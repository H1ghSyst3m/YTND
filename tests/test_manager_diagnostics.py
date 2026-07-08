from ytnd import manager_server
from ytnd.manager_server import SESSION_SIG_COOKIE, SESSION_UID_COOKIE, _sign_uid


def test_youtube_diagnostics_classifies_ytdlp_errors(client, admin_user, monkeypatch, fake_ytdlp):
    def fake_extract(ydl, url, download):
        raise manager_server.yt_dlp.utils.DownloadError("Sign in to confirm you’re not a bot")

    fake_ytdlp(manager_server, extract_info=fake_extract)
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


def test_youtube_diagnostics_classifies_generic_errors(client, admin_user, monkeypatch, fake_ytdlp):
    def fake_extract(ydl, url, download):
        raise RuntimeError("Cookie: SID=secret\nHTTP Error 403: Forbidden")

    fake_ytdlp(manager_server, extract_info=fake_extract)
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
    assert data["category"] == "forbidden"
    assert "secret" not in data["error"]


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


def test_youtube_diagnostics_rejects_non_youtube_hosts(client, admin_user, monkeypatch):
    def fail_youtube_dl(*args, **kwargs):
        raise AssertionError("YoutubeDL should not be created for non-YouTube diagnostics URLs")

    monkeypatch.setattr(manager_server.yt_dlp, "YoutubeDL", fail_youtube_dl)

    for url in (
        "https://example.com/watch?v=video123",
        "https://youtube.com.evil/watch?v=video123",
        "https://notyoutube.com/watch?v=video123",
        "ftp://youtube.com/watch?v=video123",
        "youtube.com/watch?v=video123",
        "http://[::1",
    ):
        response = client.get(
            "/api/system/youtube-diagnostics",
            params={"url": url},
            cookies={
                SESSION_UID_COOKIE: admin_user["uid"],
                SESSION_SIG_COOKIE: _sign_uid(admin_user["uid"]),
            },
        )

        assert response.status_code == 400


def test_youtube_diagnostics_allows_http_and_https_youtube_hosts():
    assert manager_server._is_youtube_diagnostics_url("https://youtube.com/watch?v=video123")
    assert manager_server._is_youtube_diagnostics_url("http://www.youtube.com/watch?v=video123")
    assert manager_server._is_youtube_diagnostics_url("https://youtu.be/video123")


def test_probe_uses_shared_ytdlp_options(fake_ytdlp):
    captured = fake_ytdlp(
        manager_server,
        extract_info=lambda ydl, url, download: {"id": "video123", "title": "Track"},
    )

    ok, reason = manager_server._probe_url_available("https://youtube.com/watch?v=video123")

    assert ok is True
    assert reason == "ok"
    assert captured["opts"]["sentinel"] == "shared"
    assert captured["base"]["quiet"] is True


def test_probe_classifies_download_errors(fake_ytdlp):
    def fake_extract(ydl, url, download):
        raise manager_server.yt_dlp.utils.DownloadError("HTTP Error 429: Too Many Requests")

    fake_ytdlp(manager_server, extract_info=fake_extract)

    ok, reason = manager_server._probe_url_available("https://youtube.com/watch?v=video123")

    assert ok is False
    assert reason.startswith("rate_limited: yt-dlp error:")


def test_probe_classifies_generic_errors(fake_ytdlp):
    def fake_extract(ydl, url, download):
        raise RuntimeError("Authorization: Bearer secret\nHTTP Error 403: Forbidden")

    fake_ytdlp(manager_server, extract_info=fake_extract)

    ok, reason = manager_server._probe_url_available("https://youtube.com/watch?v=video123")

    assert ok is False
    assert reason.startswith("forbidden: Probe failed:")
    assert "secret" not in reason
