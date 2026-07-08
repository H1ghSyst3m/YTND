from pathlib import Path
from types import SimpleNamespace
import subprocess

from ytnd import database
from ytnd.downloader import Downloader
import ytnd.downloader as downloader_module


def test_add_urls_deduplicates_existing_and_new_urls():
    uid = "queuededupe"
    try:
        database.add_user(uid)
    except ValueError:
        pass

    database.set_queue(uid, ["https://example.test/a"])
    downloader = Downloader(uid)
    downloader.add_urls(
        [
            "https://example.test/b",
            "https://example.test/b",
            "https://example.test/a",
            "",
            "  https://example.test/c  ",
        ]
    )

    assert database.get_queue(uid) == [
        "https://example.test/a",
        "https://example.test/b",
        "https://example.test/c",
    ]


def test_save_cover_allows_ffmpeg_from_path(monkeypatch):
    uid = "coverffmpeg"
    downloader = Downloader(uid)
    entry = SimpleNamespace(id="video123", url="https://example.test/watch?v=video123")
    captured = {}

    def fake_build_options(base):
        captured["base"] = base
        opts = dict(base)
        opts["sentinel"] = "shared"
        return opts

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def download(self, urls):
            Path(self.opts["outtmpl"].replace("%(ext)s", "webp")).write_bytes(b"fake-webp")
            return 0

    def fake_run(cmd, check, timeout):
        assert cmd[0] == "ffmpeg"
        assert check is True
        assert timeout == 15
        Path(cmd[-1]).write_bytes(b"fake-jpg")
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(downloader_module, "FFMPEG_EXECUTABLE", "ffmpeg")
    monkeypatch.setattr(downloader_module, "build_ytdlp_options", fake_build_options)
    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(downloader_module.subprocess, "run", fake_run)

    assert downloader._save_cover(entry) == "video123.jpg"
    assert captured["opts"]["sentinel"] == "shared"
    assert captured["base"]["writethumbnail"] is True
    assert (downloader.cover_dir / "video123.jpg").exists()
    assert not (downloader.cover_dir / "video123.webp").exists()


def test_fetch_metadata_uses_shared_ytdlp_options(monkeypatch):
    uid = "metadataopts"
    try:
        database.add_user(uid)
    except ValueError:
        pass

    captured = {}

    def fake_build_options(base):
        captured["base"] = base
        opts = dict(base)
        opts["sentinel"] = "shared"
        return opts

    class FakeYoutubeDL:
        def __init__(self, opts):
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, url, download):
            return {
                "id": "video123",
                "title": "Track",
                "uploader": "Artist",
                "webpage_url": url,
            }

    monkeypatch.setattr(downloader_module, "build_ytdlp_options", fake_build_options)
    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)

    data, err = Downloader(uid)._fetch_metadata("https://youtube.com/watch?v=video123")

    assert err is None
    assert data["id"] == "video123"
    assert captured["opts"]["sentinel"] == "shared"
    assert captured["base"]["quiet"] is True


def test_process_entry_uses_shared_ytdlp_options(monkeypatch):
    uid = "downloadopts"
    downloader = Downloader(uid)
    captured = {}

    def fake_build_options(base):
        captured["base"] = base
        opts = dict(base)
        opts["sentinel"] = "shared"
        return opts

    class FakeYoutubeDL:
        def __init__(self, opts):
            captured["opts"] = opts
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def download(self, urls):
            Path(self.opts["outtmpl"].replace("%(ext)s", "opus")).write_bytes(b"fake-opus")
            return 0

    entry = SimpleNamespace(
        id="video123",
        title="Track",
        uploader="Artist",
        url="https://example.test/watch?v=video123",
        source_url="https://example.test/watch?v=video123",
        album=None,
        upload_date=None,
        description="",
    )

    monkeypatch.setattr(downloader_module, "build_ytdlp_options", fake_build_options)
    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(Downloader, "_save_cover", lambda self, entry: None)

    downloader._process_entry(entry)

    assert captured["opts"]["sentinel"] == "shared"
    assert captured["base"]["format"] == "bestaudio/best"


def test_run_keeps_metadata_failures_in_queue(monkeypatch):
    uid = "queuekeepmeta"
    try:
        database.add_user(uid)
    except ValueError:
        pass

    database.set_queue(uid, ["https://example.test/ok", "https://example.test/fail"])

    def fake_fetch(self, url):
        if url.endswith("/fail"):
            return None, "Sign in to confirm you’re not a bot"
        return {
            "id": "ok",
            "title": "Track",
            "uploader": "Artist",
            "webpage_url": url,
        }, None

    monkeypatch.setenv("YTDLP_ITEM_DELAY", "0")
    monkeypatch.setattr(Downloader, "_fetch_metadata", fake_fetch)
    monkeypatch.setattr(Downloader, "_process_entry", lambda self, entry: None)

    result = Downloader(uid).run(workers=1)

    assert result["downloaded"] == 1
    assert result["errors"] == 1
    assert database.get_queue(uid) == ["https://example.test/fail"]


def test_run_keeps_download_failures_in_queue(monkeypatch):
    uid = "queuekeepdownload"
    try:
        database.add_user(uid)
    except ValueError:
        pass

    database.set_queue(uid, ["https://example.test/ok", "https://example.test/bad"])

    def fake_fetch(self, url):
        title = "Bad" if url.endswith("/bad") else "Ok"
        return {
            "id": title.lower(),
            "title": title,
            "uploader": "Artist",
            "webpage_url": url,
        }, None

    def fake_process(self, entry):
        if entry.title == "Bad":
            raise downloader_module.DownloadError(entry, "HTTP Error 429: Too Many Requests")

    monkeypatch.setenv("YTDLP_ITEM_DELAY", "0")
    monkeypatch.setattr(Downloader, "_fetch_metadata", fake_fetch)
    monkeypatch.setattr(Downloader, "_process_entry", fake_process)

    result = Downloader(uid).run(workers=1)

    assert result["downloaded"] == 1
    assert result["errors"] == 1
    assert result["failed"][0]["category"] == "rate_limited"
    assert database.get_queue(uid) == ["https://example.test/bad"]


def test_run_staggers_multi_worker_submission(monkeypatch):
    uid = "queuepaceworkers"
    try:
        database.add_user(uid)
    except ValueError:
        pass

    urls = [
        "https://example.test/one",
        "https://example.test/two",
        "https://example.test/three",
    ]
    database.set_queue(uid, urls)

    def fake_fetch(self, url):
        return {
            "id": url.rsplit("/", 1)[-1],
            "title": url.rsplit("/", 1)[-1],
            "uploader": "Artist",
            "webpage_url": url,
        }, None

    sleeps = []
    processed = []

    monkeypatch.setenv("YTDLP_ITEM_DELAY", "0.25")
    monkeypatch.setattr(downloader_module.time, "sleep", lambda seconds: sleeps.append(seconds))
    monkeypatch.setattr(Downloader, "_fetch_metadata", fake_fetch)
    monkeypatch.setattr(Downloader, "_process_entry", lambda self, entry: processed.append(entry.source_url))

    result = Downloader(uid).run(workers=3)

    assert result["downloaded"] == 3
    assert result["errors"] == 0
    assert sleeps == [0.25, 0.25]
    assert sorted(processed) == sorted(urls)
