# ytnd/downloader.py
"""
Downloader with persistent queue managed via database.
"""
from __future__ import annotations
import json, uuid, concurrent.futures, time, subprocess, shutil, os, re
from pathlib import Path
from typing import List, Dict, Optional, Tuple, TYPE_CHECKING
from mutagen.flac import FLAC
from mutagen.mp3 import EasyMP3
from mutagen.mp4 import MP4
from mutagen.oggopus import OggOpus
import yt_dlp

from .config import FFMPEG_EXECUTABLE, OUTPUT_ROOT, COOKIES_FILE, COVERS_ROOT
from .utils import sanitize_filename, sanitize_user_id, logger, get_context_logger, is_youtube_playlist_url, strip_playlist_context
from . import database

if TYPE_CHECKING:
    from typing import Any

AUDIO_EXTENSIONS = {".opus", ".mp3", ".m4a", ".flac", ".ogg"}
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
COOKIE_HEADERS = ("# HTTP Cookie File", "# Netscape HTTP Cookie File")
JS_RUNTIME_ORDER = ("deno", "node", "quickjs")
JS_RUNTIME_BINARIES = {
    "deno": ("deno",),
    "node": ("node",),
    "quickjs": ("qjs", "quickjs"),
}

def _shorten(s: str, maxlen: int = 600) -> str:
    s = clean_ytdlp_message(s)
    return s if len(s) <= maxlen else s[:maxlen] + " …"

def _needs_android_client(stderr_out: str) -> bool:
    t = (stderr_out or "").lower()
    return ("http error 403" in t or
            "forbidden" in t or
            "429" in t or
            "too many requests" in t or
            "sign in to confirm your age" in t or
            "playback on other websites has been disabled by the video owner" in t)

def clean_ytdlp_message(message: str) -> str:
    message = ANSI_ESCAPE_RE.sub("", message or "")
    return " ".join(message.replace("\r", "\n").split())

def _runtime_name_from_value(value: str | None) -> Optional[str]:
    if not value:
        return None
    lowered = value.strip().lower()
    if lowered in ("auto", ""):
        return None
    if lowered in ("qjs", "quickjs"):
        return "quickjs"
    if lowered in ("deno", "node"):
        return lowered
    return None

def _runtime_name_from_path(path: str) -> str:
    name = Path(path).name.lower()
    if name.endswith(".exe"):
        name = name[:-4]
    if name in ("qjs", "quickjs"):
        return "quickjs"
    if name in ("node", "deno"):
        return name
    return "deno"

def _find_runtime_executable(runtime: str) -> Optional[str]:
    for binary in JS_RUNTIME_BINARIES.get(runtime, (runtime,)):
        found = shutil.which(binary)
        if found:
            return found
    return None

def get_js_runtime_status() -> Dict[str, str]:
    explicit_path = os.getenv("YTND_JS_RUNTIME_PATH", "").strip()
    raw_runtime = os.getenv("YTND_JS_RUNTIME", "auto").strip().lower()
    explicit_runtime = _runtime_name_from_value(raw_runtime)

    if raw_runtime not in ("", "auto") and explicit_runtime is None:
        return {"status": "error", "detail": f"Unsupported JavaScript runtime: {raw_runtime}"}

    if explicit_path:
        runtime = explicit_runtime or _runtime_name_from_path(explicit_path)
        if runtime not in JS_RUNTIME_ORDER:
            return {"status": "error", "detail": f"Unsupported JavaScript runtime: {runtime}"}
        if not Path(explicit_path).is_file():
            return {
                "status": "error",
                "runtime": runtime,
                "path": explicit_path,
                "detail": "Configured JavaScript runtime path does not exist",
            }
        return {"status": "ok", "runtime": runtime, "path": explicit_path}

    if explicit_runtime:
        found = _find_runtime_executable(explicit_runtime)
        if found:
            return {"status": "ok", "runtime": explicit_runtime, "path": found}
        return {
            "status": "error",
            "runtime": explicit_runtime,
            "detail": f"Configured JavaScript runtime '{explicit_runtime}' was not found in PATH",
        }

    for runtime in JS_RUNTIME_ORDER:
        found = _find_runtime_executable(runtime)
        if found:
            return {"status": "ok", "runtime": runtime, "path": found}

    return {
        "status": "error",
        "runtime": "deno",
        "detail": "No supported JavaScript runtime found. Install Deno or set YTND_JS_RUNTIME_PATH.",
    }

def _yt_dlp_js_runtime_options() -> Dict[str, Dict[str, str]]:
    status = get_js_runtime_status()
    runtime = status.get("runtime") or "deno"
    if runtime not in JS_RUNTIME_ORDER:
        runtime = "deno"
    path = status.get("path")
    return {runtime: {"path": path} if path else {}}

def get_cookies_status(cookie_file: Optional[Path] = None) -> Dict[str, str]:
    cookie_file = cookie_file or COOKIES_FILE
    if not cookie_file.exists():
        return {"status": "missing", "detail": f"No cookies file at {cookie_file}"}

    try:
        size = cookie_file.stat().st_size
    except OSError as exc:
        return {"status": "invalid", "detail": f"Cannot read cookies file: {exc}"}

    if size == 0:
        return {"status": "empty", "detail": "Cookies file is empty"}

    try:
        lines = cookie_file.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError as exc:
        return {"status": "invalid", "detail": f"Cannot read cookies file: {exc}"}

    first_line = lines[0].lstrip("\ufeff").strip() if lines else ""
    if first_line not in COOKIE_HEADERS:
        return {
            "status": "invalid",
            "detail": "Cookies file must be in Netscape format and start with '# Netscape HTTP Cookie File' or '# HTTP Cookie File'",
        }

    cookie_rows = [
        line for line in lines
        if line.strip() and not line.lstrip().startswith("#") and len(line.split("\t")) >= 7
    ]
    if not cookie_rows:
        return {"status": "invalid", "detail": "Cookies file contains no valid cookie rows"}

    youtube_rows = sum(1 for line in cookie_rows if "youtube.com" in line.split("\t", 1)[0].lower())
    modified = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(cookie_file.stat().st_mtime))
    return {
        "status": "present",
        "detail": f"{len(cookie_rows)} cookie row(s), {youtube_rows} YouTube row(s), {size} bytes, modified {modified}",
    }

def _should_use_cookies(cookie_file: Optional[Path] = None) -> bool:
    cookie_file = cookie_file or COOKIES_FILE
    return get_cookies_status(cookie_file).get("status") == "present"

class YtDlpCaptureLogger:
    def __init__(self) -> None:
        self.debug_messages: List[str] = []
        self.warning_messages: List[str] = []
        self.error_messages: List[str] = []

    def debug(self, message: str) -> None:
        self.debug_messages.append(clean_ytdlp_message(message))

    def warning(self, message: str) -> None:
        self.warning_messages.append(clean_ytdlp_message(message))

    def error(self, message: str) -> None:
        self.error_messages.append(clean_ytdlp_message(message))

    def text(self) -> str:
        messages = self.warning_messages + self.error_messages
        return clean_ytdlp_message(" ".join(m for m in messages if m))

def apply_yt_dlp_defaults(
    opts: Dict,
    *,
    use_cookies: bool = True,
    capture_logger: Optional[YtDlpCaptureLogger] = None,
) -> Dict:
    ydl_opts = dict(opts)
    ydl_opts["js_runtimes"] = _yt_dlp_js_runtime_options()
    ydl_opts["no_color"] = True
    if capture_logger is not None:
        ydl_opts["logger"] = capture_logger
    if use_cookies and _should_use_cookies():
        ydl_opts["cookiefile"] = str(COOKIES_FILE)
    else:
        ydl_opts.pop("cookiefile", None)
    return ydl_opts

def _is_invalid_cookie_error(text: str) -> bool:
    t = clean_ytdlp_message(text).lower()
    return (
        "cookies are no longer valid" in t
        or "rotated in the browser" in t
        or "invalid cookie" in t
        or "cookie file must be" in t
        or "http error 400: bad request" in t
    )

def _is_missing_js_runtime_error(text: str) -> bool:
    t = clean_ytdlp_message(text).lower()
    return "no supported javascript runtime" in t or "javascript runtime could be found" in t

def _is_bot_signin_error(text: str) -> bool:
    t = clean_ytdlp_message(text).lower()
    return "not a bot" in t or "sign in to confirm" in t

def classify_yt_dlp_error(text: str, *, retried_without_cookies: bool = False) -> str:
    cleaned = clean_ytdlp_message(text)
    if _is_missing_js_runtime_error(cleaned):
        return (
            "yt-dlp needs a supported JavaScript runtime for YouTube. "
            "Install Deno or set YTND_JS_RUNTIME_PATH."
        )
    if _is_invalid_cookie_error(cleaned):
        retry_note = " Retried without cookies, but YouTube still rejected the request." if retried_without_cookies else ""
        return (
            "YouTube cookies are invalid or rotated. Re-export them from a private/incognito "
            "YouTube session and close that session after exporting."
            f"{retry_note}"
        )
    if _is_bot_signin_error(cleaned):
        return (
            "YouTube rejected this server with a sign-in/bot check. "
            "Use fresh YouTube cookies exported in Netscape format and make sure Deno is installed."
        )
    return cleaned or "yt-dlp failed without a detailed error"

class DownloadError(Exception):
    def __init__(self, entry: "_Entry", message: str, stdout: str = "", stderr: str = "", attempt: int = 1):
        self.entry = entry
        self.msg = message
        self.stdout = stdout
        self.stderr = stderr
        self.attempt = attempt
        super().__init__(message)

class Downloader:
    def __init__(self, user_id: str, connection_manager: Optional[Any] = None):
        try:
            self.user_id = sanitize_user_id(str(user_id))
        except ValueError as e:
            logger.error("Invalid user_id: %s", e)
            raise ValueError(f"Invalid user ID: {e}")
        
        self.log = get_context_logger(uid=self.user_id)
        self.out_dir   = OUTPUT_ROOT / self.user_id
        self.connection_manager = connection_manager
        
        if OUTPUT_ROOT.resolve() not in self.out_dir.resolve().parents:
            raise ValueError("Invalid output directory path")
        
        try:
            self.out_dir.mkdir(exist_ok=True, parents=True)
        except (PermissionError, OSError) as e:
            self.log.error("Failed to create output directory: %s", e)
            raise RuntimeError(f"Cannot create output directory: {e}")

        self.cover_dir = COVERS_ROOT / self.user_id
        
        if COVERS_ROOT.resolve() not in self.cover_dir.resolve().parents:
            raise ValueError("Invalid cover directory path")
        
        try:
            self.cover_dir.mkdir(exist_ok=True, parents=True)
        except (PermissionError, OSError) as e:
            self.log.error("Failed to create cover directory: %s", e)
            raise RuntimeError(f"Cannot create cover directory: {e}")

        self.song_list_path = self.out_dir / "song-list.json"
        self._song_cache = self._load_song_cache()
    
    def _check_disk_space(self, required_mb: int = 100) -> bool:
        """Check if there's enough disk space available."""
        try:
            stat = shutil.disk_usage(self.out_dir)
            available_mb = stat.free / (1024 * 1024)
            if available_mb < required_mb:
                self.log.warning("Low disk space: %.2f MB available (need %d MB)", available_mb, required_mb)
                return False
            return True
        except Exception as e:
            self.log.warning("Could not check disk space: %s", e)
            return True

    def _send_progress(self, url: str, status: str, **kwargs) -> None:
        """Send progress update via WebSocket if connection manager is available."""
        if self.connection_manager:
            message = {
                "type": "download_progress",
                "userId": self.user_id,
                "url": url,
                "status": status,
                **kwargs
            }
            try:
                self.connection_manager.broadcast_to_user_threadsafe(self.user_id, message)
            except Exception as e:
                self.log.warning("Failed to send progress update: %s", e)

    def _load_queue(self) -> List[str]:
        try:
            return database.get_queue(self.user_id)
        except Exception as e:
            self.log.error("Failed to load queue from database: %s", e)
            return []

    def _save_queue(self, urls: List[str]) -> None:
        try:
            database.set_queue(self.user_id, urls)
        except Exception as e:
            self.log.error("Failed to save queue to database: %s", e)
            raise RuntimeError(f"Cannot save queue: {e}")

    def add_urls(self, urls: List[str]) -> None:
        """Adds new links to the queue in the database"""
        queue = self._load_queue()
        queued_urls = set(queue)
        seen_urls = set()
        new_urls = []
        for u in urls:
            u = u.strip()
            if u and len(u) <= 2000 and u not in queued_urls and u not in seen_urls:
                new_urls.append(u)
                seen_urls.add(u)
        
        if new_urls:
            try:
                database.add_to_queue(self.user_id, new_urls)
                self.log.bind(step="queue").info("%d URL(s) added to queue", len(new_urls))
            except Exception as e:
                self.log.error("Failed to add URLs to queue: %s", e)
                raise RuntimeError(f"Cannot add URLs to queue: {e}")
        
        final_queue = self._load_queue()
        self.log.bind(step="queue").info("%d URL(s) in Queue", len(final_queue))

    def run(self, workers: int = 4) -> dict:
        urls = self._load_queue()
        if not urls:
            self.log.bind(step="queue").info("No URLs in queue.")
            return {"downloaded": 0, "duplicates": 0, "errors": 0, "failed": []}
        
        for url in urls:
            self._send_progress(url, "pending")
        
        if not self._check_disk_space():
            self.log.bind(step="queue").warning("Insufficient disk space, aborting download")
            return {
                "downloaded": 0, 
                "duplicates": 0, 
                "errors": 1, 
                "failed": [{"title": "—", "artist": "—", "url": "—", "reason": "Insufficient disk space", "attempts": 0}]
            }
        self.log.bind(step="queue").info("Starting download of %d URL(s)…", len(urls))

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            meta_results = list(pool.map(self._fetch_metadata, urls))

        entries: List[_Entry] = []
        failed_meta: List[dict] = []

        for (data, err), src_url in zip(meta_results, urls):
            if err or not data:
                self._send_progress(src_url, "error", error=err or "No metadata")
                failed_meta.append({
                    "title": "—",
                    "artist": "—",
                    "url": src_url,
                    "reason": err or "No metadata",
                    "attempts": 0,
                })
                continue

            sub = data.get("entries")
            if sub:
                entries.extend(_Entry(e) for e in sub if e)
            else:
                entries.append(_Entry(data))

        raw_count = len(entries)

        entries = [e for e in entries if not self._is_duplicate(e)]
        dup_count = raw_count - len(entries)

        errors = 0
        successes = 0
        failed_list: List[dict] = []

        if not entries:
            errors = len(failed_meta)
            self._save_queue([])
            if errors:
                self.log.bind(step="metadata").warning("%d errors already in metadata phase.", errors)
            else:
                self.log.bind(step="metadata").info("Only duplicates or empty results – nothing to do.")
            return {
                "downloaded": 0,
                "duplicates": dup_count,
                "errors": errors,
                "failed": failed_meta,
            }

        def _wrap_process(e: _Entry):
            self._process_entry(e)
            return e

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(_wrap_process, e) for e in entries]
            total = len(futures)
            for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
                try:
                    fut.result()
                    successes += 1
                except DownloadError as dex:
                    errors += 1
                    failed_list.append({
                        "title": dex.entry.title,
                        "artist": dex.entry.uploader,
                        "url": dex.entry.url,
                        "reason": dex.msg or "unknown error",
                        "attempts": dex.attempt,
                    })
                    self.log.bind(step="download", vid=dex.entry.id).error("Error in entry %d/%d: %s", i, total, dex.msg)
                    if dex.stderr: self.log.bind(step="download", vid=dex.entry.id).error("stderr: %s", _shorten(dex.stderr))
                    if dex.stdout: self.log.bind(step="download", vid=dex.entry.id).info("stdout: %s", _shorten(dex.stdout))
                except Exception as ex:
                    errors += 1
                    failed_list.append({
                        "title": "—",
                        "artist": "—",
                        "url": "—",
                        "reason": str(ex),
                        "attempts": 1,
                    })
                    self.log.bind(step="download").error("Error in entry %d/%d: %s", i, total, ex)
                finally:
                    self.log.bind(step="download").info("Progress: %d/%d", i, total)

        if errors:
            self.log.bind(step="download").warning("%d errors occurred.", errors)

        try:
            self._save_song_cache()
        except Exception as e:
            self.log.error("Failed to save song cache: %s", e)
        
        self._save_queue([])

        all_failed = failed_meta + failed_list
        return {
            "downloaded": successes,
            "duplicates": dup_count,
            "errors": len(all_failed),
            "failed": all_failed,
        }

    def _fetch_metadata(self, url: str) -> Tuple[Optional[Dict], Optional[str]]:
        is_pl = is_youtube_playlist_url(url)
        eff_url = url if is_pl else strip_playlist_context(url)

        base_opts = {
            'ignoreerrors': False,
            'no_warnings': False,
            'force_ipv4': True,
            'extract_flat': 'in_playlist' if is_pl else False,
            'playlistend': 150 if is_pl else -1,
            'quiet': True,
        }

        def extract(use_cookies: bool):
            capture = YtDlpCaptureLogger()
            opts = apply_yt_dlp_defaults(base_opts, use_cookies=use_cookies, capture_logger=capture)
            try:
                with yt_dlp.YoutubeDL(opts) as ydl:
                    data = ydl.extract_info(eff_url, download=False)
                    if not data:
                        return None, "No metadata received", capture.text()
                    return data, None, capture.text()
            except yt_dlp.utils.DownloadError as e:
                return None, f"yt-dlp error: {e}", capture.text()
            except Exception as e:
                return None, f"Metadata fetch error: {e}", capture.text()

        use_cookies = _should_use_cookies()
        data, err, captured = extract(use_cookies)
        combined_error = clean_ytdlp_message(f"{captured} {err or ''}")

        if err and use_cookies and _is_invalid_cookie_error(combined_error):
            self.log.bind(step="metadata", url=eff_url).warning(
                "Cookie file appears invalid; retrying metadata without cookies"
            )
            data, retry_err, retry_captured = extract(False)
            if not retry_err and data:
                return data, None
            combined_error = clean_ytdlp_message(f"{combined_error} {retry_captured} {retry_err or ''}")
            err = classify_yt_dlp_error(combined_error, retried_without_cookies=True)
        elif err:
            err = classify_yt_dlp_error(combined_error)

        if err:
            reason = f"yt-dlp error: {err}" if not err.startswith("Metadata fetch error:") else err
            self.log.bind(step="metadata", url=eff_url).warning(reason)
            return None, reason

        return data, None

    def _process_entry(self, entry: "_Entry") -> None:
        """
        Downloads audio and sets tags. Raises DownloadError on failure.
        Has a 2-stage retry:
          - Attempt 1: Standard
          - Attempt 2 (only on 403/429/age-gate): android player client
        """
        self._send_progress(entry.url, "downloading", title=entry.title, artist=entry.uploader, id=entry.id)
        
        uid = uuid.uuid4().hex[:8]
        title_artist = f"{entry.title} # {entry.uploader}"
        sanitized    = sanitize_filename(title_artist)
        temp_tpl     = self.out_dir / f"{uid}_{sanitized}.%(ext)s"

        def progress_hook(d):
            if d['status'] == 'downloading':
                downloaded = d.get('downloaded_bytes', 0)
                total = d.get('total_bytes') or d.get('total_bytes_estimate', 0)
                if total > 0:
                    percentage = (downloaded / total) * 100
                    self._send_progress(
                        entry.url, 
                        "downloading",
                        title=entry.title,
                        artist=entry.uploader,
                        id=entry.id,
                        percentage=round(percentage, 1),
                        downloaded_bytes=downloaded,
                        total_bytes=total
                    )
            elif d['status'] == 'finished':
                self._send_progress(entry.url, "processing", title=entry.title, artist=entry.uploader, id=entry.id)

        base_opts = {
            'format': 'bestaudio/best',
            'outtmpl': str(temp_tpl),
            'quiet': True,
            'no_warnings': True,
            'force_ipv4': True,
            'ffmpeg_location': FFMPEG_EXECUTABLE,
            'progress_hooks': [progress_hook],
            'postprocessors': [
                {
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'opus',
                    'preferredquality': '0',
                },
                {
                    'key': 'FFmpegMetadata',
                    'add_metadata': True
                },
                {
                    'key': 'EmbedThumbnail'
                }
            ],
            'writethumbnail': True,
            'noprogress': False,
        }

        def do_download(opts, *, use_cookies: bool):
            capture = YtDlpCaptureLogger()
            ydl_opts = apply_yt_dlp_defaults(opts, use_cookies=use_cookies, capture_logger=capture)
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    res_code = ydl.download([entry.url])
                    return res_code, capture.text()
            except yt_dlp.utils.DownloadError as de:
                return 1, clean_ytdlp_message(f"{capture.text()} {de}")
            except Exception as e:
                return 1, clean_ytdlp_message(f"{capture.text()} {e}")

        use_cookies = _should_use_cookies()
        retried_without_cookies = False
        res_code, err_msg = do_download(base_opts, use_cookies=use_cookies)

        if res_code != 0 and use_cookies and _is_invalid_cookie_error(err_msg):
            retried_without_cookies = True
            self.log.bind(step="download", vid=entry.id).warning(
                "Cookie file appears invalid; retrying download without cookies"
            )
            res_code, retry_err = do_download(base_opts, use_cookies=False)
            if res_code != 0:
                err_msg = clean_ytdlp_message(f"{err_msg} {retry_err}")
            else:
                err_msg = retry_err

        if res_code != 0:
            if _needs_android_client(err_msg):
                time.sleep(0.8)
                retry_opts = base_opts.copy()
                retry_opts['extractor_args'] = {'youtube': {'player_client': ['android']}}
                retry_use_cookies = use_cookies and not _is_invalid_cookie_error(err_msg)
                res_code, err_msg = do_download(retry_opts, use_cookies=retry_use_cookies)
                if res_code != 0:
                    friendly = classify_yt_dlp_error(err_msg, retried_without_cookies=retried_without_cookies)
                    self._send_progress(entry.url, "error", title=entry.title, artist=entry.uploader, id=entry.id, error=_shorten(friendly))
                    raise DownloadError(entry, message=f"yt-dlp exit: {_shorten(friendly)}", attempt=2, stderr=err_msg)
            else:
                friendly = classify_yt_dlp_error(err_msg, retried_without_cookies=retried_without_cookies)
                self._send_progress(entry.url, "error", title=entry.title, artist=entry.uploader, id=entry.id, error=_shorten(friendly))
                raise DownloadError(entry, message=f"yt-dlp exit: {_shorten(friendly)}", attempt=1, stderr=err_msg)

        for dl_file in self.out_dir.glob(f"{uid}_*"):
            if not dl_file.is_file() or dl_file.suffix.lower() not in AUDIO_EXTENSIONS:
                continue
            final_name = dl_file.name.split("_", 1)[1]
            final_path = self.out_dir / final_name
            dl_file.rename(final_path)
            try:
                self._set_tags(final_path, entry)
            except Exception as tag_ex:
                self.log.bind(step="metadata", url=final_path).warning("Tagging error: %s", tag_ex)

        try:
            cover_filename = self._save_cover(entry)
        except Exception as cex:
            self.log.bind(step="metadata", url=entry.id or entry.url).warning("Could not save cover: %s", cex)
            cover_filename = None

        cache_key = entry.id or f"{entry.title}|{entry.uploader}"
        self._song_cache[cache_key] = {
            "id": entry.id,
            "title": entry.title,
            "artist": entry.uploader,
            "url": entry.url,
            "date": entry.upload_date,
            "cover": cover_filename,
        }
        
        self._send_progress(entry.url, "completed", title=entry.title, artist=entry.uploader, id=entry.id)

    def _save_cover(self, entry: "_Entry") -> Optional[str]:
        """
        Downloads the video thumbnail, converts it to JPG if needed, and
        saves it under covers/<user>/<id>.jpg.
        Returns the filename or None.
        """
        if not entry.id:
            return None

        if "/" in entry.id or "\\" in entry.id or ".." in entry.id:
            self.log.bind(step="cover").warning("Invalid video ID: %s", entry.id)
            return None

        final_cover_path = self.cover_dir / f"{entry.id}.jpg"
        if final_cover_path.exists():
            return final_cover_path.name
        
        for ext in ("jpeg", "png", "webp"):
            if (self.cover_dir / f"{entry.id}.{ext}").exists():
                 return (self.cover_dir / f"{entry.id}.{ext}").name

        out_tpl = self.cover_dir / f"{entry.id}.%(ext)s"
        base_opts = {
            'skip_download': True,
            'writethumbnail': True,
            'outtmpl': str(out_tpl),
            'quiet': True,
            'no_warnings': True,
            'force_ipv4': True,
            'noprogress': True,
        }

        def download_cover(use_cookies: bool):
            capture = YtDlpCaptureLogger()
            opts = apply_yt_dlp_defaults(base_opts, use_cookies=use_cookies, capture_logger=capture)
            try:
                with yt_dlp.YoutubeDL(opts) as ydl:
                    ydl.download([entry.url])
                return None
            except Exception as e:
                return clean_ytdlp_message(f"{capture.text()} {e}")

        use_cookies = _should_use_cookies()
        cover_error = download_cover(use_cookies)
        if cover_error and use_cookies and _is_invalid_cookie_error(cover_error):
            self.log.bind(step="cover", vid=entry.id).warning(
                "Cookie file appears invalid; retrying cover download without cookies"
            )
            retry_error = download_cover(False)
            if retry_error:
                cover_error = clean_ytdlp_message(f"{cover_error} {retry_error}")
            else:
                cover_error = None

        if cover_error:
            raise RuntimeError(f"yt-dlp(cover) error: {classify_yt_dlp_error(cover_error)}")

        downloaded_cover = None
        for ext in ("webp", "png", "jpeg", "jpg"):
            cand = self.cover_dir / f"{entry.id}.{ext}"
            if cand.exists():
                downloaded_cover = cand
                break
        
        if not downloaded_cover:
             self.log.bind(step="cover", vid=entry.id).warning("No thumbnail file found after download.")
             return None

        if downloaded_cover.suffix.lower() == ".jpg":
            return downloaded_cover.name

        self.log.bind(step="cover", vid=entry.id).info("Converting cover from %s to .jpg", downloaded_cover.suffix)
        try:
            cmd = [
                str(FFMPEG_EXECUTABLE), "-y", "-i", str(downloaded_cover), 
                "-v", "quiet", "-q:v", "2", str(final_cover_path)
            ]
            subprocess.run(cmd, check=True, timeout=15)
            
            if final_cover_path.exists():
                 downloaded_cover.unlink(missing_ok=True)
                 return final_cover_path.name

        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as ff_err:
             self.log.bind(step="cover", vid=entry.id).error("FFmpeg conversion failed: %s", ff_err)
             return downloaded_cover.name
        
        return None

    def _set_tags(self, path: Path, entry: "_Entry") -> None:
        audio = None
        ext = path.suffix.lower()
        if ext == ".mp3": audio = EasyMP3(path)
        elif ext == ".m4a": audio = MP4(path)
        elif ext == ".opus": audio = OggOpus(path)
        elif ext == ".flac": audio = FLAC(path)
        if audio is None:
            self.log.bind(step="tag").warning("Unknown format: %s", path)
            return

        if isinstance(audio, MP4):
            audio["\xa9nam"] = [entry.title]
            audio["\xa9ART"] = [entry.uploader]
            if entry.album: audio["\xa9alb"] = [entry.album]
            if entry.upload_date: audio["\xa9day"] = [entry.upload_date]
            audio["desc"] = [entry.url]
            if entry.description:
                audio["ldes"] = [entry.description]
        else:
            audio["title"] = entry.title
            audio["artist"] = entry.uploader
            if entry.album: audio["album"] = entry.album
            if entry.upload_date: audio["date"] = entry.upload_date
            audio["description"] = entry.url
            if entry.description:
                try: audio["COMMENT"] = entry.description
                except Exception: audio["SYNOPSIS"] = entry.description
        audio.save()

    def _load_song_cache(self) -> Dict[str, dict]:
        if self.song_list_path.exists():
            try:
                with self.song_list_path.open(encoding="utf-8") as f:
                    items = json.load(f)
                    cache = {}
                    for s in items:
                        key = s.get("id") or f"{s.get('title')}|{s.get('artist')}"
                        cache[key] = s
                    return cache
            except (json.JSONDecodeError, OSError) as e:
                self.log.error("Failed to load song cache: %s", e)
        return {}

    def _save_song_cache(self) -> None:
        try:
            with self.song_list_path.open("w", encoding="utf-8") as f:
                json.dump(list(self._song_cache.values()), f, indent=4, ensure_ascii=False)
        except (OSError, PermissionError) as e:
            self.log.error("Failed to save song cache: %s", e)
            raise RuntimeError(f"Cannot save song cache: {e}")

    def _is_duplicate(self, entry: "_Entry") -> bool:
        if entry.id and entry.id in self._song_cache:
            return True
        key = f"{entry.title}|{entry.uploader}"
        if key in self._song_cache:
            return True
        sanitized = sanitize_filename(f"{entry.title} # {entry.uploader}")
        return any(self.out_dir.glob(f"*{sanitized}*"))

class _Entry:
    def __init__(self, data: dict):
        self.id = data.get("id") or data.get("display_id")
        self.title  = data.get("title", "Unknown Title")
        self.uploader = data.get("uploader", "Unknown Artist")
        self.url   = data.get("webpage_url") or data.get("url")
        self.album = "Nightcore" if "nightcore" in (self.title or "").lower() else None

        d = data.get("upload_date")
        self.upload_date = f"{d[:4]}-{d[4:6]}-{d[6:]}" if d and len(d) == 8 else None
        self.description = (data.get("description") or "").strip()
