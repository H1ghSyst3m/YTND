import json
import os
import subprocess
import sys
from pathlib import Path


def test_cli_entrypoint_is_registered():
    pyproject = Path(__file__).resolve().parents[1] / "pyproject.toml"
    assert 'ytnd = "ytnd.cli:main"' in pyproject.read_text(encoding="utf-8")


def test_initial_admin_bootstrap_uses_generated_uid(tmp_path):
    project_root = Path(__file__).resolve().parents[1]
    data_root = tmp_path / "data"
    env = os.environ.copy()
    env.update(
        {
            "DATA_ROOT": str(data_root),
            "MANAGER_SECRET": "test-secret",
            "INITIAL_ADMIN_USERNAME": "bootadmin",
            "INITIAL_ADMIN_PASSWORD": "bootpassword",
            "WEBDAV_ENABLED": "false",
        }
    )
    env["PYTHONPATH"] = str(project_root)

    code = """
import json
import ytnd
from ytnd import database

user = database.get_user_by_username('bootadmin')
print(json.dumps(user))
"""
    result = subprocess.run(
        [sys.executable, "-c", code],
        cwd=project_root,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )

    user = json.loads(result.stdout.strip())
    assert user["username"] == "bootadmin"
    assert user["role"] == "admin"
    assert user["uid"] != "admin"
    assert len(user["uid"]) == 12


def test_manager_cli_module_help_runs():
    result = subprocess.run(
        [sys.executable, "-m", "ytnd.cli", "--help"],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )

    assert "YTN Downloader" in result.stdout
    assert "--workers" in result.stdout
