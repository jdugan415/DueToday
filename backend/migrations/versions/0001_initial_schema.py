"""Initial schema: courses and tasks.

Revision ID: 0001
Revises:
Create Date: 2026-10-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "courses",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("share_code", sa.String(length=5), nullable=False),
        sa.Column("course_code", sa.String(length=20), nullable=False),
        sa.Column("course_name", sa.String(length=120), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_courses_share_code", "courses", ["share_code"], unique=True)

    op.create_table(
        "tasks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "course_id",
            sa.Integer(),
            sa.ForeignKey("courses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("task_type", sa.String(length=32), nullable=False),
        sa.Column("due_datetime", sa.DateTime(timezone=False), nullable=True),
        sa.Column("weight_percent", sa.Float(), nullable=True),
        sa.Column("points", sa.Integer(), nullable=True),
        sa.Column("priority", sa.String(length=8), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
    )
    op.create_index("ix_tasks_course_id", "tasks", ["course_id"])


def downgrade() -> None:
    op.drop_index("ix_tasks_course_id", table_name="tasks")
    op.drop_table("tasks")
    op.drop_index("ix_courses_share_code", table_name="courses")
    op.drop_table("courses")
