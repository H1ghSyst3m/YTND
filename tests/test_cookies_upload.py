from ytnd import manager_server as manager_module
from ytnd.manager_server import (
    SESSION_SIG_COOKIE,
    SESSION_UID_COOKIE,
    _generate_csrf_token,
    _sign_uid,
)


VALID_COOKIES = (
    "# Netscape HTTP Cookie File\n"
    ".youtube.com\tTRUE\t/\tFALSE\t0\tSID\tvalue\n"
)


def _session_cookies(user: dict) -> dict:
    return {
        SESSION_UID_COOKIE: user["uid"],
        SESSION_SIG_COOKIE: _sign_uid(user["uid"]),
    }


def _upload(client, user: dict, content: str, csrf_token: str | None):
    data = {}
    if csrf_token is not None:
        data["csrf_token"] = csrf_token

    return client.post(
        "/api/cookies",
        cookies=_session_cookies(user),
        data=data,
        files={"file": ("cookies.txt", content.encode("utf-8"), "text/plain")},
    )


def test_admin_can_upload_valid_cookies_file(client, admin_user, monkeypatch, tmp_path):
    cookies_file = tmp_path / "cookies.txt"
    monkeypatch.setattr(manager_module, "COOKIES_FILE", cookies_file)

    response = _upload(
        client,
        admin_user,
        VALID_COOKIES,
        _generate_csrf_token(admin_user["uid"]),
    )

    assert response.status_code == 200
    assert response.json()["cookiesStatus"]["status"] == "present"
    assert cookies_file.read_text(encoding="utf-8") == VALID_COOKIES


def test_invalid_cookies_upload_does_not_replace_existing_file(client, admin_user, monkeypatch, tmp_path):
    cookies_file = tmp_path / "cookies.txt"
    cookies_file.write_text(VALID_COOKIES, encoding="utf-8")
    monkeypatch.setattr(manager_module, "COOKIES_FILE", cookies_file)

    response = _upload(
        client,
        admin_user,
        "not a cookies file\n",
        _generate_csrf_token(admin_user["uid"]),
    )

    assert response.status_code == 400
    assert "Netscape" in response.json()["detail"]
    assert cookies_file.read_text(encoding="utf-8") == VALID_COOKIES


def test_regular_user_cannot_upload_cookies_file(client, regular_user, monkeypatch, tmp_path):
    cookies_file = tmp_path / "cookies.txt"
    monkeypatch.setattr(manager_module, "COOKIES_FILE", cookies_file)

    response = _upload(
        client,
        regular_user,
        VALID_COOKIES,
        _generate_csrf_token(regular_user["uid"]),
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Admin access required"
    assert not cookies_file.exists()


def test_cookies_upload_requires_csrf_token(client, admin_user, monkeypatch, tmp_path):
    cookies_file = tmp_path / "cookies.txt"
    monkeypatch.setattr(manager_module, "COOKIES_FILE", cookies_file)

    response = _upload(client, admin_user, VALID_COOKIES, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "CSRF token invalid"
    assert not cookies_file.exists()
