import time

from ytnd import ytdlp_support


def _clear_ytdlp_env(monkeypatch):
    for name in (
        "YTDLP_FORCE_IPV4",
        "YTDLP_JS_RUNTIME",
        "YTDLP_JS_RUNTIME_PATH",
        "YTDLP_PROXY",
        "YTDLP_SOURCE_ADDRESS",
        "YTDLP_USER_AGENT",
        "YTDLP_EXTRACTOR_ARGS_JSON",
        "YTDLP_REMOTE_COMPONENTS",
        "YTDLP_SOCKET_TIMEOUT",
        "YTDLP_RETRIES",
        "YTDLP_FRAGMENT_RETRIES",
        "YTDLP_EXTRACTOR_RETRIES",
        "YTDLP_REQUEST_DELAY",
    ):
        monkeypatch.delenv(name, raising=False)


def test_build_ytdlp_options_uses_cookie_and_env_overrides(tmp_path, monkeypatch):
    _clear_ytdlp_env(monkeypatch)
    cookies = tmp_path / "cookies.txt"
    cookies.write_text("# Netscape HTTP Cookie File\n", encoding="utf-8")

    monkeypatch.setattr(ytdlp_support, "COOKIES_FILE", cookies)
    monkeypatch.setattr(
        ytdlp_support,
        "detect_js_runtime",
        lambda: ytdlp_support.RuntimeStatus("ok", runtime="deno", path="/bin/deno", version="deno 2.3.1"),
    )
    monkeypatch.setenv("YTDLP_FORCE_IPV4", "true")
    monkeypatch.setenv("YTDLP_PROXY", "http://127.0.0.1:8080")
    monkeypatch.setenv("YTDLP_SOURCE_ADDRESS", "192.0.2.10")
    monkeypatch.setenv("YTDLP_USER_AGENT", "YTND-Test")
    monkeypatch.setenv(
        "YTDLP_EXTRACTOR_ARGS_JSON",
        '{"youtube":{"player_client":["default"],"po_token":"web.gvs+TOKEN"}}',
    )
    monkeypatch.setenv("YTDLP_SOCKET_TIMEOUT", "42")
    monkeypatch.setenv("YTDLP_RETRIES", "7")
    monkeypatch.setenv("YTDLP_FRAGMENT_RETRIES", "8")
    monkeypatch.setenv("YTDLP_EXTRACTOR_RETRIES", "2")
    monkeypatch.setenv("YTDLP_REQUEST_DELAY", "1.25")
    monkeypatch.setenv("YTDLP_REMOTE_COMPONENTS", "ejs:github,ejs:npm")

    opts = ytdlp_support.build_ytdlp_options(base={"quiet": True})

    assert opts["cookiefile"] == str(cookies)
    assert opts["force_ipv4"] is True
    assert opts["proxy"] == "http://127.0.0.1:8080"
    assert opts["source_address"] == "192.0.2.10"
    assert opts["user_agent"] == "YTND-Test"
    assert opts["js_runtimes"] == {"deno": {"path": "/bin/deno"}}
    assert opts["extractor_args"]["youtube"]["player_client"] == ["default"]
    assert opts["extractor_args"]["youtube"]["po_token"] == ["web.gvs+TOKEN"]
    assert opts["socket_timeout"] == 42.0
    assert opts["retries"] == 7
    assert opts["fragment_retries"] == 8
    assert opts["extractor_retries"] == 2
    assert opts["sleep_interval_requests"] == 1.25
    assert opts["remote_components"] == ["ejs:github", "ejs:npm"]


def test_build_ytdlp_options_skips_missing_cookies_and_forced_ipv4_by_default(tmp_path, monkeypatch):
    _clear_ytdlp_env(monkeypatch)
    monkeypatch.setattr(ytdlp_support, "COOKIES_FILE", tmp_path / "missing.txt")
    monkeypatch.setattr(ytdlp_support, "detect_js_runtime", lambda: ytdlp_support.RuntimeStatus("missing"))

    opts = ytdlp_support.build_ytdlp_options()

    assert "cookiefile" not in opts
    assert "force_ipv4" not in opts
    assert "js_runtimes" not in opts


def test_build_ytdlp_options_remote_components_boolean_uses_ejs_github(monkeypatch):
    _clear_ytdlp_env(monkeypatch)
    monkeypatch.setattr(ytdlp_support, "detect_js_runtime", lambda: ytdlp_support.RuntimeStatus("missing"))
    monkeypatch.setenv("YTDLP_REMOTE_COMPONENTS", "true")

    opts = ytdlp_support.build_ytdlp_options(include_cookies=False)

    assert opts["remote_components"] == ["ejs:github"]


def test_detect_js_runtime_prefers_supported_deno(monkeypatch):
    _clear_ytdlp_env(monkeypatch)
    monkeypatch.setattr(ytdlp_support.shutil, "which", lambda name: f"/bin/{name}")
    monkeypatch.setattr(
        ytdlp_support,
        "_runtime_version",
        lambda path, runtime: {"deno": "deno 2.3.0", "node": "v24.0.0", "quickjs": "2025-04-26"}[runtime],
    )

    status = ytdlp_support.detect_js_runtime()

    assert status.status == "ok"
    assert status.runtime == "deno"
    assert status.path == "/bin/deno"


def test_detect_js_runtime_honors_node_minimum(monkeypatch):
    _clear_ytdlp_env(monkeypatch)
    monkeypatch.setenv("YTDLP_JS_RUNTIME", "node")
    monkeypatch.setenv("YTDLP_JS_RUNTIME_PATH", "/opt/node/bin/node")
    monkeypatch.setattr(ytdlp_support.shutil, "which", lambda name: None)
    monkeypatch.setattr(ytdlp_support, "_runtime_version", lambda path, runtime: "v21.9.0")

    status = ytdlp_support.detect_js_runtime()

    assert status.status == "missing"
    assert "node" in status.detail


def test_cookie_health_reports_auth_present(tmp_path):
    expires = int(time.time()) + 3600
    cookies = tmp_path / "cookies.txt"
    cookies.write_text(
        "\n".join(
            [
                "# Netscape HTTP Cookie File",
                f".youtube.com\tTRUE\t/\tTRUE\t{expires}\tLOGIN_INFO\tlogin",
                f".youtube.com\tTRUE\t/\tTRUE\t{expires}\t__Secure-3PAPISID\tsid",
            ]
        ),
        encoding="utf-8",
    )

    status = ytdlp_support.cookie_health(cookies)

    assert status["status"] == "auth_present"
    assert status["youtubeRows"] == 2
    assert status["expiredRows"] == 0


def test_cookie_health_counts_httponly_youtube_cookie_rows(tmp_path):
    expires = int(time.time()) + 3600
    cookies = tmp_path / "cookies.txt"
    cookies.write_text(
        "\n".join(
            [
                "# Netscape HTTP Cookie File",
                f"#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t{expires}\tLOGIN_INFO\tlogin",
                f"#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t{expires}\tSAPISID\tsid",
            ]
        ),
        encoding="utf-8",
    )

    status = ytdlp_support.cookie_health(cookies)

    assert status["status"] == "auth_present"
    assert status["youtubeRows"] == 2


def test_cookie_health_reports_malformed_and_no_youtube_cookies(tmp_path):
    cookies = tmp_path / "cookies.txt"
    cookies.write_text("not-a-netscape-row\n.example.com\tTRUE\t/\tTRUE\t0\tfoo\tbar\n", encoding="utf-8")

    status = ytdlp_support.cookie_health(cookies)

    assert status["status"] == "no_youtube_cookies"
    assert status["malformedRows"] == 1


def test_cookie_health_reports_partial_auth_for_rotated_like_cookie_set(tmp_path):
    expires = int(time.time()) + 3600
    cookies = tmp_path / "cookies.txt"
    cookies.write_text(
        f".youtube.com\tTRUE\t/\tTRUE\t{expires}\t__Secure-3PAPISID\tsid\n",
        encoding="utf-8",
    )

    assert ytdlp_support.cookie_health(cookies)["status"] == "partial_auth"


def test_cookie_health_reports_expired_youtube_cookies(tmp_path):
    expires = int(time.time()) - 3600
    cookies = tmp_path / "cookies.txt"
    cookies.write_text(
        "\n".join(
            [
                f".youtube.com\tTRUE\t/\tTRUE\t{expires}\tLOGIN_INFO\tlogin",
                f".youtube.com\tTRUE\t/\tTRUE\t{expires}\tSAPISID\tsid",
            ]
        ),
        encoding="utf-8",
    )

    status = ytdlp_support.cookie_health(cookies)

    assert status["status"] == "expired"
    assert status["expiredRows"] == 2


def test_classify_ytdlp_error_matches_common_youtube_failures():
    assert ytdlp_support.classify_ytdlp_error(
        "The provided YouTube account cookies are no longer valid. They have likely been rotated"
    )["category"] == "invalid_cookies"
    assert ytdlp_support.classify_ytdlp_error(
        "No supported JavaScript runtime could be found"
    )["category"] == "missing_js_runtime"
    assert ytdlp_support.classify_ytdlp_error(
        "Sign in to confirm you’re not a bot"
    )["category"] == "bot_challenge"
    assert ytdlp_support.classify_ytdlp_error("HTTP Error 403: Forbidden")["category"] == "forbidden"
    assert ytdlp_support.classify_ytdlp_error("HTTP Error 429: Too Many Requests")["category"] == "rate_limited"


def test_sanitize_error_redacts_sensitive_headers_and_tokens():
    message = (
        "Authorization: Bearer secret-token\n"
        "Cookie: SID=secret; SAPISID=secret\n"
        "po_token=web.gvs+secret&next=1 pot=secret-value"
    )

    sanitized = ytdlp_support.sanitize_error(message)

    assert "Authorization: <redacted>" in sanitized
    assert "Cookie: <redacted>" in sanitized
    assert "po_token=<redacted>" in sanitized
    assert "pot=<redacted>" in sanitized
    assert "secret" not in sanitized
