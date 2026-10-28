"""Database connector and ORM models.

Set DATABASE_URL to a Supabase Postgres connection string in production, e.g.
    postgresql://postgres.<ref>:<password>@aws-0-us-east-1.pooler.supabase.com:6543/postgres
Without it, a local SQLite file (./duetoday.db) is used so the API runs with
zero setup.

Schema changes go through Alembic (backend/migrations). After editing the
models below, run ``alembic revision --autogenerate -m "..."`` and review the
generated file. SQLite dev databases are still created with ``create_all``.
"""

from __future__ import annotations

import os
import secrets
from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, create_engine, select
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker

from .models import SHARE_CODE_ALPHABET, SHARE_CODE_LENGTH, CourseCreate


def normalize_database_url(url: str) -> str:
    """Point bare postgres:// URLs (Supabase, Render, Fly) at the psycopg 3 driver."""
    for prefix in ("postgres://", "postgresql://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix) :]
    return url


def make_engine(url: str) -> Engine:
    if url.startswith("sqlite"):
        return create_engine(url, connect_args={"check_same_thread": False})
    # prepare_threshold=None keeps psycopg compatible with Supabase's
    # transaction-mode pooler (PgBouncer), which rejects prepared statements.
    return create_engine(url, pool_pre_ping=True, connect_args={"prepare_threshold": None})


DATABASE_URL = normalize_database_url(os.getenv("DATABASE_URL", "sqlite:///./duetoday.db"))
engine = make_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class CourseRecord(Base):
    __tablename__ = "courses"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    share_code: Mapped[str] = mapped_column(String(SHARE_CODE_LENGTH), unique=True, index=True)
    course_code: Mapped[str] = mapped_column(String(20))
    course_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    tasks: Mapped[list[TaskRecord]] = relationship(
        back_populates="course",
        cascade="all, delete-orphan",
        order_by="TaskRecord.due_datetime",
    )


class TaskRecord(Base):
    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    task_type: Mapped[str] = mapped_column(String(32), default="other")
    # Naive local wall-clock time, matching the parser output (no UTC offset).
    due_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=False), nullable=True)
    weight_percent: Mapped[float | None] = mapped_column(Float, nullable=True)
    points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    priority: Mapped[str] = mapped_column(String(8), default="medium")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    course: Mapped[CourseRecord] = relationship(back_populates="tasks")


def init_db(bind: Engine | None = None) -> None:
    """Create tables for local SQLite databases.

    Postgres is managed by Alembic (``alembic upgrade head`` runs before the
    server starts in the Docker image); calling create_all there would create
    tables Alembic doesn't know about and break the next migration.
    """
    target = bind or engine
    if target.dialect.name == "sqlite":
        Base.metadata.create_all(target)


def get_db() -> Iterator[Session]:
    """FastAPI dependency yielding a request-scoped session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Repository functions
# ---------------------------------------------------------------------------


def generate_share_code() -> str:
    return "".join(secrets.choice(SHARE_CODE_ALPHABET) for _ in range(SHARE_CODE_LENGTH))


def create_course(db: Session, payload: CourseCreate, max_attempts: int = 10) -> CourseRecord:
    """Persist a course and its tasks under a fresh, unused 5-character share code."""
    for _ in range(max_attempts):
        code = generate_share_code()
        if db.scalar(select(CourseRecord.id).where(CourseRecord.share_code == code)) is None:
            break
    else:  # 31^5 ≈ 28.6M codes; exhausting retries means something is badly wrong.
        raise RuntimeError("Could not allocate a unique share code")

    course = CourseRecord(
        share_code=code,
        course_code=payload.course_code,
        course_name=payload.course_name,
        tasks=[TaskRecord(**task.model_dump()) for task in payload.tasks],
    )
    db.add(course)
    db.commit()
    db.refresh(course)
    return course


def get_course_by_share_code(db: Session, share_code: str) -> CourseRecord | None:
    return db.scalar(select(CourseRecord).where(CourseRecord.share_code == share_code.upper()))
