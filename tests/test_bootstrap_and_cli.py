import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def test_cli_entrypoint_is_registered():
    pyproject = Path(__file__).resolve().parents[1] / "pyproject.toml"
    assert 'ytnd = "ytnd.cli:main"' in pyproject.read_text(encoding="utf-8")


def test_pelican_egg_installs_deno_after_destructive_repo_sync():
    egg = Path(__file__).resolve().parents[1] / "egg-ytnd-manager.yaml"
    content = egg.read_text(encoding="utf-8")

    sync_idx = content.index("rsync -a --delete")
    mkdir_idx = content.index("mkdir -p data bin")
    deno_idx = content.index('echo "Installing Deno ${DENO_VERSION}..."')
    ffmpeg_idx = content.index('echo "Installing static FFmpeg..."')
    final_deno_check_idx = content.rindex("test -x /mnt/server/bin/deno")
    done_idx = content.index('echo "Installation completed..."')

    assert "export YTND_JS_RUNTIME_PATH=/home/container/bin/deno" in content
    assert content.count('echo "Installing Deno ${DENO_VERSION}..."') == 1
    assert sync_idx < mkdir_idx < deno_idx < done_idx
    assert "sha256sum -c" in content
    assert 'unzip -p "/tmp/${DENO_ASSET}" deno > /mnt/server/bin/deno.tmp' in content
    assert "mv /mnt/server/bin/deno.tmp /mnt/server/bin/deno" in content
    assert ffmpeg_idx < final_deno_check_idx < done_idx
    assert "test -x /mnt/server/bin/ffmpeg" in content


def test_initial_admin_bootstrap_uses_generated_uid():
    project_root = Path(__file__).resolve().parents[1]
    tmp_parent = Path("C:/tmp") if os.name == "nt" else Path(tempfile.gettempdir())
    tmp_parent.mkdir(parents=True, exist_ok=True)
    data_root = Path(tempfile.mkdtemp(prefix="ytnd_bootstrap_", dir=tmp_parent)) / "data"
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
