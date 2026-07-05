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

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

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
    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(downloader_module.subprocess, "run", fake_run)

    assert downloader._save_cover(entry) == "video123.jpg"
    assert (downloader.cover_dir / "video123.jpg").exists()
    assert not (downloader.cover_dir / "video123.webp").exists()
