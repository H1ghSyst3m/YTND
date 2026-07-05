# ytnd/__init__.py
from . import database
from .config import DATABASE_FILE, INITIAL_ADMIN_USERNAME, INITIAL_ADMIN_PASSWORD
from passlib.context import CryptContext
from uuid import uuid4

# Initialize database on module import
database.set_database_path(DATABASE_FILE)
database.initialize_database()

# Optional initial admin bootstrap for first start
if INITIAL_ADMIN_USERNAME and INITIAL_ADMIN_PASSWORD:
    max_uid_generation_attempts = 5
    pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")
    password_hash = pwd_context.hash(INITIAL_ADMIN_PASSWORD)
    for _ in range(max_uid_generation_attempts):
        uid = uuid4().hex[:12]
        try:
            database.complete_initial_setup(
                uid,
                INITIAL_ADMIN_USERNAME,
                password_hash,
                role="admin",
            )
            break
        except ValueError as e:
            error_message = str(e)
            if "Already set up" in error_message:
                break
            if "User already exists" in error_message:
                continue
            raise
    else:
        raise RuntimeError(
            f"Failed to create initial admin user after {max_uid_generation_attempts} UID generation attempts"
        )
