import pytest
from ytnd.manager_server import _webdav_auth_failures
from tests.conftest import _basic_auth_header


def _propfind(client, user_id, auth_headers, depth="1"):
    return client.request(
        "PROPFIND",
        f"/webdav/{user_id}/",
        headers={**auth_headers, "Depth": depth},
    )


# ───────────────────── 1. Unauthorized challenge ─────────────────────

class TestUnauthorized:
    def test_no_auth_header_returns_401(self, client, regular_user, user_folder):
        r = client.request("PROPFIND", f"/webdav/{regular_user['uid']}/", headers={"Depth": "1"})
        assert r.status_code == 401
        assert "WWW-Authenticate" in r.headers
        assert 'Basic realm="YTND WebDAV"' in r.headers["WWW-Authenticate"]

    def test_wrong_password_returns_401(self, client, regular_user, user_folder):
        r = _propfind(client, regular_user["uid"], _basic_auth_header(regular_user["username"], "wrongpassword"))
        assert r.status_code == 401

    def test_unknown_username_returns_401(self, client, regular_user, user_folder):
        r = _propfind(client, regular_user["uid"], _basic_auth_header("nobody", "nopassword"))
        assert r.status_code == 401

    def test_malformed_basic_token_returns_401(self, client, regular_user, user_folder):
        r = client.request(
            "PROPFIND",
            f"/webdav/{regular_user['uid']}/",
            headers={"Authorization": "Basic !!!not-base64!!!", "Depth": "1"},
        )
        assert r.status_code == 401

    def test_brute_force_lockout(self, client, regular_user, user_folder):
        _webdav_auth_failures.clear()
        from ytnd.manager_server import _WEBDAV_MAX_FAILURES

        uid = regular_user["uid"]
        username = regular_user["username"]
        for _ in range(_WEBDAV_MAX_FAILURES):
            r = _propfind(client, uid, _basic_auth_header(username, "badpass"))
            assert r.status_code == 401

        r = _propfind(client, uid, _basic_auth_header(username, "badpass"))
        assert r.status_code == 429
        assert "Retry-After" in r.headers

        # Correct credentials still return 429 while locked out
        r = _propfind(client, uid, _basic_auth_header(username, regular_user["password"]))
        assert r.status_code == 429

        _webdav_auth_failures.clear()


# ───────────────────── 2. Admin / user access boundary ─────────────────────

class TestAccessBoundary:
    def test_user_can_access_own_folder(self, client, regular_user, user_folder):
        r = _propfind(client, regular_user["uid"], _basic_auth_header(regular_user["username"], regular_user["password"]))
        assert r.status_code == 207

    def test_user_cannot_access_other_user_folder(self, client, regular_user, regular_user2, user_folder):
        r = _propfind(client, regular_user2["uid"], _basic_auth_header(regular_user["username"], regular_user["password"]))
        assert r.status_code == 403

    def test_admin_can_access_any_folder(self, client, admin_user, regular_user, user_folder):
        r = _propfind(client, regular_user["uid"], _basic_auth_header(admin_user["username"], admin_user["password"]))
        assert r.status_code == 207


# ───────────────────── 3. Path traversal ─────────────────────

class TestTraversal:
    def test_dotdot_segment_returns_400_or_404(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        uid = regular_user["uid"]
        for payload in ["../etc/passwd", "%2e%2e/etc/passwd", ".."]:
            r = client.get(f"/webdav/{uid}/{payload}", headers=auth)
            # Starlette normalises traversal paths before routing, so some attempts
            # land as 403 (wrong user namespace) rather than 400/404 — all are secure.
            assert r.status_code in (400, 403, 404), (
                f"Expected secure rejection for payload {payload!r}, got {r.status_code}"
            )

    def test_nested_traversal_returns_400_or_404(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.get(f"/webdav/{regular_user['uid']}/subdir/../../track.opus", headers=auth)
        assert r.status_code in (400, 403, 404)


# ───────────────────── 4. File-extension filtering ─────────────────────

class TestExtensionFiltering:
    def test_get_allowed_audio_returns_200(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.get(f"/webdav/{regular_user['uid']}/track.opus", headers=auth)
        assert r.status_code == 200
        assert r.headers.get("content-type", "").startswith("audio/opus")

    def test_get_forbidden_extension_returns_404(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.get(f"/webdav/{regular_user['uid']}/forbidden.txt", headers=auth)
        assert r.status_code == 404

    def test_propfind_listing_excludes_forbidden_files(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = _propfind(client, regular_user["uid"], auth, depth="1")
        assert r.status_code == 207
        assert "forbidden.txt" not in r.text
        assert "track.opus" in r.text
        assert "song-list.json" in r.text

    def test_get_song_list_json_returns_200(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.get(f"/webdav/{regular_user['uid']}/song-list.json", headers=auth)
        assert r.status_code == 200


# ───────────────────── 5. PROPFIND Depth header behaviour ─────────────────────

class TestPropfindDepth:
    def test_depth_1_returns_207_with_file_entries(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = _propfind(client, regular_user["uid"], auth, depth="1")
        assert r.status_code == 207
        assert r.headers.get("content-type", "").startswith("application/xml")
        assert "d:multistatus" in r.text
        assert "track.opus" in r.text

    def test_depth_0_returns_207_collection_only(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = _propfind(client, regular_user["uid"], auth, depth="0")
        assert r.status_code == 207
        assert "d:collection" in r.text
        assert "track.opus" not in r.text

    def test_invalid_depth_returns_400(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = _propfind(client, regular_user["uid"], auth, depth="infinity")
        assert r.status_code == 400

    def test_propfind_response_contains_dav_headers(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = _propfind(client, regular_user["uid"], auth, depth="1")
        assert r.headers.get("DAV") == "1"

    def test_propfind_file_returns_207(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.request("PROPFIND", f"/webdav/{regular_user['uid']}/track.opus", headers=auth)
        assert r.status_code == 207
        assert "track.opus" in r.text

    def test_root_get_returns_json_file_list(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.get(f"/webdav/{regular_user['uid']}/", headers=auth)
        assert r.status_code == 200
        data = r.json()
        assert "files" in data
        assert "track.opus" in data["files"]
        assert "forbidden.txt" not in data["files"]

    def test_options_returns_200_with_allow_header(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.request("OPTIONS", f"/webdav/{regular_user['uid']}/", headers=auth)
        assert r.status_code == 200
        assert "PROPFIND" in r.headers.get("Allow", "")

    def test_head_file_returns_200_with_content_headers(self, client, regular_user, user_folder):
        auth = _basic_auth_header(regular_user["username"], regular_user["password"])
        r = client.head(f"/webdav/{regular_user['uid']}/track.opus", headers=auth)
        assert r.status_code == 200
        assert r.headers.get("Content-Type", "").startswith("audio/opus")
        assert int(r.headers.get("Content-Length", "0")) > 0
