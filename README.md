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
- **Deno** or another supported JavaScript runtime for YouTube extraction on servers.

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

    # Optional: YouTube JavaScript runtime. Leave unset to auto-detect deno, node, or qjs.
    # YTND_JS_RUNTIME="auto"
    # YTND_JS_RUNTIME_PATH="/usr/local/bin/deno"

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
    | `COOKIES_FILE` | No | `DATA_ROOT / "cookies.txt"` | Path where your Netscape-format YouTube `cookies.txt` should be placed. |
    | `FFMPEG_PATH` | No | Uses `PATH`/auto-detect | Path to ffmpeg binary if not available globally. |
    | `YTND_JS_RUNTIME` | No | `auto` | JavaScript runtime name to use for yt-dlp (`auto`, `deno`, `node`, or `quickjs`). |
    | `YTND_JS_RUNTIME_PATH` | No | Auto-detect | Explicit path to the JavaScript runtime executable. Deno is recommended for servers. |
    | `WEBDAV_ENABLED` | No | `false` | Enables WebDAV endpoints when set to `true`. |
    | `INITIAL_ADMIN_USERNAME` | No | – | Creates the initial admin user on startup (with password). |
    | `INITIAL_ADMIN_PASSWORD` | No | – | Password for `INITIAL_ADMIN_USERNAME`. |

    YouTube cookies must be exported in Mozilla/Netscape `cookies.txt` format. For the most reliable export, open a private/incognito browser window, log into YouTube, navigate that same tab to `https://www.youtube.com/robots.txt`, export the `youtube.com` cookies, then close the private window so the exported session is not rotated by the browser.

    On Pelican installs, update/reinstall the egg after upgrading so `/home/container/bin/deno` is installed and `YTND_JS_RUNTIME_PATH` is set automatically.

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
