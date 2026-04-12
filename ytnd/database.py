# ytnd/database.py
"""
SQLite database module for user and token management.
"""
from __future__ import annotations
import sqlite3
from pathlib import Path
from typing import Optional, Dict, List, Any
from contextlib import contextmanager

_DB_PATH: Optional[Path] = None


def set_database_path(path: Path) -> None:
    """Set the database file path."""
    global _DB_PATH
    _DB_PATH = path


@contextmanager
def get_connection():
    """Get a database connection with proper cleanup."""
    if _DB_PATH is None:
        raise RuntimeError("Database path not set. Call set_database_path() first.")
    
    conn = None
    try:
        conn = sqlite3.connect(str(_DB_PATH), timeout=10.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        yield conn
    except sqlite3.OperationalError as e:
        if conn:
            conn.close()
        raise RuntimeError(f"Database connection failed: {e}")
    finally:
        if conn:
            conn.close()


def initialize_database() -> None:
    """
    Initialize the database with users and queue tables.
    Safe to call multiple times (uses IF NOT EXISTS).
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                uid TEXT PRIMARY KEY,
                role TEXT NOT NULL DEFAULT 'user',
                username TEXT UNIQUE,
                password_hash TEXT
            )
        """)
        
        # Queue table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS queue (
                uid TEXT NOT NULL,
                url TEXT NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY (uid, position),
                FOREIGN KEY (uid) REFERENCES users(uid) ON DELETE CASCADE
            )
        """)
        
        # Index for queue queries
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_queue_uid ON queue(uid, position)
        """)
        
        conn.commit()

def add_user(uid: str, role: str = "user") -> None:
    """
    Add a new user to the database.
    
    Args:
        uid: User ID
        role: User role ('admin' or 'user')
    
    Raises:
        ValueError: If user already exists or invalid input
    """
    if not uid or not isinstance(uid, str):
        raise ValueError("Invalid user ID")
    if role not in ("admin", "user"):
        raise ValueError("Role must be 'admin' or 'user'")
    
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT INTO users (uid, role) VALUES (?, ?)",
                (str(uid), role)
            )
            conn.commit()
        except sqlite3.IntegrityError:
            raise ValueError(f"User {uid} already exists")


def get_user(uid: str) -> Optional[Dict[str, Any]]:
    """
    Get user information by UID.
    
    Args:
        uid: User ID
    
    Returns:
        Dictionary with user info or None if not found
        Format: {"uid": str, "role": str, "username": str|None, "password_hash": str|None}
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT uid, role, username, password_hash FROM users WHERE uid = ?", (str(uid),))
        row = cursor.fetchone()
        if row:
            return {
                "uid": row["uid"],
                "role": row["role"],
                "username": row["username"],
                "password_hash": row["password_hash"]
            }
        return None


def update_user_role(uid: str, role: str) -> bool:
    """
    Update a user's role.
    
    Args:
        uid: User ID
        role: New role ('admin' or 'user')
    
    Returns:
        True if user was updated, False if user not found
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET role = ? WHERE uid = ?", (role, str(uid)))
        conn.commit()
        return cursor.rowcount > 0


def remove_user(uid: str) -> bool:
    """
    Remove a user from the database.
    
    Args:
        uid: User ID
    
    Returns:
        True if user was removed, False if user not found
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE uid = ?", (str(uid),))
        conn.commit()
        return cursor.rowcount > 0


def list_users() -> Dict[str, Dict[str, Any]]:
    """
    List all users.
    
    Returns:
        Dictionary mapping uid to user info
        Format: {"uid": {"role": str}, ...}
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT uid, role FROM users")
        users = {}
        for row in cursor.fetchall():
            users[row["uid"]] = {
                "role": row["role"],
            }
        return users


def get_queue(uid: str) -> List[str]:
    """
    Get the download queue for a user, ordered by position.
    
    Args:
        uid: User ID
    
    Returns:
        List of URLs in queue order
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT url FROM queue WHERE uid = ? ORDER BY position",
            (str(uid),)
        )
        return [row["url"] for row in cursor.fetchall()]


def set_queue(uid: str, urls: List[str]) -> None:
    """
    Replace the entire queue for a user.
    
    Args:
        uid: User ID
        urls: List of URLs to set as the new queue
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM queue WHERE uid = ?", (str(uid),))
        for position, url in enumerate(urls):
            cursor.execute(
                "INSERT INTO queue (uid, url, position) VALUES (?, ?, ?)",
                (str(uid), url, position)
            )
        conn.commit()


def add_to_queue(uid: str, urls: List[str]) -> None:
    """
    Add new URLs to the end of a user's queue.
    
    Args:
        uid: User ID
        urls: List of URLs to add to the queue
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT MAX(position) as max_pos FROM queue WHERE uid = ?",
            (str(uid),)
        )
        row = cursor.fetchone()
        next_position = (row["max_pos"] + 1) if row["max_pos"] is not None else 0
        
        for url in urls:
            cursor.execute(
                "INSERT INTO queue (uid, url, position) VALUES (?, ?, ?)",
                (str(uid), url, next_position)
            )
            next_position += 1
        
        conn.commit()


# ────────────────────── User Credentials Management ──────────────────────

def get_user_by_username(username: str) -> Optional[Dict[str, Any]]:
    """
    Get user information by username.
    
    Args:
        username: Username to look up
    
    Returns:
        Dictionary with user info or None if not found
        Format: {"uid": str, "role": str, "username": str, "password_hash": str}
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT uid, role, username, password_hash FROM users WHERE username = ?",
            (username,)
        )
        row = cursor.fetchone()
        if row:
            return {
                "uid": row["uid"],
                "role": row["role"],
                "username": row["username"],
                "password_hash": row["password_hash"]
            }
        return None


def set_user_credentials(uid: str, username: str, password_hash: str) -> bool:
    """
    Set or update username and password for a user.
    
    Args:
        uid: User ID
        username: New username (must be unique)
        password_hash: Hashed password
    
    Returns:
        True if credentials were set, False if username already exists
    
    Raises:
        ValueError: If user doesn't exist
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        
        cursor.execute("SELECT uid FROM users WHERE uid = ?", (str(uid),))
        if not cursor.fetchone():
            raise ValueError(f"User {uid} does not exist")
        
        try:
            cursor.execute(
                "UPDATE users SET username = ?, password_hash = ? WHERE uid = ?",
                (username, password_hash, str(uid))
            )
            conn.commit()
            return True
        except sqlite3.IntegrityError:
            return False


def create_user_with_credentials(uid: str, username: str, password_hash: str, role: str = "admin") -> None:
    """Create a user with credentials atomically."""
    if not uid or not isinstance(uid, str):
        raise ValueError("Invalid user ID")
    if not username or not isinstance(username, str):
        raise ValueError("Invalid username")
    if not password_hash or not isinstance(password_hash, str):
        raise ValueError("Invalid password hash")
    if role not in ("admin", "user"):
        raise ValueError("Role must be 'admin' or 'user'")

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM users WHERE username = ? LIMIT 1", (username,))
        if cursor.fetchone():
            raise ValueError("Username already exists")

        try:
            cursor.execute(
                "INSERT INTO users (uid, role, username, password_hash) VALUES (?, ?, ?, ?)",
                (str(uid), role, username, password_hash),
            )
            conn.commit()
        except sqlite3.IntegrityError as e:
            cursor.execute("SELECT 1 FROM users WHERE username = ? LIMIT 1", (username,))
            if cursor.fetchone():
                raise ValueError("Username already exists") from e
            raise ValueError("User already exists") from e


def complete_initial_setup(uid: str, username: str, password_hash: str, role: str = "admin") -> None:
    """
    Atomically verify setup is incomplete and create the first admin user.

    Raises:
        ValueError("Already set up") – if a credentialed user already exists.
        ValueError("Username already exists") – username UNIQUE constraint violated.
        ValueError("User already exists") – uid PRIMARY KEY collision.
    """
    if not uid or not isinstance(uid, str):
        raise ValueError("Invalid user ID")
    if not username or not isinstance(username, str):
        raise ValueError("Invalid username")
    if not password_hash or not isinstance(password_hash, str):
        raise ValueError("Invalid password hash")
    if role not in ("admin", "user"):
        raise ValueError("Role must be 'admin' or 'user'")

    if _DB_PATH is None:
        raise RuntimeError("Database path not set. Call set_database_path() first.")

    conn = sqlite3.connect(str(_DB_PATH), timeout=10.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        conn.execute("BEGIN EXCLUSIVE")
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT 1 FROM users
            WHERE username IS NOT NULL AND username != ''
              AND password_hash IS NOT NULL AND password_hash != ''
            LIMIT 1
            """
        )
        if cursor.fetchone():
            conn.execute("ROLLBACK")
            raise ValueError("Already set up")

        try:
            cursor.execute(
                "INSERT INTO users (uid, role, username, password_hash) VALUES (?, ?, ?, ?)",
                (str(uid), role, username, password_hash),
            )
            conn.execute("COMMIT")
        except sqlite3.IntegrityError as e:
            conn.execute("ROLLBACK")
            cursor.execute("SELECT 1 FROM users WHERE username = ? LIMIT 1", (username,))
            if cursor.fetchone():
                raise ValueError("Username already exists") from e
            raise ValueError("User already exists") from e
    except Exception:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        raise
    finally:
        conn.close()


def count_admins() -> int:
    """Return the number of users with the admin role."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM users WHERE role = 'admin'")
        row = cursor.fetchone()
        return row[0] if row else 0


def remove_user_if_not_last_admin(uid: str) -> None:
    """
    Atomically remove a user unless they are the last admin.

    Raises:
        ValueError("User not found") – uid does not exist.
        ValueError("Last admin") – user is the only remaining admin.
    """
    if _DB_PATH is None:
        raise RuntimeError("Database path not set. Call set_database_path() first.")

    conn = sqlite3.connect(str(_DB_PATH), timeout=10.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        conn.execute("BEGIN EXCLUSIVE")
        cursor = conn.cursor()

        cursor.execute("SELECT role FROM users WHERE uid = ?", (str(uid),))
        row = cursor.fetchone()
        if not row:
            conn.execute("ROLLBACK")
            raise ValueError("User not found")

        if row["role"] == "admin":
            cursor.execute("SELECT COUNT(*) FROM users WHERE role = 'admin'")
            count_row = cursor.fetchone()
            if (count_row[0] if count_row else 0) <= 1:
                conn.execute("ROLLBACK")
                raise ValueError("Last admin")

        cursor.execute("DELETE FROM users WHERE uid = ?", (str(uid),))
        conn.execute("COMMIT")
    except Exception:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        raise
    finally:
        conn.close()


def update_user_password(uid: str, password_hash: str) -> bool:
    """
    Update password for a user.
    
    Args:
        uid: User ID
        password_hash: New hashed password
    
    Returns:
        True if password was updated, False if user not found
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE users SET password_hash = ? WHERE uid = ?",
            (password_hash, str(uid))
        )
        conn.commit()
        return cursor.rowcount > 0


def is_setup_complete() -> bool:
    """Return True when at least one user has both username and password hash set."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 1
            FROM users
            WHERE username IS NOT NULL
              AND username != ''
              AND password_hash IS NOT NULL
              AND password_hash != ''
            LIMIT 1
            """
        )
        return cursor.fetchone() is not None
