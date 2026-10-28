"""RFC 5545 iCalendar feed for a shared course.

Students subscribe to ``/api/courses/{code}/calendar.ics`` by URL in Google
Calendar ("Other calendars → From URL"), which keeps the phone app at zero
permissions while still syncing every deadline.

Times are *floating* (no TZID, no Z): a due time of 23:59 shows as 23:59 in
whatever timezone the subscriber's calendar uses, matching the API's naive
datetimes.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime, timedelta, timezone

from .database import CourseRecord, TaskRecord

EVENT_LENGTH = timedelta(hours=1)
_FLOATING = "%Y%m%dT%H%M%S"


def build_calendar(course: CourseRecord, now: datetime | None = None) -> str:
    stamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc).strftime(_FLOATING) + "Z"
    name = course.course_code + (f" · {course.course_name}" if course.course_name else "")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//DueToday//Syllabus Tracker//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:{_escape(name)}",
        "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
        "X-PUBLISHED-TTL:PT6H",
    ]
    for task in _dated(course.tasks):
        lines += _event(course, task, stamp)
    lines.append("END:VCALENDAR")
    return "".join(_fold(line) + "\r\n" for line in lines)


def _dated(tasks: Iterable[TaskRecord]) -> list[TaskRecord]:
    return [t for t in tasks if t.due_datetime is not None]


def _event(course: CourseRecord, task: TaskRecord, stamp: str) -> list[str]:
    due = task.due_datetime
    assert due is not None
    details = [f"Type: {task.task_type}", f"Priority: {task.priority}"]
    if task.weight_percent is not None:
        details.append(f"Weight: {task.weight_percent:g}%")
    if task.points is not None:
        details.append(f"Points: {task.points}")
    if task.notes:
        details.append(task.notes)

    return [
        "BEGIN:VEVENT",
        f"UID:task-{task.id}-{course.share_code}@duetoday",
        f"DTSTAMP:{stamp}",
        f"DTSTART:{due.strftime(_FLOATING)}",
        f"DTEND:{(due + EVENT_LENGTH).strftime(_FLOATING)}",
        f"SUMMARY:{_escape(f'[{course.course_code}] {task.title}')}",
        f"DESCRIPTION:{_escape(chr(10).join(details))}",
        f"CATEGORIES:{_escape(task.task_type.upper())}",
        "TRANSP:TRANSPARENT",
        "END:VEVENT",
    ]


def _escape(text: str) -> str:
    """Escape a TEXT value (RFC 5545 §3.3.11)."""
    return (
        text.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
    )


def _fold(line: str, limit: int = 75) -> str:
    """Fold content lines longer than 75 octets (RFC 5545 §3.1), never
    splitting a multi-byte UTF-8 character."""
    if len(line.encode("utf-8")) <= limit:
        return line
    parts: list[str] = []
    current, size = "", 0
    for char in line:
        width = len(char.encode("utf-8"))
        # Continuation lines start with a space, which counts toward the limit.
        if size + width > (limit if not parts else limit - 1):
            parts.append(current)
            current, size = "", 0
        current += char
        size += width
    parts.append(current)
    return "\r\n ".join(parts)
