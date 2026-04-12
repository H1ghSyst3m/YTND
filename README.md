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
    # REQUIRED
    MANAGER_SECRET="change-me-to-a-random-secret"

    # OPTIONAL: auto-create first admin if no users exist
    # INITIAL_ADMIN_USERNAME="admin"
    # INITIAL_ADMIN_PASSWORD="changeme123"
    # WEBDAV_ENABLED="false"
    ```

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
