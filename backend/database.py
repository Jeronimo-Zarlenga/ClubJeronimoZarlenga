import os
from sqlalchemy import create_engine, inspect
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()


def normalize_database_url(database_url: str) -> str:
    """Normaliza la URL de PostgreSQL para SQLAlchemy y conserva SQLite-local."""
    database_url = database_url.strip()
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql://", 1)
    return database_url


# Si existe DATABASE_URL en .env (Render/PostgreSQL), usa esa; si no, usa SQLite local para pruebas
DATABASE_URL = normalize_database_url(os.getenv("DATABASE_URL", "sqlite:///./club_jeronimo.db"))

# Ajuste específico para SQLite si corre en local
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
else:
    engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def upgrade_schema():
    """Apply small additive migrations for existing SQLite/PostgreSQL databases."""
    inspector = inspect(engine)
    if "usuarios" not in inspector.get_table_names():
        return

    user_columns = {column["name"] for column in inspector.get_columns("usuarios")}
    dialect = engine.dialect.name
    if "firebase_uid" not in user_columns:
        with engine.begin() as connection:
            connection.exec_driver_sql("ALTER TABLE usuarios ADD COLUMN firebase_uid VARCHAR")
    if "is_admin" not in user_columns:
        default = "FALSE" if dialect == "postgresql" else "0"
        with engine.begin() as connection:
            connection.exec_driver_sql(
                f"ALTER TABLE usuarios ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT {default}"
            )
    if "fecha_nacimiento" not in user_columns:
        with engine.begin() as connection:
            connection.exec_driver_sql(
                "ALTER TABLE usuarios ADD COLUMN fecha_nacimiento DATE"
            )
    inspector = inspect(engine)
    user_indexes = {index["name"] for index in inspector.get_indexes("usuarios")}
    if "ix_usuarios_firebase_uid" not in user_indexes:
        with engine.begin() as connection:
            connection.exec_driver_sql(
                "CREATE UNIQUE INDEX ix_usuarios_firebase_uid ON usuarios (firebase_uid)"
            )

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()