from ytnd import manager_server
from ytnd.manager_server import SESSION_SIG_COOKIE, SESSION_UID_COOKIE, _sign_uid


def test_youtube_diagnostics_classifies_ytdlp_errors(client, admin_user, monkeypatch):
    class FakeYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, url, download):
            raise manager_server.yt_dlp.utils.DownloadError("Sign in to confirm you’re not a bot")

    monkeypatch.setattr(manager_server.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(manager_server, "_check_cookies_status", lambda: {"status": "auth_present"})
    monkeypatch.setattr(manager_server, "_check_ytdlp_status", lambda: {"status": "ok", "version": "test"})

    response = client.get(
        "/api/system/youtube-diagnostics",
        params={"url": "https://youtube.com/watch?v=video123"},
        cookies={
            SESSION_UID_COOKIE: admin_user["uid"],
            SESSION_SIG_COOKIE: _sign_uid(admin_user["uid"]),
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is False
    assert data["category"] == "bot_challenge"
    assert "bot" in data["error"].lower()


def test_youtube_diagnostics_requires_admin(client, regular_user):
    response = client.get(
        "/api/system/youtube-diagnostics",
        params={"url": "https://youtube.com/watch?v=video123"},
        cookies={
            SESSION_UID_COOKIE: regular_user["uid"],
            SESSION_SIG_COOKIE: _sign_uid(regular_user["uid"]),
        },
    )

    assert response.status_code == 403


def test_probe_uses_shared_ytdlp_options(monkeypatch):
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
            return {"id": "video123", "title": "Track"}

    monkeypatch.setattr(manager_server, "build_ytdlp_options", fake_build_options)
    monkeypatch.setattr(manager_server.yt_dlp, "YoutubeDL", FakeYoutubeDL)

    ok, reason = manager_server._probe_url_available("https://youtube.com/watch?v=video123")

    assert ok is True
    assert reason == "ok"
    assert captured["opts"]["sentinel"] == "shared"
    assert captured["base"]["quiet"] is True
