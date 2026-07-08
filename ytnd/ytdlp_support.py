from __future__ import annotations

import importlib.metadata
import json
import os
import re
import shutil
import subprocess
import time
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

from .config import COOKIES_FILE


YOUTUBE_AUTH_COOKIE_NAMES = {
    "LOGIN_INFO",
    "SAPISID",
    "__Secure-1PAPISID",
    "__Secure-3PAPISID",
}


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int, minimum: int = 1, maximum: int = 64) -> int:
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    try:
        parsed = int(value)
    except ValueError:
        return default
    return max(minimum, min(maximum, parsed))


def env_float(name: str, default: float, minimum: float = 0.0, maximum: float = 60.0) -> float:
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    try:
        parsed = float(value)
    except ValueError:
        return default
    return max(minimum, min(maximum, parsed))


def metadata_workers(default: int = 1) -> int:
    return env_int("YTDLP_METADATA_WORKERS", default, minimum=1, maximum=8)


def download_workers(default: int = 1) -> int:
    return env_int("DOWNLOAD_WORKERS", default, minimum=1, maximum=8)


def item_delay(default: float = 1.5) -> float:
    return env_float("YTDLP_ITEM_DELAY", default, minimum=0.0, maximum=30.0)


def android_retry_enabled() -> bool:
    return _env_bool("YTDLP_ANDROID_RETRY", False)


def _version_tuple(version_text: str) -> tuple[int, ...]:
    parts = re.findall(r"\d+", version_text or "")
    return tuple(int(p) for p in parts[:3]) if parts else ()


def _runtime_version(path: str, runtime: str) -> Optional[str]:
    try:
        if runtime == "node":
            result = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=3)
        elif runtime == "deno":
            result = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=3)
        elif runtime == "quickjs":
            result = subprocess.run([path, "-v"], capture_output=True, text=True, timeout=3)
        else:
            return None
    except Exception:
        return None

    if result.returncode != 0:
        return None
    output = (result.stdout or result.stderr or "").strip()
    return output.splitlines()[0].strip() if output else None


@dataclass(frozen=True)
class RuntimeStatus:
    status: str
    runtime: Optional[str] = None
    path: Optional[str] = None
    version: Optional[str] = None
    detail: Optional[str] = None


def detect_js_runtime() -> RuntimeStatus:
    requested_runtime = (os.getenv("YTDLP_JS_RUNTIME") or "").strip().lower()
    requested_path = (os.getenv("YTDLP_JS_RUNTIME_PATH") or "").strip()

    if requested_runtime in {"none", "off", "disabled"}:
        return RuntimeStatus("disabled", detail="JavaScript runtime disabled by YTDLP_JS_RUNTIME")

    candidates: list[str]
    if requested_runtime:
        candidates = [requested_runtime]
    else:
        candidates = ["deno", "node", "quickjs"]

    for runtime in candidates:
        if runtime not in {"deno", "node", "quickjs"}:
            continue

        path = requested_path if requested_runtime == runtime and requested_path else shutil.which(runtime)
        if not path:
            continue

        version = _runtime_version(path, runtime)
        if not version:
            continue

        if runtime == "deno" and _version_tuple(version) < (2, 3):
            continue
        if runtime == "node" and _version_tuple(version) < (22,):
            continue

        return RuntimeStatus("ok", runtime=runtime, path=path, version=version)

    detail = "No supported JavaScript runtime found. Install Deno 2.3+ or Node.js 22+."
    if requested_runtime:
        detail = f"Configured runtime {requested_runtime!r} was not usable."
    return RuntimeStatus("missing", detail=detail)


def ytdlp_ejs_status() -> Dict[str, Optional[str]]:
    try:
        version = importlib.metadata.version("yt-dlp-ejs")
        return {"status": "ok", "version": version}
    except importlib.metadata.PackageNotFoundError:
        return {"status": "missing", "detail": "Install yt-dlp[default] to provide yt-dlp-ejs."}


def _merge_extractor_args(base: Dict[str, Dict[str, list[str]]], extra: Any) -> Dict[str, Dict[str, list[str]]]:
    if not isinstance(extra, dict):
        return base

    merged = {k: {kk: list(vv) for kk, vv in v.items()} for k, v in base.items()}
    for ie_key, args in extra.items():
        if not isinstance(ie_key, str) or not isinstance(args, dict):
            continue
        target = merged.setdefault(ie_key, {})
        for arg_key, values in args.items():
            if not isinstance(arg_key, str):
                continue
            if isinstance(values, str):
                target[arg_key] = [values]
            elif isinstance(values, Iterable) and not isinstance(values, dict):
                target[arg_key] = [str(v) for v in values]
    return merged


def _extractor_args_from_env() -> Dict[str, Dict[str, list[str]]]:
    raw = (os.getenv("YTDLP_EXTRACTOR_ARGS_JSON") or "").strip()
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return _merge_extractor_args({}, data)


def _remote_components_from_env() -> Optional[list[str]]:
    raw = (os.getenv("YTDLP_REMOTE_COMPONENTS") or "").strip()
    if not raw or raw.lower() in {"0", "false", "no", "off"}:
        return None
    if raw.lower() in {"1", "true", "yes", "on"}:
        return ["ejs:github"]
    components = [part.strip() for part in raw.split(",") if part.strip()]
    return components or None


def build_ytdlp_options(*, include_cookies: bool = True, base: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    opts: Dict[str, Any] = dict(base or {})

    if include_cookies and COOKIES_FILE.exists():
        opts["cookiefile"] = str(COOKIES_FILE)

    if _env_bool("YTDLP_FORCE_IPV4", False):
        opts["force_ipv4"] = True

    if proxy := (os.getenv("YTDLP_PROXY") or "").strip():
        opts["proxy"] = proxy

    if source_address := (os.getenv("YTDLP_SOURCE_ADDRESS") or "").strip():
        opts["source_address"] = source_address

    if user_agent := (os.getenv("YTDLP_USER_AGENT") or "").strip():
        opts["user_agent"] = user_agent

    opts.setdefault("socket_timeout", env_float("YTDLP_SOCKET_TIMEOUT", 30.0, 1.0, 300.0))
    opts.setdefault("retries", env_int("YTDLP_RETRIES", 10, 0, 50))
    opts.setdefault("fragment_retries", env_int("YTDLP_FRAGMENT_RETRIES", 10, 0, 50))
    opts.setdefault("extractor_retries", env_int("YTDLP_EXTRACTOR_RETRIES", 3, 0, 20))

    request_sleep = env_float("YTDLP_REQUEST_DELAY", 0.0, 0.0, 30.0)
    if request_sleep:
        opts.setdefault("sleep_interval_requests", request_sleep)

    runtime = detect_js_runtime()
    if runtime.runtime:
        config: Dict[str, str] = {}
        if runtime.path:
            config["path"] = runtime.path
        opts["js_runtimes"] = {runtime.runtime: config}

    extractor_args = _merge_extractor_args(opts.get("extractor_args") or {}, _extractor_args_from_env())
    if extractor_args:
        opts["extractor_args"] = extractor_args

    remote_components = _remote_components_from_env()
    if remote_components:
        opts["remote_components"] = remote_components

    return opts


def _cookie_rows(cookie_file: Path) -> tuple[list[dict[str, str]], int]:
    rows: list[dict[str, str]] = []
    malformed = 0
    for line in cookie_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#HttpOnly_"):
            line = stripped.removeprefix("#HttpOnly_")
        elif stripped.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            malformed += 1
            continue
        domain, _, path, secure, expires, name, value = parts[:7]
        rows.append({
            "domain": domain,
            "path": path,
            "secure": secure,
            "expires": expires,
            "name": name,
            "has_value": "1" if bool(value) else "0",
        })
    return rows, malformed


def cookie_health(cookie_file: Optional[Path] = None) -> Dict[str, Any]:
    cookie_file = cookie_file or COOKIES_FILE
    if not cookie_file.exists():
        return {"status": "missing", "detail": f"Cookie file not found at {cookie_file}"}

    try:
        rows, malformed = _cookie_rows(cookie_file)
    except OSError as exc:
        return {"status": "error", "detail": f"Cookie file could not be read: {exc}"}

    if not rows:
        return {"status": "malformed", "detail": "Cookie file contains no Netscape cookie rows.", "rows": 0}

    now = int(time.time())
    youtube_rows = [row for row in rows if "youtube.com" in row["domain"].lower()]
    def row_expired(row: dict[str, str]) -> bool:
        try:
            expires = int(row["expires"])
        except ValueError:
            return False
        return bool(expires and expires < now)

    expired = sum(1 for row in rows if row_expired(row))
    youtube_expired = sum(1 for row in youtube_rows if row_expired(row))

    if not youtube_rows:
        return {
            "status": "no_youtube_cookies",
            "detail": "Cookie file has no youtube.com cookies.",
            "rows": len(rows),
            "malformedRows": malformed,
            "expiredRows": expired,
        }

    if youtube_expired == len(youtube_rows):
        return {
            "status": "expired",
            "detail": "All YouTube cookie rows are expired.",
            "rows": len(rows),
            "youtubeRows": len(youtube_rows),
            "malformedRows": malformed,
            "expiredRows": expired,
            "path": str(cookie_file),
        }

    names = {row["name"] for row in youtube_rows if row["has_value"] == "1" and not row_expired(row)}
    sid_present = bool({"SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID"} & names)
    login_present = "LOGIN_INFO" in names

    if login_present and sid_present:
        status = "auth_present"
        detail = "YouTube auth-looking cookies are present. This does not guarantee YouTube will accept them from this server."
    elif names & YOUTUBE_AUTH_COOKIE_NAMES:
        status = "partial_auth"
        detail = "Some YouTube auth cookies are present, but LOGIN_INFO plus a SAPISID cookie were not both found."
    else:
        status = "unauthenticated"
        detail = "YouTube cookies are present, but no account-auth cookies were found."

    return {
        "status": status,
        "detail": detail,
        "rows": len(rows),
        "youtubeRows": len(youtube_rows),
        "malformedRows": malformed,
        "expiredRows": expired,
        "path": str(cookie_file),
    }


def classify_ytdlp_error(message: str) -> Dict[str, str]:
    text = (message or "").lower()
    if "cookies are no longer valid" in text or "rotated in the browser" in text:
        return {"category": "invalid_cookies", "detail": "YouTube rejected the provided account cookies."}
    if "no supported javascript runtime" in text or "without a js runtime has been deprecated" in text:
        return {"category": "missing_js_runtime", "detail": "Install/configure Deno or Node.js for yt-dlp EJS support."}
    if "sign in to confirm" in text and "bot" in text:
        return {"category": "bot_challenge", "detail": "YouTube is challenging the server/IP or cookie session."}
    if "po token" in text or ("pot" in text and "token" in text):
        return {"category": "po_token", "detail": "YouTube requested a PO Token for this client/format."}
    if "http error 403" in text or "forbidden" in text:
        return {"category": "forbidden", "detail": "YouTube returned 403; this can be IP, cookie, client, or PO-token related."}
    if "http error 429" in text or "too many requests" in text or "rate-limit" in text:
        return {"category": "rate_limited", "detail": "YouTube rate-limited this server/IP/session."}
    if "ip is likely being blocked" in text or "all player responses are invalid" in text:
        return {"category": "ip_blocked", "detail": "yt-dlp reports the server IP is likely blocked by YouTube."}
    if "failed to extract any player response" in text or "no title found in player responses" in text:
        return {"category": "player_response", "detail": "YouTube player response extraction failed."}
    return {"category": "generic", "detail": "yt-dlp failed with an unclassified extractor/download error."}


def sanitize_error(message: str, max_length: int = 600) -> str:
    text = message or ""
    text = re.sub(
        r"(?i)\b(po_token|pot)=[^\s&]+",
        lambda match: f"{match.group(1)}=<redacted>",
        text,
    )
    text = re.sub(
        r"(?im)\b(authorization|cookie)\s*:\s*[^\r\n]*",
        lambda match: f"{match.group(1)}: <redacted>",
        text,
    )
    text = text.strip()
    return text if len(text) <= max_length else text[:max_length] + " …"
