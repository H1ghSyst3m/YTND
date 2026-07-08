# ytnd/downloader.py
"""
Downloader with persistent queue managed via database.
"""
from __future__ import annotations
import json, uuid, concurrent.futures, time, subprocess, shutil
from pathlib import Path
from typing import List, Dict, Optional, Tuple, TYPE_CHECKING
from mutagen.flac import FLAC
from mutagen.mp3 import EasyMP3
from mutagen.mp4 import MP4
from mutagen.oggopus import OggOpus
import yt_dlp

from .config import FFMPEG_EXECUTABLE, OUTPUT_ROOT, COVERS_ROOT
from .utils import sanitize_filename, sanitize_user_id, logger, get_context_logger, is_youtube_playlist_url, strip_playlist_context
from .ytdlp_support import (
    android_retry_enabled,
    build_ytdlp_options,
    classify_ytdlp_error,
    download_workers,
    item_delay,
    metadata_workers,
    sanitize_error,
)
from . import database

if TYPE_CHECKING:
    from typing import Any

AUDIO_EXTENSIONS = {".opus", ".mp3", ".m4a", ".flac", ".ogg"}
MAX_DOWNLOAD_WORKERS = 8

def _shorten(s: str, maxlen: int = 600) -> str:
    s = (s or "").strip()
    return s if len(s) <= maxlen else s[:maxlen] + " …"

def _clamp_worker_count(workers: int) -> int:
    return max(1, min(MAX_DOWNLOAD_WORKERS, workers))

def _needs_android_client(stderr_out: str) -> bool:
    t = (stderr_out or "").lower()
    return ("http error 403" in t or
            "forbidden" in t or
            "429" in t or
            "too many requests" in t or
            "sign in to confirm your age" in t or
            "playback on other websites has been disabled by the video owner" in t)

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

    def run(self, workers: Optional[int] = None) -> dict:
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

        meta_workers = metadata_workers()
        requested_workers = workers if workers is not None else download_workers()
        work_count = _clamp_worker_count(requested_workers)
        delay_seconds = item_delay()

        with concurrent.futures.ThreadPoolExecutor(max_workers=meta_workers) as pool:
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
                    "category": classify_ytdlp_error(err or "No metadata").get("category"),
                })
                continue

            sub = data.get("entries")
            if sub:
                entries.extend(_Entry(e, source_url=src_url) for e in sub if e)
            else:
                entries.append(_Entry(data, source_url=src_url))

        raw_count = len(entries)

        entries = [e for e in entries if not self._is_duplicate(e)]
        dup_count = raw_count - len(entries)

        errors = 0
        successes = 0
        failed_list: List[dict] = []

        if not entries:
            errors = len(failed_meta)
            self._save_queue([item["url"] for item in failed_meta])
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

        total = len(entries)

        def _handle_success(e: _Entry, i: int) -> None:
            nonlocal successes
            successes += 1
            self.log.bind(step="download").info("Progress: %d/%d", i, total)

        def _handle_download_error(dex: DownloadError, i: int) -> None:
            nonlocal errors
            errors += 1
            failed_list.append({
                "title": dex.entry.title,
                "artist": dex.entry.uploader,
                "url": dex.entry.source_url or dex.entry.url,
                "reason": dex.msg or "unknown error",
                "attempts": dex.attempt,
                "category": classify_ytdlp_error(dex.msg or dex.stderr).get("category"),
            })
            self.log.bind(step="download", vid=dex.entry.id).error("Error in entry %d/%d: %s", i, total, dex.msg)
            if dex.stderr:
                self.log.bind(step="download", vid=dex.entry.id).error("stderr: %s", _shorten(dex.stderr))
            if dex.stdout:
                self.log.bind(step="download", vid=dex.entry.id).info("stdout: %s", _shorten(dex.stdout))
            self.log.bind(step="download").info("Progress: %d/%d", i, total)

        def _handle_unknown_error(ex: Exception, e: Optional[_Entry], i: int) -> None:
            nonlocal errors
            errors += 1
            safe_reason = sanitize_error(str(ex))
            classification = classify_ytdlp_error(safe_reason)
            client_reason = safe_reason if classification.get("category") != "generic" else "Internal download error"
            failed_list.append({
                "title": e.title if e else "—",
                "artist": e.uploader if e else "—",
                "url": (e.source_url or e.url) if e else "—",
                "reason": client_reason,
                "attempts": 1,
                "category": classification.get("category"),
            })
            self.log.bind(step="download").error("Error in entry %d/%d: %s", i, total, ex)
            self.log.bind(step="download").info("Progress: %d/%d", i, total)

        if work_count <= 1:
            for i, entry in enumerate(entries, 1):
                try:
                    _wrap_process(entry)
                    _handle_success(entry, i)
                except DownloadError as dex:
                    _handle_download_error(dex, i)
                except Exception as ex:
                    _handle_unknown_error(ex, entry, i)
                finally:
                    if delay_seconds and i < total:
                        time.sleep(delay_seconds)
        else:
            with concurrent.futures.ThreadPoolExecutor(max_workers=work_count) as pool:
                future_entries = {}
                for submit_index, entry in enumerate(entries):
                    if delay_seconds and submit_index > 0:
                        time.sleep(delay_seconds)
                    future_entries[pool.submit(_wrap_process, entry)] = entry
                for i, fut in enumerate(concurrent.futures.as_completed(future_entries), 1):
                    entry = future_entries[fut]
                    try:
                        fut.result()
                        _handle_success(entry, i)
                    except DownloadError as dex:
                        _handle_download_error(dex, i)
                    except Exception as ex:
                        _handle_unknown_error(ex, entry, i)

        if errors:
            self.log.bind(step="download").warning("%d errors occurred.", errors)

        try:
            self._save_song_cache()
        except Exception as e:
            self.log.error("Failed to save song cache: %s", e)
        
        failed_urls = {item["url"] for item in failed_meta + failed_list if item.get("url") and item.get("url") != "—"}
        self._save_queue([url for url in urls if url in failed_urls])

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

        ydl_opts = build_ytdlp_options(base={
            'ignoreerrors': False,
            'no_warnings': False,
            'extract_flat': 'in_playlist' if is_pl else False,
            'playlistend': 150 if is_pl else -1,
            'quiet': True,
        })

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                data = ydl.extract_info(eff_url, download=False)
                if not data:
                    return None, "No metadata received"
                return data, None
        except yt_dlp.utils.DownloadError as e:
            reason = sanitize_error(f"yt-dlp error: {e}")
            self.log.bind(step="metadata", url=eff_url).warning(reason)
            return None, reason
        except Exception as e:
            self.log.bind(step="metadata", url=eff_url).error("Metadata fetch error: %s", e)
            safe_reason = sanitize_error(str(e))
            classification = classify_ytdlp_error(safe_reason)
            if classification.get("category") == "generic":
                return None, "Metadata fetch error"
            return None, f"Metadata fetch error: {safe_reason}"

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

        base_opts = build_ytdlp_options(base={
            'format': 'bestaudio/best',
            'outtmpl': str(temp_tpl),
            'quiet': True,
            'no_warnings': True,
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
        })

        def do_download(opts):
            try:
                with yt_dlp.YoutubeDL(opts) as ydl:
                    res_code = ydl.download([entry.url])
                    return res_code, None
            except yt_dlp.utils.DownloadError as de:
                return 1, sanitize_error(str(de))
            except Exception as e:
                return 1, sanitize_error(str(e))

        res_code, err_msg = do_download(base_opts)

        if res_code != 0:
            if android_retry_enabled() and _needs_android_client(err_msg):
                time.sleep(0.8)
                retry_opts = base_opts.copy()
                extractor_args = dict(retry_opts.get('extractor_args') or {})
                youtube_args = dict(extractor_args.get('youtube') or {})
                youtube_args['player_client'] = ['android']
                extractor_args['youtube'] = youtube_args
                retry_opts['extractor_args'] = extractor_args
                res_code, err_msg = do_download(retry_opts)
                if res_code != 0:
                    self._send_progress(entry.url, "error", title=entry.title, artist=entry.uploader, id=entry.id, error=_shorten(err_msg))
                    raise DownloadError(entry, message=f"yt-dlp exit: {_shorten(err_msg)}", attempt=2, stderr=err_msg)
            else:
                self._send_progress(entry.url, "error", title=entry.title, artist=entry.uploader, id=entry.id, error=_shorten(err_msg))
                raise DownloadError(entry, message=f"yt-dlp exit: {_shorten(err_msg)}", attempt=1, stderr=err_msg)

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
        ydl_opts = build_ytdlp_options(base={
            'skip_download': True,
            'writethumbnail': True,
            'outtmpl': str(out_tpl),
            'quiet': True,
            'no_warnings': True,
            'noprogress': True,
        })

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([entry.url])
        except Exception as e:
            raise RuntimeError(sanitize_error(f"yt-dlp(cover) error: {e}"))

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
    def __init__(self, data: dict, source_url: Optional[str] = None):
        self.id = data.get("id") or data.get("display_id")
        self.title  = data.get("title", "Unknown Title")
        self.uploader = data.get("uploader", "Unknown Artist")
        self.url   = data.get("webpage_url") or data.get("url")
        self.source_url = source_url or self.url
        self.album = "Nightcore" if "nightcore" in (self.title or "").lower() else None

        d = data.get("upload_date")
        self.upload_date = f"{d[:4]}-{d[4:6]}-{d[6:]}" if d and len(d) == 8 else None
        self.description = (data.get("description") or "").strip()
