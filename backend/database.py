import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()

# Si existe DATABASE_URL en .env (Render/PostgreSQL), usa esa; si no, usa SQLite local para pruebas
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./club_jeronimo.db")

# Ajuste específico para SQLite si corre en local
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
else:
    # Render suele entregar postgres://, SQLAlchemy prefiere postgresql://
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
    engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()