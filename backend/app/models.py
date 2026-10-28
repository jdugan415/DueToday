"""Pydantic schemas that define the public JSON contract of the API.

Any change here is an API contract change: update AGENT_HANDOVER.md and
mobile/lib/services/api_service.dart in the same PR.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

TaskType = Literal[
    "exam",
    "midterm",
    "homework",
    "quiz",
    "project",
    "lab",
    "discussion",
    "essay",
    "assignment",
    "presentation",
    "other",
]
Priority = Literal["high", "medium", "low"]

# Share codes avoid look-alike characters (0/O, 1/I/L) so they can be read aloud in class.
SHARE_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
SHARE_CODE_LENGTH = 5
SHARE_CODE_PATTERN = rf"^[{SHARE_CODE_ALPHABET}]{{{SHARE_CODE_LENGTH}}}$"


# ---------------------------------------------------------------------------
# POST /api/parse
# ---------------------------------------------------------------------------


class ParseRequest(BaseModel):
    raw_text: str = Field(..., min_length=1, max_length=100_000)
    course_code: str | None = Field(default=None, max_length=20)
    # The client's local "today". Relative phrases ("due Tuesday") and
    # year-less dates are resolved against it. Defaults to the server's date.
    reference_date: date | None = None
    default_due_time: str = Field(default="23:59", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


class ParsedTask(BaseModel):
    id: str
    title: str
    task_type: TaskType
    due_date: date | None
    due_time: str  # "HH:MM", 24-hour, local wall-clock time
    due_datetime: datetime | None  # naive local datetime (no UTC offset)
    time_specified: bool  # False when due_time is the default fallback
    weight_percent: float | None = None
    points: int | None = None
    priority: Priority
    confidence: float = Field(ge=0.0, le=1.0)
    source_line: str


class ParseResponse(BaseModel):
    course_code: str | None
    reference_date: date
    tasks: list[ParsedTask]
    warnings: list[str]


# ---------------------------------------------------------------------------
# POST /api/courses  and  GET /api/courses/{code}
# ---------------------------------------------------------------------------


class TaskIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    task_type: TaskType = "other"
    due_datetime: datetime | None = None
    weight_percent: float | None = Field(default=None, ge=0, le=100)
    points: int | None = Field(default=None, ge=0)
    priority: Priority = "medium"
    notes: str | None = Field(default=None, max_length=2000)


class TaskOut(TaskIn):
    model_config = ConfigDict(from_attributes=True)

    id: int


class CourseCreate(BaseModel):
    course_code: str = Field(..., min_length=1, max_length=20)
    course_name: str | None = Field(default=None, max_length=120)
    tasks: list[TaskIn] = Field(default_factory=list, max_length=500)

    @field_validator("course_code")
    @classmethod
    def _normalize_code(cls, value: str) -> str:
        return " ".join(value.upper().split())


class CourseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    share_code: str
    course_code: str
    course_name: str | None
    created_at: datetime
    tasks: list[TaskOut]
