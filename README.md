# YTND Bot - YouTube Audio Downloader

[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python&logoColor=white)](https://www.python.org/)
[![React](https://img.shields.io/badge/React-19-blue?logo=react&logoColor=61DAFB)](https://react.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-green?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Telegram](https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram)](https://telegram.org/)
[![Syncthing](https://img.shields.io/badge/Syncthing-orange?logo=syncthing&logoColor=white)](https://syncthing.net/)

YTND Bot is a complete solution for downloading audio from YouTube, featuring a powerful backend, a user-friendly Telegram bot, and a sleek web-based management interface. It's designed for personal use, allowing users to build a music library and sync it seamlessly across devices using Syncthing.

## ✨ Features

- **Telegram Bot**: Easily add YouTube links, manage your download queue, and control your library directly from Telegram.
- **Modern Web UI**: A feature-rich web interface for managing songs, users, and system status with real-time updates.
- **Download Queue**: Add multiple URLs, process them in a batch, and see live progress updates.
- **Song Management**: View your entire library, search, re-download, delete, and download songs directly from the web UI.
- **Automatic Tagging**: Downloads are automatically tagged with metadata like title, artist, album, and cover art.
- **Syncthing Integration**: Automatically syncs your downloaded music library to your personal devices.
- **User Management**: Admin interface for managing users and their roles.
- **Real-time Updates**: The web UI uses WebSockets to reflect changes instantly without needing to refresh.
- **Secure Authentication**: One-time login links via Telegram and a robust username/password system for the web interface.
- **Responsive Design**: The web manager is fully responsive and works on both desktop and mobile devices.
- **Dark Mode**: Because your eyes deserve it.

## 🛠️ Tech Stack

| Area      | Technology                                                                                                  |
| :-------- | :---------------------------------------------------------------------------------------------------------- |
| **Backend** | [Python](https://www.python.org/), [FastAPI](https://fastapi.tiangolo.com/), [yt-dlp](https://github.com/yt-dlp/yt-dlp), [python-telegram-bot](https://python-telegram-bot.org/), [Poetry](https://python-poetry.org/) |
| **Frontend**  | [React 19](https://react.dev/), [TypeScript](https://www.typescriptlang.org/), [Vite](https://vitejs.dev/), [Tailwind CSS](https://tailwindcss.com/), [TanStack Query](https://tanstack.com/query), [Framer Motion](https://www.framer.com/motion/) |
| **Database**  | [SQLite](https://www.sqlite.org/)                                                                           |
| **Sync**      | [Syncthing](https://syncthing.net/)                                                                         |

## 🚀 Getting Started

### Prerequisites

- **Python 3.10+**
- **Poetry** for Python dependency management.
- **Node.js 20.x+** and **npm** (or yarn/pnpm) for the frontend.
- **Syncthing** installed and accessible in your system's `PATH`.
- **FFmpeg** installed and accessible in your system's `PATH`.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/H1ghSyst3m/ytnd.git
    cd ytnd
    ```

2.  **Configure the environment:**
    Create a `.env` file in the root of the project by copying the example:
    ```bash
    cp .env.example .env
    ```
    Now, edit the `.env` file with your details:

    ```env
    # --- REQUIRED ---
    # Your Telegram Bot Token from BotFather
    BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"

    # Your personal Telegram User ID (this will be the default admin)
    DEFAULT_ADMIN_ID="YOUR_TELEGRAM_USER_ID"

    # Your Syncthing API Key
    SYNCTHING_API_KEY="YOUR_SYNCTHING_API_KEY"

    # --- OPTIONAL ---
    # URL for the Syncthing API (if not running locally)
    SYNCTHING_URL="http://127.0.0.1:8384"

    # Base URL for the manager (used for generating login links)
    MANAGER_BASE_URL="http://127.0.0.1:8080"

    # Secret key for signing session cookies (defaults to BOT_TOKEN if not set)
    MANAGER_SECRET=""

    # Path to store all application data (logs, db, downloads)
    DATA_ROOT="./data"
    ```

3.  **Install backend dependencies:**
    Use Poetry to install all Python packages, including the optional `manager` group.
    ```bash
    poetry install --with manager
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

The easiest way to run all services (Syncthing, Telegram Bot, and Web Manager) is using the provided `run.py` script.

```bash
poetry run ytnd-all
```

This will:
1.  Start the Syncthing daemon.
2.  Start the Telegram bot process.
3.  Start the FastAPI web server process.

All services will run concurrently and will be gracefully shut down on `Ctrl+C`.

Alternatively, you can run services individually:
-   **Telegram Bot only**: `poetry run ytnd-bot`
-   **Web Manager only**: `poetry run ytnd-manager`

## 🕹️ Usage

### Telegram Bot

Start a chat with your bot on Telegram.
- **Send a YouTube link**: The bot will add the link to your download queue.
- **Send a `.txt` file**: The bot will parse all YouTube links from the file and add them to your queue.

**Available Commands:**
- `/start` - Shows a welcome message and lists available commands.
- `/download` - Starts processing the download queue.
- `/status` - Shows the current status (use `/download` for detailed progress).
- `/clear` - Clears all items from your download queue.
- `/sync` - Provides commands to pair your device with Syncthing for file synchronization.
- `/manager` - Generates a one-time link to access the web management UI.

### Web Manager

1.  Get a login link by sending the `/manager` command to your bot on Telegram.
2.  Open the link in your browser. You will be automatically logged in.
3.  Once logged in, you can create a permanent username and password in the **Profile** section to log in without a token in the future.
4.  Explore the dashboard, manage your songs, and monitor the download queue. If you are an admin, you can also manage users and view system logs.

## 🔌 Networking

If you are running this application behind a firewall, you will need to open the following ports for all services to function correctly:

| Port          | Protocol | Service          | Description                                             |
| :------------ | :------- | :--------------- | :------------------------------------------------------ |
| **8080**      | `TCP`    | Web Manager      | FastAPI server for the web UI. Configurable via `MANAGER_PORT` in `.env`. |
| **8384**      | `TCP`    | Syncthing API    | Web UI and REST API for Syncthing. Configurable via `SYNCTHING_URL` in `.env`. |
| **22000**     | `TCP`    | Syncthing Sync   | Main data synchronization port for Syncthing.           |
| **21027**     | `UDP`    | Syncthing Discovery | Used for local peer discovery.                          |

Ensure these ports are allowed through your firewall and, if necessary, forwarded on your router.

## 📁 Project Structure

```
.
├── manager-frontend/   # React/Vite frontend application
│   ├── src/
│   └── package.json
├── ytnd/               # Python backend application
│   ├── __init__.py
│   ├── bot.py          # Telegram bot logic
│   ├── manager_server.py # FastAPI web server
│   ├── downloader.py   # yt-dlp wrapper and file processing
│   ├── database.py     # SQLite database management
│   ├── config.py       # Configuration loader
│   └── ...
├── .env.example        # Example environment file
├── run.py              # Main script to run all services
└── pyproject.toml      # Python project definition
```