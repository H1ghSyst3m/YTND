# YTND Manager - YouTube Audio Manager & Setup Wizard

[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python&logoColor=white)](https://www.python.org/)
[![React](https://img.shields.io/badge/React-19-blue?logo=react&logoColor=61DAFB)](https://react.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-green?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
YTND Manager is a web-based management interface for downloading and organising YouTube audio. A built-in first-run setup wizard creates the initial admin account, and the FastAPI backend powers a sleek React frontend with real-time updates.

## ✨ Features

- **Modern Web UI**: A feature-rich web interface for managing songs, users, and system status with real-time updates.
- **Download Queue**: Add multiple URLs, process them in a batch, and see live progress updates.
- **Song Management**: View your entire library, search, re-download, delete, and download songs directly from the web UI.
- **Automatic Tagging**: Downloads are automatically tagged with metadata like title, artist, album, and cover art.
- **User Management**: Admin interface for managing users and their roles.
- **Real-time Updates**: The web UI uses WebSockets to reflect changes instantly without needing to refresh.
- **Secure Authentication**: Initial setup wizard plus robust username/password authentication for the web interface.
- **Responsive Design**: The web manager is fully responsive and works on both desktop and mobile devices.
- **Dark Mode**: Because your eyes deserve it.

## 🛠️ Tech Stack

| Area      | Technology                                                                                                  |
| :-------- | :---------------------------------------------------------------------------------------------------------- |
| **Backend** | [Python](https://www.python.org/), [FastAPI](https://fastapi.tiangolo.com/), [yt-dlp](https://github.com/yt-dlp/yt-dlp), [uv](https://docs.astral.sh/uv/) |
| **Frontend**  | [React 19](https://react.dev/), [TypeScript](https://www.typescriptlang.org/), [Vite](https://vitejs.dev/), [Tailwind CSS](https://tailwindcss.com/), [TanStack Query](https://tanstack.com/query), [Framer Motion](https://www.framer.com/motion/) |
| **Database**  | [SQLite](https://www.sqlite.org/)                                                                           |

## 🚀 Getting Started

### Prerequisites

- **Python 3.10+**
- **uv** for Python dependency management.
- **Node.js and npm** (or yarn/pnpm) for the frontend.
- **FFmpeg** installed and accessible in your system's `PATH`.
- **Deno 2.3+** or **Node.js 22+** for yt-dlp's YouTube JavaScript challenge support on servers.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/H1ghSyst3m/ytnd-bot.git
    cd ytnd-bot
    ```

2.  **Configure the environment:**
    Create a `.env` file in the root of the project by copying the example:
    ```bash
    cp .env.example .env
    ```
    Now, edit the `.env` file with your details:

    ```env
    # Required
    MANAGER_SECRET="change-me-to-a-random-secret"

    # Manager server
    MANAGER_HOST="0.0.0.0"
    MANAGER_PORT="8080"
    # Optional: override auto-generated base URL (example)
    # MANAGER_BASE_URL="http://localhost:8080"

    # Data paths
    # Defaults in ytnd/config.py:
    # DATA_ROOT = PROJECT_ROOT / "data"
    # OUTPUT_ROOT = DATA_ROOT / "downloads"
    # COVERS_ROOT = DATA_ROOT / "covers"
    # LOG_DIR = DATA_ROOT / "logs"
    # DATABASE_FILE = DATA_ROOT / "ytnd.db"
    # COOKIES_FILE = DATA_ROOT / "cookies.txt"
    # DATA_ROOT="./data"
    # OUTPUT_ROOT="data/downloads"
    # COVERS_ROOT="data/covers"
    # LOG_DIR="data/logs"
    # DATABASE_FILE="data/ytnd.db"
    # COOKIES_FILE="data/cookies.txt"

    # Optional: only set when ffmpeg is not available in PATH
    # FFMPEG_PATH="/usr/bin/ffmpeg"

    # Optional yt-dlp / YouTube reliability controls
    # DOWNLOAD_WORKERS="1"
    # YTDLP_METADATA_WORKERS="1"
    # YTDLP_ITEM_DELAY="1.5"
    # YTDLP_FORCE_IPV4="false"
    # YTDLP_JS_RUNTIME="deno"
    # YTDLP_JS_RUNTIME_PATH="/usr/local/bin/deno"
    # YTDLP_PROXY=""
    # YTDLP_SOURCE_ADDRESS=""
    # YTDLP_USER_AGENT=""
    # YTDLP_EXTRACTOR_ARGS_JSON=""
    # YTDLP_SOCKET_TIMEOUT="30"
    # YTDLP_RETRIES="10"
    # YTDLP_FRAGMENT_RETRIES="10"
    # YTDLP_EXTRACTOR_RETRIES="3"
    # YTDLP_REQUEST_DELAY="0"
    # YTDLP_REMOTE_COMPONENTS=""
    # YTDLP_ANDROID_RETRY="false"

    # Optional: enable WebDAV endpoint
    WEBDAV_ENABLED="false"

    # Optional: auto-create first admin if no users exist
    # INITIAL_ADMIN_USERNAME="admin"
    # INITIAL_ADMIN_PASSWORD="changeme123"
    ```

    | Variable | Required | Default | Description |
    | :-- | :-- | :-- | :-- |
    | `MANAGER_SECRET` | Yes | – | Secret key used for signing sessions. |
    | `MANAGER_HOST` | No | `0.0.0.0` | Host/interface where the manager server listens. |
    | `MANAGER_PORT` | No | `8080` | Port used by the manager server. |
    | `MANAGER_BASE_URL` | No | Auto-generated (`http://MANAGER_HOST:MANAGER_PORT`) | Public base URL used by the manager. |
    | `DATA_ROOT` | No | `PROJECT_ROOT / "data"` | Root directory for app data. |
    | `OUTPUT_ROOT` | No | `DATA_ROOT / "downloads"` | Download output directory. |
    | `COVERS_ROOT` | No | `DATA_ROOT / "covers"` | Cover image directory. |
    | `LOG_DIR` | No | `DATA_ROOT / "logs"` | Log file directory. |
    | `DATABASE_FILE` | No | `DATA_ROOT / "ytnd.db"` | SQLite database file path. |
    | `COOKIES_FILE` | No | `DATA_ROOT / "cookies.txt"` | Path where your Netscape `cookies.txt` should be placed. Required for many server-side YouTube requests. |
    | `FFMPEG_PATH` | No | Uses `PATH`/auto-detect | Path to ffmpeg binary if not available globally. |
    | `DOWNLOAD_WORKERS` | No | `1` | Number of parallel download workers. Keep low on servers to reduce YouTube bot/rate-limit triggers. |
    | `YTDLP_METADATA_WORKERS` | No | `1` | Number of parallel metadata probe workers. |
    | `YTDLP_ITEM_DELAY` | No | `1.5` | Delay in seconds between sequential downloads. |
    | `YTDLP_FORCE_IPV4` | No | `false` | Force IPv4 for yt-dlp. Leave disabled unless your IPv6 route is broken. |
    | `YTDLP_JS_RUNTIME` | No | Auto-detect | Preferred JavaScript runtime: `deno`, `node`, `quickjs`, or `none`. |
    | `YTDLP_JS_RUNTIME_PATH` | No | Auto-detect | Path to the configured JS runtime executable. |
    | `YTDLP_PROXY` | No | – | Proxy URL passed to yt-dlp. Useful when a data-center IP is blocked. |
    | `YTDLP_SOURCE_ADDRESS` | No | – | Local source IP address passed to yt-dlp. |
    | `YTDLP_USER_AGENT` | No | yt-dlp default | Custom User-Agent for yt-dlp requests. |
    | `YTDLP_EXTRACTOR_ARGS_JSON` | No | – | JSON object merged into yt-dlp `extractor_args`, for advanced YouTube settings such as PO tokens. |
    | `YTDLP_SOCKET_TIMEOUT` | No | `30` | yt-dlp socket timeout in seconds. |
    | `YTDLP_RETRIES` | No | `10` | yt-dlp retry count for downloads/extraction. |
    | `YTDLP_FRAGMENT_RETRIES` | No | `10` | Retry count for media fragments. |
    | `YTDLP_EXTRACTOR_RETRIES` | No | `3` | Retry count for extractor failures. |
    | `YTDLP_REQUEST_DELAY` | No | `0` | Optional delay between yt-dlp HTTP requests. |
    | `YTDLP_REMOTE_COMPONENTS` | No | – | Opt-in remote EJS components. Set to `true` for `ejs:github`, or provide comma-separated values such as `ejs:github,ejs:npm`. This may fetch and execute remote code at yt-dlp runtime; enable only if you accept that supply-chain risk. |
    | `YTDLP_ANDROID_RETRY` | No | `false` | Enables a last-resort Android client retry after web/default extraction fails. |
    | `WEBDAV_ENABLED` | No | `false` | Enables WebDAV endpoints when set to `true`. |
    | `INITIAL_ADMIN_USERNAME` | No | – | Creates the initial admin user on startup (with password). |
    | `INITIAL_ADMIN_PASSWORD` | No | – | Password for `INITIAL_ADMIN_USERNAME`. |

3.  **Install backend dependencies:**
    Use uv to install Python dependencies.
    ```bash
    uv sync
    ```

4.  **Build the frontend:**
    Navigate to the frontend directory, install dependencies, and build the static assets.
    ```bash
    cd manager-frontend
    npm install
    npm run build
    cd ..
    ```
    The build output will be placed in `manager-frontend/dist`, which the backend server will serve automatically.

### Server-side YouTube reliability

On servers, install yt-dlp with its default extras so the EJS challenge solver package is available:

```bash
python -m pip install -U "yt-dlp[default]"
```

Install a JavaScript runtime for YouTube challenge solving. Deno is preferred by yt-dlp:

```bash
curl -fsSL https://deno.land/install.sh | sh
deno --version
```

Use a Netscape-format `cookies.txt` at `COOKIES_FILE`. For YouTube, export from a fresh private/incognito browser session:

1. Open a private/incognito window and sign in to YouTube.
2. Visit `https://www.youtube.com/robots.txt`.
3. Export cookies in Netscape `cookies.txt` format.
4. Close the private/incognito window and do not keep using that same session in a browser.
5. Copy the file to the server path configured by `COOKIES_FILE`.

The dashboard shows whether cookies look usable, whether `yt-dlp-ejs` is installed, and which JS runtime is available. Admins can also call `/api/system/youtube-diagnostics?url=...` for a no-download probe that classifies common YouTube failures.

`YTDLP_REMOTE_COMPONENTS` is intentionally off by default. Enabling it can let yt-dlp fetch and execute remote EJS components such as `ejs:github` or `ejs:npm` at runtime, so use it only as an explicit operator decision.

If YouTube blocks the server IP or account session, YTND can diagnose the category and pass proxy/source-address settings to yt-dlp, but it cannot make a flagged data-center IP universally trusted.

### Running the Application

Run the manager server directly.

```bash
uv run ytnd-manager
```

This starts the FastAPI web server for the manager UI.

## 🕹️ Usage

### Web Manager

1.  On first startup, complete the initial setup wizard to create the first admin account.
2.  Sign in with username and password.
3.  Explore the dashboard, manage songs, and monitor the download queue. Admins can also manage users and view logs.

### WebDAV

- Enable with `WEBDAV_ENABLED=true` in `.env`.
- Endpoint pattern: `/webdav/{user_id}/`
- Authentication: HTTP Basic Auth (`username:password`).
- Access rules: admins can access every user's folder, regular users only their own.
- Supported methods: `GET`, `HEAD`, `PROPFIND`, `OPTIONS`.
- Brute-force protection: temporary lockout after repeated failed logins.

### CLI

Use the CLI for automation/cronjobs:

```bash
uv run ytnd <url> [url ...] [-u USER] [-w WORKERS]
```

Example:

```bash
uv run ytnd https://youtube.com/watch?v=... -u myuser -w 4
```

## 📁 Project Structure

```
.
├── manager-frontend/   # React/Vite frontend application
│   ├── src/
│   └── package.json
├── ytnd/               # Python backend application
│   ├── __init__.py
│   ├── manager_server.py # FastAPI web server
│   ├── downloader.py   # yt-dlp wrapper and file processing
│   ├── database.py     # SQLite database management
│   ├── config.py       # Configuration loader
│   └── ...
├── .env.example        # Example environment file
└── pyproject.toml      # Python project definition
```
