import os
import json
import base64
import tempfile
import pytest
from pathlib import Path
from fastapi.testclient import TestClient
from passlib.context import CryptContext

_tmpdir = tempfile.mkdtemp(prefix="ytnd_test_")
os.environ.setdefault("MANAGER_SECRET", "test-secret-conftest")
os.environ["DATA_ROOT"] = _tmpdir
os.environ["WEBDAV_ENABLED"] = "true"

from ytnd import database
from ytnd.config import OUTPUT_ROOT
from ytnd.manager_server import app, _webdav_auth_failures

_pwd = CryptContext(schemes=["argon2"], deprecated="auto")


def _create_user(uid: str, username: str, password: str, role: str = "user") -> dict:
    try:
        database.create_user_with_credentials(uid, username, _pwd.hash(password), role=role)
    except ValueError:
        pass
    return {"uid": uid, "username": username, "password": password, "role": role}


def _basic_auth_header(username: str, password: str) -> dict:
    token = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {"Authorization": f"Basic {token}"}


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def regular_user():
    return _create_user("ruser1", "ruser1", "rpassword1", role="user")


@pytest.fixture(scope="session")
def regular_user2():
    return _create_user("ruser2", "ruser2", "rpassword2", role="user")


@pytest.fixture(scope="session")
def admin_user():
    return _create_user("radmin1", "radmin1", "radminpassword1", role="admin")


@pytest.fixture(scope="session")
def user_folder(regular_user):
    folder = OUTPUT_ROOT / regular_user["uid"]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "song-list.json").write_text(
        json.dumps([{"title": "Track", "artist": "Artist"}]), encoding="utf-8"
    )
    (folder / "track.opus").write_bytes(b"FAKE_AUDIO")
    (folder / "forbidden.txt").write_text("nope", encoding="utf-8")
    return folder


@pytest.fixture
def fake_ytdlp(monkeypatch):
    def install(module, *, extract_info=None, download=None):
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

            def extract_info(self, url, download_arg=None, **kwargs):
                if "download" in kwargs:
                    download_arg = kwargs["download"]
                if extract_info:
                    return extract_info(self, url, download_arg)
                return {"id": "video123", "title": "Track"}

            def download(self, urls):
                if download:
                    return download(self, urls)
                return 0

        monkeypatch.setattr(module, "build_ytdlp_options", fake_build_options)
        monkeypatch.setattr(module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
        return captured

    return install
