from ytnd.manager_server import SESSION_SIG_COOKIE, SESSION_UID_COOKIE, _sign_uid


def test_ping_rejects_unsigned_session_cookie(client, regular_user):
    response = client.get(
        "/api/ping",
        cookies={
            SESSION_UID_COOKIE: regular_user["uid"],
            SESSION_SIG_COOKIE: "invalid-signature",
        },
    )

    assert response.status_code == 200
    assert response.json() == {"authorized": False}


def test_ping_accepts_signed_session_cookie(client, regular_user):
    response = client.get(
        "/api/ping",
        cookies={
            SESSION_UID_COOKIE: regular_user["uid"],
            SESSION_SIG_COOKIE: _sign_uid(regular_user["uid"]),
        },
    )

    assert response.status_code == 200
    assert response.json() == {"authorized": True}

def test_ping_rejects_unknown_signed_session_cookie(client):
    uid = "missing-user"
    response = client.get(
        "/api/ping",
        cookies={
            SESSION_UID_COOKIE: uid,
            SESSION_SIG_COOKIE: _sign_uid(uid),
        },
    )

    assert response.status_code == 200
    assert response.json() == {"authorized": False}
