from pathlib import Path
from types import SimpleNamespace
from datetime import datetime, timezone
import json
import os
import subprocess

import pytest

from ytnd import database
from ytnd.downloader import Downloader
import ytnd.downloader as downloader_module
import ytnd.manager_server as manager_module
from ytnd.manager_server import SESSION_SIG_COOKIE, SESSION_UID_COOKIE, _sign_uid


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


def test_process_entry_records_server_download_time(monkeypatch):
    uid = "downloadtime"
    downloader = Downloader(uid)
    entry = SimpleNamespace(
        id="video-time",
        title="Timed Song",
        uploader="Timed Artist",
        url="https://example.test/watch?v=video-time",
        upload_date="2024-01-02",
    )

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def download(self, urls):
            Path(self.opts["outtmpl"].replace("%(ext)s", "opus")).write_bytes(
                b"audio"
            )
            for hook in self.opts.get("progress_hooks", []):
                hook({"status": "finished"})
            return 0

    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(Downloader, "_set_tags", lambda self, path, entry: None)
    monkeypatch.setattr(
        Downloader, "_save_cover", lambda self, entry: "video-time.jpg"
    )

    downloader._process_entry(entry)

    song = downloader._song_cache["video-time"]
    assert song["date"] == "2024-01-02"
    downloaded_at = song["downloaded_at"]
    assert downloaded_at.endswith("Z")
    assert (
        datetime.fromisoformat(downloaded_at.replace("Z", "+00:00")).tzinfo
        is not None
    )


def test_manager_write_song_list_writes_valid_json_atomically():
    uid = "atomicmanager"
    folder = manager_module.OUTPUT_ROOT / uid

    manager_module._write_song_list(
        uid,
        [{"id": "song1", "title": "Atomic", "artist": "Writer"}],
    )

    song_list = folder / "song-list.json"
    assert json.loads(song_list.read_text(encoding="utf-8")) == [
        {"id": "song1", "title": "Atomic", "artist": "Writer"}
    ]
    assert not list(folder.glob(".song-list.json.*.tmp"))


def test_downloader_save_song_cache_uses_atomic_json_writer(monkeypatch):
    downloader = Downloader("atomicdownloader")
    downloader._song_cache = {
        "song2": {"id": "song2", "title": "Atomic", "artist": "Downloader"}
    }
    calls = []
    original = downloader_module.write_json_atomic

    def spy_write_json_atomic(path, data, **kwargs):
        calls.append((path, data))
        return original(path, data, **kwargs)

    monkeypatch.setattr(
        downloader_module, "write_json_atomic", spy_write_json_atomic
    )

    downloader._save_song_cache()

    assert calls == [
        (
            downloader.song_list_path,
            [{"id": "song2", "title": "Atomic", "artist": "Downloader"}],
        )
    ]
    assert json.loads(downloader.song_list_path.read_text(encoding="utf-8")) == [
        {"id": "song2", "title": "Atomic", "artist": "Downloader"}
    ]


def test_api_songs_backfills_downloaded_at_from_audio_mtime(client):
    uid = "songdateapi"
    try:
        database.add_user(uid)
    except ValueError:
        pass
    folder = manager_module.OUTPUT_ROOT / uid
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "song-list.json").write_text(
        json.dumps([{"id": "video-api", "title": "Fresh", "artist": "Artist"}]),
        encoding="utf-8",
    )
    audio = folder / "Fresh # Artist.opus"
    audio.write_bytes(b"audio")
    timestamp = 1_750_000_000
    os.utime(audio, (timestamp, timestamp))
    expected = (
        datetime.fromtimestamp(timestamp, tz=timezone.utc)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z")
    )

    response = client.get(
        "/api/songs",
        params={"user_id": uid},
        cookies={
            SESSION_UID_COOKIE: uid,
            SESSION_SIG_COOKIE: _sign_uid(uid),
        },
    )

    assert response.status_code == 200
    song = response.json()["songs"][0]
    assert song["downloaded_at"] == expected
    assert song["file_available"] is True

    saved = json.loads((folder / "song-list.json").read_text(encoding="utf-8"))
    assert saved[0]["downloaded_at"] == expected


def test_api_songs_returns_null_downloaded_at_without_audio(client):
    uid = "songdatenull"
    try:
        database.add_user(uid)
    except ValueError:
        pass
    folder = manager_module.OUTPUT_ROOT / uid
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "song-list.json").write_text(
        json.dumps([{"id": "video-null", "title": "Missing", "artist": "Artist"}]),
        encoding="utf-8",
    )

    response = client.get(
        "/api/songs",
        params={"user_id": uid},
        cookies={
            SESSION_UID_COOKIE: uid,
            SESSION_SIG_COOKIE: _sign_uid(uid),
        },
    )

    assert response.status_code == 200
    song = response.json()["songs"][0]
    assert song["downloaded_at"] is None
    assert song["file_available"] is False


def test_yt_dlp_options_use_configured_deno_path(monkeypatch, tmp_path):
    downloader_module._find_runtime_executable.cache_clear()
    deno = tmp_path / "deno"
    deno.write_text("", encoding="utf-8")

    monkeypatch.setenv("YTND_JS_RUNTIME_PATH", str(deno))
    monkeypatch.delenv("YTND_JS_RUNTIME", raising=False)

    opts = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)

    assert opts["js_runtimes"] == {"deno": {"path": str(deno)}}
    assert "cookiefile" not in opts


def test_yt_dlp_options_fall_back_to_node_when_deno_is_missing(monkeypatch):
    downloader_module._find_runtime_executable.cache_clear()
    monkeypatch.delenv("YTND_JS_RUNTIME_PATH", raising=False)
    monkeypatch.delenv("YTND_JS_RUNTIME", raising=False)

    def fake_which(binary, path=None):
        return "C:/node/node.exe" if binary == "node" else None

    monkeypatch.setattr(downloader_module.shutil, "which", fake_which)

    try:
        opts = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)
        assert opts["js_runtimes"] == {"node": {"path": "C:/node/node.exe"}}
    finally:
        downloader_module._find_runtime_executable.cache_clear()


def test_runtime_lookup_is_cached_while_path_is_unchanged(monkeypatch):
    downloader_module._find_runtime_executable.cache_clear()
    monkeypatch.delenv("YTND_JS_RUNTIME_PATH", raising=False)
    monkeypatch.delenv("YTND_JS_RUNTIME", raising=False)

    calls = []

    def fake_which(binary, path=None):
        calls.append((binary, path))
        return "C:/node/node.exe" if binary == "node" else None

    monkeypatch.setattr(downloader_module.shutil, "which", fake_which)

    try:
        first = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)
        second = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)

        assert first["js_runtimes"] == {"node": {"path": "C:/node/node.exe"}}
        assert second["js_runtimes"] == {"node": {"path": "C:/node/node.exe"}}
        assert [binary for binary, _ in calls] == ["deno", "node"]
    finally:
        downloader_module._find_runtime_executable.cache_clear()


def test_cookie_detection_remains_uncached(monkeypatch, tmp_path):
    deno = tmp_path / "deno"
    deno.write_text("", encoding="utf-8")
    cookie_file = tmp_path / "cookies.txt"

    monkeypatch.setenv("YTND_JS_RUNTIME_PATH", str(deno))
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)

    first = downloader_module.apply_yt_dlp_defaults({}, use_cookies=True)
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )
    second = downloader_module.apply_yt_dlp_defaults({}, use_cookies=True)

    assert "cookiefile" not in first
    assert second["cookiefile"] == str(cookie_file)


def test_cookie_status_validates_netscape_file(monkeypatch, tmp_path):
    cookie_file = tmp_path / "cookies.txt"
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)

    assert downloader_module.get_cookies_status()["status"] == "missing"

    cookie_file.write_text("", encoding="utf-8")
    assert downloader_module.get_cookies_status()["status"] == "empty"

    cookie_file.write_text("not a cookies file\n", encoding="utf-8")
    assert downloader_module.get_cookies_status()["status"] == "invalid"

    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )

    status = downloader_module.get_cookies_status()
    opts = downloader_module.apply_yt_dlp_defaults({}, use_cookies=True)

    assert status["status"] == "present"
    assert "1 YouTube row" in status["detail"]
    assert opts["cookiefile"] == str(cookie_file)


def test_fetch_metadata_retries_without_invalid_cookies(monkeypatch, tmp_path):
    cookie_file = tmp_path / "cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)

    calls = []

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts
            calls.append(opts)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, url, download):
            if "cookiefile" in self.opts:
                self.opts["logger"].warning("The provided YouTube account cookies are no longer valid")
                raise downloader_module.yt_dlp.utils.DownloadError("Sign in to confirm you're not a bot")
            return {
                "id": "video123",
                "title": "Song",
                "uploader": "Artist",
                "webpage_url": url,
            }

    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)

    data, err = Downloader("metaretry")._fetch_metadata("https://youtube.com/watch?v=video123")

    assert err is None
    assert data["id"] == "video123"
    assert "cookiefile" in calls[0]
    assert "cookiefile" not in calls[1]


def test_probe_preserves_retry_without_cookies_note(monkeypatch, tmp_path):
    deno = tmp_path / "deno"
    deno.write_text("", encoding="utf-8")
    cookie_file = tmp_path / "cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )

    monkeypatch.setenv("YTND_JS_RUNTIME_PATH", str(deno))
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, url, download):
            if "cookiefile" in self.opts:
                self.opts["logger"].warning("The provided YouTube account cookies are no longer valid")
                raise manager_module.yt_dlp.utils.DownloadError("cookies failed")
            raise manager_module.yt_dlp.utils.DownloadError("retry still failed")

    monkeypatch.setattr(manager_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)

    ok, reason = manager_module._probe_url_available("https://youtube.com/watch?v=video123")

    assert ok is False
    assert "Retried without cookies" in reason


def test_save_cover_preserves_retry_without_cookies_note(monkeypatch, tmp_path):
    deno = tmp_path / "deno"
    deno.write_text("", encoding="utf-8")
    cookie_file = tmp_path / "cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )

    monkeypatch.setenv("YTND_JS_RUNTIME_PATH", str(deno))
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)

    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def download(self, urls):
            if "cookiefile" in self.opts:
                self.opts["logger"].warning("The provided YouTube account cookies are no longer valid")
                raise downloader_module.yt_dlp.utils.DownloadError("cookies failed")
            raise downloader_module.yt_dlp.utils.DownloadError("retry still failed")

    monkeypatch.setattr(downloader_module.yt_dlp, "YoutubeDL", FakeYoutubeDL)

    downloader = Downloader("coverretry")
    entry = SimpleNamespace(id="video456", url="https://example.test/watch?v=video456")

    with pytest.raises(RuntimeError, match="Retried without cookies"):
        downloader._save_cover(entry)


def test_yt_dlp_error_classification_reports_missing_js_runtime():
    message = downloader_module.classify_yt_dlp_error(
        "WARNING: No supported JavaScript runtime could be found"
    )

    assert "JavaScript runtime" in message
    assert "Deno" in message


def test_dashboard_reports_js_runtime_and_cookie_detail(client, admin_user, monkeypatch, tmp_path):
    cookie_file = tmp_path / "cookies.txt"
    cookie_file.write_text(
        "# Netscape HTTP Cookie File\n"
        ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(downloader_module, "COOKIES_FILE", cookie_file)
    monkeypatch.setattr(
        manager_module,
        "get_js_runtime_status",
        lambda: {"status": "ok", "runtime": "deno", "path": "/home/container/bin/deno"},
    )

    response = client.get(
        "/api/dashboard",
        cookies={
            SESSION_UID_COOKIE: admin_user["uid"],
            SESSION_SIG_COOKIE: _sign_uid(admin_user["uid"]),
        },
    )

    assert response.status_code == 200
    admin_data = response.json()["adminData"]
    assert admin_data["jsRuntimeStatus"]["runtime"] == "deno"
    assert admin_data["cookiesStatus"]["status"] == "present"
    assert "YouTube row" in admin_data["cookiesStatus"]["detail"]
