from pathlib import Path
from types import SimpleNamespace
import subprocess

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


def test_yt_dlp_options_use_configured_deno_path(monkeypatch, tmp_path):
    deno = tmp_path / "deno"
    deno.write_text("", encoding="utf-8")

    monkeypatch.setenv("YTND_JS_RUNTIME_PATH", str(deno))
    monkeypatch.delenv("YTND_JS_RUNTIME", raising=False)

    opts = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)

    assert opts["js_runtimes"] == {"deno": {"path": str(deno)}}
    assert "cookiefile" not in opts


def test_yt_dlp_options_fall_back_to_node_when_deno_is_missing(monkeypatch):
    monkeypatch.delenv("YTND_JS_RUNTIME_PATH", raising=False)
    monkeypatch.delenv("YTND_JS_RUNTIME", raising=False)

    def fake_which(binary):
        return "C:/node/node.exe" if binary == "node" else None

    monkeypatch.setattr(downloader_module.shutil, "which", fake_which)

    opts = downloader_module.apply_yt_dlp_defaults({}, use_cookies=False)

    assert opts["js_runtimes"] == {"node": {"path": "C:/node/node.exe"}}


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
