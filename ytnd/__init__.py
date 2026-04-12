# ytnd/__init__.py
from . import database
from .config import DATABASE_FILE, INITIAL_ADMIN_USERNAME, INITIAL_ADMIN_PASSWORD
from passlib.context import CryptContext

# Initialize database on module import
database.set_database_path(DATABASE_FILE)
database.initialize_database()

# Optional initial admin bootstrap for first start
if INITIAL_ADMIN_USERNAME and INITIAL_ADMIN_PASSWORD:
    pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")
    try:
        database.complete_initial_setup(
            "admin",
            INITIAL_ADMIN_USERNAME,
            pwd_context.hash(INITIAL_ADMIN_PASSWORD),
            role="admin",
        )
    except ValueError:
        pass
