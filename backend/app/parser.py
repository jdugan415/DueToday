"""Deterministic syllabus schedule parser.

Takes raw, unformatted schedule text (pasted from a PDF, LMS page, or email)
and extracts dated, weighted assignments. No ML model and no network calls:
the same input and reference date always produce the same output, which keeps
the parser testable and free to host.

Pipeline, per line:
  1. Strip bullets; skip holiday / "no class" lines.
  2. Find explicit dates (ISO, MM/DD[/YYYY], "Sept 28", "October 4th"),
     merging "9/14 - 9/18" style ranges.
  3. Find relative dates ("Tuesday", "next Fri", "tomorrow"), resolved against
     the line's own date, the most recent schedule date above it, or the
     reference date, in that order.
  4. Find times, weights (20%) and points (50 pts).
  5. Find task keywords (Exam, HW, Quiz, ...) and slice the line into one
     segment per task, then pick each task's date/time/weight from its segment.

Lines that contain a date but no task keyword (e.g. "Week 5 (Sept 21)") become
the context date for undated task lines that follow them.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from .models import ParsedTask, ParseResponse

DEFAULT_DUE_TIME = "23:59"

_MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}
_WEEKDAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}

_MONTH_PATTERN = (
    r"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|"
    r"aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
)
_WEEKDAY_PATTERN = (
    r"(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|"
    r"fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
)

# --- dates -----------------------------------------------------------------
_ISO_DATE_RE = re.compile(r"(?<!\d)(?P<year>20\d{2})-(?P<month>\d{1,2})-(?P<day>\d{1,2})(?!\d)")
_NUMERIC_DATE_RE = re.compile(
    r"(?<![\d/.])(?P<month>\d{1,2})/(?P<day>\d{1,2})(?:/(?P<year>\d{4}|\d{2}))?(?![\d/])"
)
_MONTH_DATE_RE = re.compile(
    rf"\b(?P<month>{_MONTH_PATTERN})\.?\s+(?P<day>\d{{1,2}})(?:st|nd|rd|th)?(?!\w)"
    r"(?:,?\s+(?P<year>20\d{2})(?!\d))?",
    re.IGNORECASE,
)
_WEEKDAY_RE = re.compile(
    rf"\b(?:(?P<mod>next|this)\s+)?(?P<day>{_WEEKDAY_PATTERN})\b\.?", re.IGNORECASE
)
_RELATIVE_DAY_RE = re.compile(r"\b(?P<word>today|tonight|tomorrow)\b", re.IGNORECASE)
_RANGE_JOIN_RE = re.compile(r"\s*(?:-|–|—|to|through|thru)\s*", re.IGNORECASE)

# --- times -----------------------------------------------------------------
_TIME_12H_RE = re.compile(
    r"(?<![\d:])(?P<hour>1[0-2]|0?[1-9])(?::(?P<minute>[0-5]\d))?\s*(?P<meridiem>[ap])\.?\s?m\b\.?",
    re.IGNORECASE,
)
_TIME_24H_RE = re.compile(
    r"(?<![\d:/])(?P<hour>[01]?\d|2[0-3]):(?P<minute>[0-5]\d)(?![\d:])(?!\s*[ap]\.?\s?m\b)",
    re.IGNORECASE,
)
_NAMED_TIME_RE = re.compile(r"\b(?P<name>noon|midnight|end of day|eod)\b", re.IGNORECASE)

# --- grading weight ----------------------------------------------------------
_PERCENT_RE = re.compile(r"(?<![\d.])(?P<value>\d{1,3}(?:\.\d+)?)\s*%")
_POINTS_RE = re.compile(r"(?<![\d.])(?P<value>\d{1,4})\s*(?:pts?|points?)\b\.?", re.IGNORECASE)

# --- tasks -----------------------------------------------------------------
_TASK_RE = re.compile(
    r"\b(?P<kw>final\s+exam(?:ination)?s?|final\s+projects?|final\s+presentations?|final\s+reports?|"
    r"final\s+papers?|midterm\s+exam(?:ination)?s?|midterms?|finals?|exam(?:ination)?s?|"
    r"homeworks?|hw|quiz(?:zes)?|projects?|labs?|discussions?|essays?|assignments?|presentations?)"
    r"(?![a-z])",
    re.IGNORECASE,
)
# A keyword followed by these words is an announcement, not a deliverable:
# "Exam 1 review", "HW 3 assigned", "Midterm grades posted".
_SKIP_AFTER_RE = re.compile(
    r"\s*(?:#?\d+[a-z]?\s*)?(?:review|solutions?|sessions?|grades?|returned|key|prep|help|overview|"
    r"feedback|assigned|released|posted|available|handed\s+out|announced|out(?!\s+of))\b",
    re.IGNORECASE,
)
# Full syllabi are mostly policy prose ("Homework assignments should be
# submitted...", "The final examination accounts for 35%"). A keyword followed
# within two words by one of these is part of a sentence, not a deliverable.
# Scheduling phrases ("will be held", "will take place") are still deliverables.
_PROSE_AFTER_RE = re.compile(
    r"\s*(?:[^\s,;:.()]+\s+){0,2}?"
    r"(?:accounts?|contributes?|counts?\s+(?:for|toward)|"
    r"will(?!\s+(?:be\s+(?:held|given|due|on|in)|take\s+place|open|close))|should|must|may|can|cannot|"
    r"polic(?:y|ies)|weights?|percentages?|components?|categor(?:y|ies)|instructions?|guidelines?|"
    r"requirements?|dates|topics|assignments|grade|scores?|rubrics?|period|schedule)\b",
    re.IGNORECASE,
)
# "quiz, laboratory, and exam scores": a keyword starting a lowercase list is prose.
_PROSE_LIST_AFTER_RE = re.compile(r",\s*(?:and\s+|or\s+)?[a-z]")
# A bare "Final" is the final exam only when nothing word-like follows it
# ("Dec 9  Final", "Final (35%)"); "Final date to drop" or "Final course grade"
# are not deliverables.
_BARE_FINAL_OK_RE = re.compile(r"\s*(?:$|[(\-–—:,;|\d]|\s{2,})")
# Context dates (from a header row above) only flow into short schedule lines.
_MAX_CONTEXT_LINE_WORDS = 8
# Undated items longer than this are sentence fragments, not titles.
_MAX_UNDATED_TITLE_WORDS = 4
# A dated title that reads like a sentence (long, or containing a verb) and
# duplicates another item's type and due time is the sentence describing that
# item ("Midterm exam will be held on Oct 15 at 9:00 AM").
_MAX_TITLE_WORDS_BEFORE_SENTENCE = 5
_SENTENCE_VERB_RE = re.compile(r"\b(?:will|is|are|was|were|be|been)\b", re.IGNORECASE)
_SKIP_BEFORE_RE = re.compile(
    r"(?:\breview\s+(?:for|of)|\bstudy\s+for|\bprep(?:are)?\s+for|\bno)\s+(?:the\s+)?$",
    re.IGNORECASE,
)
_COMPOUND_BREAK_RE = re.compile(
    r"[,;:|()\[\]{}\t/–—]|\s-\s|\s{3,}|\b(?:and|or|plus|due|then|also)\b", re.IGNORECASE
)
_SKIP_LINE_RE = re.compile(
    r"\b(?:no\s+class(?:es)?|class(?:es)?\s+cancel+ed|holiday|spring\s+break|fall\s+break|"
    r"thanksgiving|office\s+hours|reading\s+day)\b",
    re.IGNORECASE,
)

# --- titles ----------------------------------------------------------------
_BULLET_RE = re.compile(r"^\s*(?:[-*•●▪◦‣>]+|\(?\d{1,2}[.)])\s+")
_DUE_PREFIX_RE = re.compile(
    r"(?:\bdue|\bby|\bon|\bdeadline|\bsubmit(?:ted)?)\b(?:\s+(?:on|by|date))?\s*[:\-–—]?\s*$",
    re.IGNORECASE,
)
_TITLE_STOP_RE = re.compile(
    r"\s+(?:is\s+)?(?:due|by|worth|deadline|submit(?:ted)?)\b|[;|()\[\]{}\t]|\s[-–—]\s*(?=\d)|,\s*(?=\d)|\s{3,}",
    re.IGNORECASE,
)
_TRAILING_JUNK_RE = re.compile(
    r"(?:[\s,:;.\-–—&/]+|\s+(?:and|or|plus|also|is|are|on|at|by|the|due)\b)+$", re.IGNORECASE
)
# Tabs and runs of 3+ spaces are table-cell boundaries (PDF layout extraction,
# text copied out of tables): a title never borrows words from the previous cell.
_PREFIX_CUT_RE = re.compile(r"[:;|()\[\]{}\t,–—]|\s-\s|\s{3,}|\bdue\b", re.IGNORECASE)
_PREFIX_WORD_RE = re.compile(r"[A-Z][A-Za-z'&+/-]*|\d{1,2}[A-Za-z]?")
_PREFIX_BLOCKLIST = {
    "due", "by", "on", "the", "and", "or", "also", "week", "today", "tomorrow", "tonight",
    "at", "no", "for", "of", "in", "class", "complete", "submit", "take", "turn", "read",
    "finish", "start", "begin", "next", "this",
}

_COURSE_CODE_RE = re.compile(r"\b(?P<dept>[A-Z]{2,4})\s?-?\s?(?P<num>\d{4}|\d{3}[A-Z]?)\b")
_COURSE_CODE_EXCLUDE = {
    "HW", "AM", "PM", "PTS", "LAB", "EXAM", "QUIZ", "RM", "ROOM", "CH", "PG", "PP", "DUE",
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "SEPT", "OCT", "NOV", "DEC",
}


@dataclass(frozen=True)
class _DateHit:
    start: int
    end: int
    value: date  # the due date (range end for "9/14 - 9/18")
    anchor: date  # the date relative weekdays resolve from (range start)
    relative: bool


@dataclass(frozen=True)
class _TimeHit:
    start: int
    end: int
    value: time


@dataclass(frozen=True)
class _MeasureHit:
    start: int
    end: int
    kind: str  # "percent" | "points"
    value: float


@dataclass
class _Context:
    anchor: date | None = None
    due: date | None = None


@dataclass
class _Draft:
    title: str
    task_type: str
    due_date: date | None
    due_time: time | None
    weight_percent: float | None
    points: int | None
    confidence: float
    source_line: str


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_syllabus(
    raw_text: str,
    *,
    course_code: str | None = None,
    reference_date: date | None = None,
    default_due_time: str = DEFAULT_DUE_TIME,
    class_days: list[int] | None = None,
) -> ParseResponse:
    """Extract assignments from raw syllabus text.

    ``reference_date`` should be the user's local "today"; it anchors relative
    weekdays and decides the year of year-less dates (the occurrence nearest
    to it wins, so a December paste of "1/15 Exam" lands in January next year).
    """
    reference = reference_date or date.today()
    fallback_time = _parse_hhmm(default_due_time)
    context = _Context()
    drafts: list[_Draft] = []

    # Only infer weekdays from explicitly labeled meeting information, never
    # from assignment dates or holiday notices elsewhere in the syllabus.
    if class_days is None:
        names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
        for line in raw_text.splitlines():
            if re.search(r"\b(?:class\s+days|meets|meeting\s+days)\s*[:=-]?", line, re.I):
                found = [i for i, name in enumerate(names) if re.search(rf"\b{name}s?\b", line, re.I)]
                if len(found) == 2:
                    class_days = found
                    break
    prose, weekly_drafts = _weekly_table_drafts(raw_text, reference, class_days)
    for raw_line in prose.splitlines():
        line = _BULLET_RE.sub("", raw_line).strip()
        if not line or _SKIP_LINE_RE.search(line):
            continue
        drafts.extend(_parse_line(line, reference, context))
    drafts = _consolidate(drafts) + weekly_drafts

    tasks: list[ParsedTask] = []
    warnings: list[str] = []
    if any(d.due_date is None for d in weekly_drafts):
        warnings.append(
            "This weekly table needs class weekdays or exact deadlines for some items. "
            "Week/session labels are preserved; set dates for these items before saving."
        )
    seen: set[tuple[str, date | None]] = set()
    resolved_code = _normalize_course_code(course_code) or detect_course_code(raw_text)

    for draft in drafts:
        key = (draft.title.lower(), draft.due_date)
        if key in seen:
            continue
        seen.add(key)

        due_time = draft.due_time or fallback_time
        confidence = draft.confidence - (0.05 if draft.due_time is None else 0.0)
        due_datetime = datetime.combine(draft.due_date, due_time) if draft.due_date else None
        if draft.due_date is None:
            warnings.append(f"No date found for '{draft.title}'. Set one before saving.")

        tasks.append(
            ParsedTask(
                id=_task_id(resolved_code, draft.title, draft.due_date),
                title=draft.title,
                task_type=draft.task_type,  # type: ignore[arg-type]
                due_date=draft.due_date,
                due_time=due_time.strftime("%H:%M"),
                due_datetime=due_datetime,
                time_specified=draft.due_time is not None,
                weight_percent=draft.weight_percent,
                points=draft.points,
                priority=compute_priority(draft.task_type, draft.weight_percent, draft.points),
                confidence=round(max(0.0, min(1.0, confidence)), 2),
                source_line=draft.source_line,
            )
        )

    if not tasks:
        warnings.append(
            "No assignments were detected. Make sure the text includes keywords such as "
            "Exam, Midterm, HW, Quiz, Project, Lab, or Discussion."
        )

    tasks.sort(key=lambda t: (t.due_datetime is None, t.due_datetime or datetime.max, t.title))
    return ParseResponse(
        needs_class_days=any(d.due_date is None and "class [" in d.source_line for d in weekly_drafts) and class_days is None,
        course_code=resolved_code,
        reference_date=reference,
        tasks=tasks,
        warnings=warnings,
    )


_WEEK_ROW_RE = re.compile(r"^\s*week\s+(\d{1,2})\b", re.IGNORECASE)
_SESSION_HEADER_RE = re.compile(r"(?:1st|first|2nd|second)\s+day\s+of\s+the\s+week", re.IGNORECASE)
_TEACHING_CELL_RE = re.compile(r"\b(?:lecture|introduction|workday|syllabus)\b", re.IGNORECASE)


def _weekly_table_drafts(text: str, reference: date, class_days: list[int] | None = None) -> tuple[str, list[_Draft]]:
    """Isolate ordinal-session tables before line-based date association.

    These columns identify class sessions, not weekdays. Never borrow a date
    from another cell (especially administrative notes), or guess a deadline
    from a week range. Keep the week/session in the review title instead.
    Only opt in when both ordinal headers and a Week row are present.
    """
    lines = text.expandtabs(8).splitlines()
    header_index = next((i for i, line in enumerate(lines)
                         if len(_SESSION_HEADER_RE.findall(line)) == 2), None)
    if header_index is None:
        return text, []
    headers = list(_SESSION_HEADER_RE.finditer(lines[header_index]))
    weeks = [(i, _WEEK_ROW_RE.match(line)) for i, line in enumerate(lines)
             if i > header_index and _WEEK_ROW_RE.match(line)]
    if not weeks:
        return text, []
    # Content is left aligned while headers may be centered. Locate the first
    # content cell from a week row, and boundaries in the gaps between headers.
    starts = []
    for i, match in weeks:
        gap = re.match(r"\s{3,}(?=\S)", lines[i][match.end():])
        if gap:
            starts.append(match.end() + gap.end())
    if not starts:
        return text, []
    left = min(starts)
    middle = (headers[0].end() + headers[1].start()) // 2
    notes = re.search(r"important\s+dates", lines[header_index], re.IGNORECASE)
    right = (headers[1].end() + notes.start()) // 2 if notes else None
    if left >= middle:
        return text, []

    consumed = {header_index}
    drafts: list[_Draft] = []
    for number, (start, match) in enumerate(weeks):
        end = weeks[number + 1][0] if number + 1 < len(weeks) else len(lines)
        block = []
        for i in range(start, end):
            line = lines[i]
            # A left-aligned sentence after the last row is outside the table.
            label = line[:left].strip()
            if i > start and label and len(line.lstrip()) > len(label) and not re.match(
                r"^[A-Za-z]{2,9}\s+\d", label
            ):
                break
            if i > start and line and not line.startswith(' ') and not re.match(
                r"^[A-Za-z]{2,9}\s+\d{1,2}\s*[-–]", label
            ):
                break
            consumed.add(i)
            block.append(line)
        week = f"Week {match.group(1)}"
        range_label = ' '.join(line[:left].strip() for line in block[1:] if line[:left].strip())
        # Correct common month typos only inside the week-label column.
        normalized_range = re.sub(r"\bAgu\b", "Aug", range_label, flags=re.I)
        normalized_range = re.sub(r"\bNo(?=\s+\d)", "Nov", normalized_range, flags=re.I)
        dates = _find_explicit_dates(normalized_range, reference)
        session_dates = sorted(dates[0].anchor + timedelta(days=(day - dates[0].anchor.weekday()) % 7)
                               for day in class_days) if dates and class_days else []
        for line in block:
            for cell, session in [(line[left:middle].strip(), 'first class'),
                                  (line[middle:right].strip(), 'second class')]:
                if not cell or _TEACHING_CELL_RE.search(cell) or _SKIP_LINE_RE.search(cell):
                    continue
                final_period = bool(re.fullmatch(r"final\s+exams?", cell, re.IGNORECASE))
                cell = re.sub(r"\bFinal Exams\b", "Final Exam", cell, flags=re.IGNORECASE)
                cell_drafts = _parse_line(cell, reference, _Context())
                for draft in cell_drafts:
                    if draft.task_type == 'project' and any(d.title.lower() == 'final' for d in cell_drafts):
                        draft.title = cell.strip()
                    if draft.title.lower() == 'final' and any(d.task_type == 'project' for d in cell_drafts):
                        continue
                    if draft.due_date is None and session_dates and not final_period:
                        draft.due_date = session_dates[0 if session == 'first class' else 1]
                        draft.confidence = 0.85
                    location = week if final_period else f"{week}, {session}"
                    if draft.due_date is None:
                        draft.title += f" ({location})"
                    draft.source_line = f"{location} [{range_label}]: {cell}"
                    drafts.append(draft)
    return '\n'.join(line for i, line in enumerate(lines) if i not in consumed), drafts


def _consolidate(drafts: list[_Draft]) -> list[_Draft]:
    """Merge and prune undated drafts.

    Syllabi mention each deliverable twice: once in the grading table
    ("Final Examination  35%", undated) and once in the schedule (dated). The
    undated twin's weight/points move onto the dated item and the twin is
    dropped. Remaining undated drafts are kept only if they look like a title:
    not a bare keyword heading ("Homework") and not a sentence fragment.
    """
    dated: dict[str, _Draft] = {}
    for draft in drafts:
        if draft.due_date is not None:
            dated.setdefault(_title_key(draft.title), draft)

    # (type, date, time) slots held by a title-like item, so a sentence-style
    # duplicate of the same item can be dropped.
    short_slots = {
        (d.task_type, d.due_date, d.due_time)
        for d in drafts
        if d.due_date is not None and not _reads_like_sentence(d.title)
    }

    kept: list[_Draft] = []
    for draft in drafts:
        if draft.due_date is None:
            twin = dated.get(_title_key(draft.title))
            if twin is not None:
                twin.weight_percent = twin.weight_percent if twin.weight_percent is not None else draft.weight_percent
                twin.points = twin.points if twin.points is not None else draft.points
                continue
            if _TASK_RE.fullmatch(draft.title) or len(draft.title.split()) > _MAX_UNDATED_TITLE_WORDS:
                continue
        elif _reads_like_sentence(draft.title) and (draft.task_type, draft.due_date, draft.due_time) in short_slots:
            continue
        kept.append(draft)
    return kept


def _reads_like_sentence(title: str) -> bool:
    return len(title.split()) > _MAX_TITLE_WORDS_BEFORE_SENTENCE or bool(_SENTENCE_VERB_RE.search(title))


def _title_key(title: str) -> str:
    return " ".join(title.lower().split())


def compute_priority(task_type: str, weight_percent: float | None, points: int | None) -> str:
    """Importance of a task, independent of how soon it is due."""
    if task_type in {"exam", "midterm"} or (weight_percent or 0) >= 15 or (points or 0) >= 100:
        return "high"
    if (
        task_type in {"project", "presentation", "essay"}
        or (weight_percent or 0) >= 5
        or (points or 0) >= 50
    ):
        return "medium"
    return "low"


def detect_course_code(text: str) -> str | None:
    """Return the first course code such as 'CSC 4330' found in the text."""
    for match in _COURSE_CODE_RE.finditer(text):
        dept = match.group("dept")
        if dept in _COURSE_CODE_EXCLUDE:
            continue
        return f"{dept} {match.group('num')}"
    return None


# ---------------------------------------------------------------------------
# Line parsing
# ---------------------------------------------------------------------------


def _parse_line(line: str, reference: date, context: _Context) -> list[_Draft]:
    explicit = _find_explicit_dates(line, reference)
    anchor = explicit[0].anchor if explicit else (context.anchor or reference)
    dates = sorted(explicit + _find_relative_dates(line, reference, anchor, explicit), key=lambda h: h.start)
    times = _find_times(line, dates)
    measures = _find_measures(line)
    spans = [(h.start, h.end) for h in (*dates, *times, *measures)]
    matches = _merge_compound_keywords(
        line, [m for m in _TASK_RE.finditer(line) if not _is_announcement(line, m)], spans
    )

    drafts: list[_Draft] = []
    if matches:
        drafts = _build_drafts(line, matches, dates, times, measures, context)

    if explicit:
        context.due = explicit[0].value
        # Only header rows ("Week 5 (Sept 21)") anchor weekdays on later lines;
        # a dated task line says nothing about when "due Tuesday" falls.
        if not matches:
            context.anchor = explicit[0].anchor
    return drafts


def _merge_compound_keywords(
    line: str, matches: list[re.Match[str]], spans: list[tuple[int, int]]
) -> list[re.Match[str]]:
    """Treat "Final Project presentation" or "Lab Report Quiz" as one task.

    A keyword joins the previous task's title when only plain words separate
    them: no punctuation, conjunction, "due", or date/time/weight in between.
    """
    kept: list[re.Match[str]] = []
    for match in matches:
        if kept:
            gap_start, gap_end = kept[-1].end(), match.start()
            gap = line[gap_start:gap_end]
            joined = (
                len(gap.split()) <= 3
                and not _COMPOUND_BREAK_RE.search(gap)
                and not any(gap_start < end and start < gap_end for start, end in spans)
            )
            if joined:
                continue
        kept.append(match)
    return kept


def _build_drafts(
    line: str,
    matches: list[re.Match[str]],
    dates: list[_DateHit],
    times: list[_TimeHit],
    measures: list[_MeasureHit],
    context: _Context,
) -> list[_Draft]:
    spans = [(h.start, h.end) for h in dates] + [(h.start, h.end) for h in times]
    spans += [(h.start, h.end) for h in measures]
    leading = bool(dates) and dates[0].start < matches[0].start()
    single = len(matches) == 1

    # Each task's title may start a few words before its keyword ("Group Project").
    prefixes: list[tuple[str, int]] = []
    for i, match in enumerate(matches):
        floor = matches[i - 1].end() if i else 0
        floor = max([floor] + [end for _, end in spans if floor < end <= match.start()])
        prefixes.append(_title_prefix(line, floor, match.start()))

    drafts: list[_Draft] = []
    for i, match in enumerate(matches):
        kw_start, kw_end = match.start(), match.end()
        seg_end = prefixes[i + 1][1] if i + 1 < len(matches) else len(line)
        prev_start = matches[i - 1].end() if i else 0

        title = _build_title(line, prefixes[i][0], kw_start, kw_end, seg_end, spans)
        weight = _pick_measure(measures, "percent", kw_start, seg_end, single)
        points = _pick_measure(measures, "points", kw_start, seg_end, single)

        hit, source = _pick_date(line, dates, kw_start, seg_end, prev_start, leading)
        confidence = {"due": 1.0, "primary": 1.0, "secondary": 0.9, "line": 0.85}.get(source, 0.3)
        due_date = hit.value if hit else None
        if hit and hit.relative:
            confidence -= 0.2
        if hit is None and context.due is not None and _may_inherit_context(line, measures, title, match):
            due_date, confidence = context.due, 0.7

        due_time = _pick_time(times, kw_start, seg_end, prev_start, leading, single)
        drafts.append(
            _Draft(
                title=title,
                task_type=_task_type(match.group("kw")),
                due_date=due_date,
                due_time=due_time,
                weight_percent=weight,
                points=int(points) if points is not None else None,
                confidence=confidence,
                source_line=line,
            )
        )
    return drafts


def _is_announcement(line: str, match: re.Match[str]) -> bool:
    """True when a keyword match is not a deliverable (announcement, category, prose)."""
    keyword = " ".join(match.group("kw").lower().split())
    # Deliverables are singular ("Quiz 3"); "Quizzes" / "Labs" name categories.
    if keyword.endswith("s") and keyword != "hw":
        return True
    if keyword == "final" and not _BARE_FINAL_OK_RE.match(line, match.end()):
        return True
    after = match.end()
    if _SKIP_AFTER_RE.match(line, after) or _PROSE_AFTER_RE.match(line, after):
        return True
    if _PROSE_LIST_AFTER_RE.match(line, after):
        return True
    return bool(_SKIP_BEFORE_RE.search(line[: match.start()]))


def _is_bare_keyword(title: str, match: re.Match[str]) -> bool:
    return " ".join(title.lower().split()) == " ".join(match.group("kw").lower().split())


def _may_inherit_context(
    line: str, measures: list[_MeasureHit], title: str, match: re.Match[str]
) -> bool:
    """Whether an undated task may take the date of the schedule row above it.

    Only short schedule lines ("Lab 5", "Discussion post") qualify: not
    sentences, not grading-table rows (they carry a weight), and not a bare
    keyword that's really a section heading ("Homework").
    """
    return (
        len(line.split()) <= _MAX_CONTEXT_LINE_WORDS
        and not measures
        and not _is_bare_keyword(title, match)
    )


# ---------------------------------------------------------------------------
# Date / time / weight extraction
# ---------------------------------------------------------------------------


def _find_explicit_dates(line: str, reference: date) -> list[_DateHit]:
    hits: list[_DateHit] = []
    for regex in (_ISO_DATE_RE, _NUMERIC_DATE_RE, _MONTH_DATE_RE):
        for m in regex.finditer(line):
            value = _date_from_match(m, reference)
            if value is None or _overlaps(m.start(), m.end(), hits):
                continue
            hits.append(_DateHit(m.start(), m.end(), value, value, relative=False))
    hits.sort(key=lambda h: h.start)

    merged: list[_DateHit] = []
    for hit in hits:
        if merged and _RANGE_JOIN_RE.fullmatch(line[merged[-1].end : hit.start]):
            first = merged.pop()
            merged.append(_DateHit(first.start, hit.end, hit.value, first.anchor, relative=False))
        else:
            merged.append(hit)
    return merged


def _find_relative_dates(
    line: str, reference: date, anchor: date, explicit: list[_DateHit]
) -> list[_DateHit]:
    hits: list[_DateHit] = []
    for m in _WEEKDAY_RE.finditer(line):
        if _overlaps(m.start(), m.end(), explicit):
            continue
        target = _WEEKDAYS[m.group("day")[:3].lower()]
        value = anchor + timedelta(days=(target - anchor.weekday()) % 7)
        if (m.group("mod") or "").lower() == "next":
            value += timedelta(days=7)
        hits.append(_DateHit(m.start(), m.end(), value, value, relative=True))
    for m in _RELATIVE_DAY_RE.finditer(line):
        value = reference + timedelta(days=1 if m.group("word").lower() == "tomorrow" else 0)
        hits.append(_DateHit(m.start(), m.end(), value, value, relative=True))
    return hits


def _find_times(line: str, dates: list[_DateHit]) -> list[_TimeHit]:
    hits: list[_TimeHit] = []
    for m in _TIME_12H_RE.finditer(line):
        hour = int(m.group("hour")) % 12 + (12 if m.group("meridiem").lower() == "p" else 0)
        hits.append(_TimeHit(m.start(), m.end(), time(hour, int(m.group("minute") or 0))))
    for m in _TIME_24H_RE.finditer(line):
        if not _overlaps(m.start(), m.end(), hits):
            hits.append(_TimeHit(m.start(), m.end(), time(int(m.group("hour")), int(m.group("minute")))))
    for m in _NAMED_TIME_RE.finditer(line):
        value = time(12, 0) if m.group("name").lower() == "noon" else time(23, 59)
        hits.append(_TimeHit(m.start(), m.end(), value))
    hits = [h for h in hits if not _overlaps(h.start, h.end, dates)]
    return sorted(hits, key=lambda h: h.start)


def _find_measures(line: str) -> list[_MeasureHit]:
    hits: list[_MeasureHit] = []
    for m in _PERCENT_RE.finditer(line):
        value = float(m.group("value"))
        if 0 < value <= 100:
            hits.append(_MeasureHit(m.start(), m.end(), "percent", value))
    for m in _POINTS_RE.finditer(line):
        hits.append(_MeasureHit(m.start(), m.end(), "points", float(m.group("value"))))
    return sorted(hits, key=lambda h: h.start)


def _pick_date(
    line: str,
    dates: list[_DateHit],
    kw_start: int,
    seg_end: int,
    prev_start: int,
    leading: bool,
) -> tuple[_DateHit | None, str]:
    """Choose the date that belongs to the task whose keyword starts at kw_start.

    "Leading" lines put the date first ("9/12 Quiz 1, 9/14 HW 2"), so a task
    owns the closest date before it. "Trailing" lines put it after
    ("Quiz 2 due 9/12; HW 3 due 9/14"), so a task owns the first date in its
    own segment. An explicit "due <date>" inside the segment always wins.
    """
    in_seg = [h for h in dates if kw_start <= h.start < seg_end]
    in_prev = [h for h in dates if prev_start <= h.start and h.end <= kw_start]

    for hit in in_seg:
        if _DUE_PREFIX_RE.search(line[max(0, hit.start - 24) : hit.start]):
            return hit, "due"

    def best(candidates: list[_DateHit], closest_last: bool) -> _DateHit | None:
        pool = [h for h in candidates if not h.relative] or candidates
        if not pool:
            return None
        return pool[-1] if closest_last else pool[0]

    primary = best(in_prev, True) if leading else best(in_seg, False)
    if primary:
        return primary, "primary"
    secondary = best(in_seg, False) if leading else best(in_prev, True)
    if secondary:
        return secondary, "secondary"
    if dates:
        pool = [h for h in dates if not h.relative] or dates
        return min(pool, key=lambda h: abs(h.start - kw_start)), "line"
    return None, "none"


def _pick_time(
    times: list[_TimeHit],
    kw_start: int,
    seg_end: int,
    prev_start: int,
    leading: bool,
    single: bool,
) -> time | None:
    in_seg = [h for h in times if kw_start <= h.start < seg_end]
    if in_seg:
        return in_seg[0].value
    if leading:
        in_prev = [h for h in times if prev_start <= h.start < kw_start]
        if in_prev:
            return in_prev[-1].value
    if single and times:
        return times[0].value
    return None


def _pick_measure(
    measures: list[_MeasureHit], kind: str, kw_start: int, seg_end: int, single: bool
) -> float | None:
    of_kind = [h for h in measures if h.kind == kind]
    in_seg = [h for h in of_kind if kw_start <= h.start < seg_end]
    if in_seg:
        return in_seg[0].value
    if single and of_kind:
        return of_kind[0].value
    return None


# ---------------------------------------------------------------------------
# Titles
# ---------------------------------------------------------------------------


def _title_prefix(line: str, floor: int, kw_start: int) -> tuple[str, int]:
    """Up to three capitalized words directly before a keyword, e.g. 'Chapter 5' Quiz.

    Returns (prefix_text, start_index_in_line); start is kw_start when empty.
    """
    segment = line[floor:kw_start]
    cut = 0
    for m in _PREFIX_CUT_RE.finditer(segment):
        cut = m.end()

    kept: list[re.Match[str]] = []
    for word in reversed(list(re.finditer(r"\S+", segment[cut:]))):
        if len(kept) == 3 or not _is_prefix_word(word.group()):
            break
        kept.append(word)
    kept.reverse()
    while kept and kept[0].group().isdigit():
        kept.pop(0)

    if not kept:
        return "", kw_start
    return " ".join(w.group() for w in kept), floor + cut + kept[0].start()


def _is_prefix_word(word: str) -> bool:
    lowered = word.lower().rstrip(".")
    if lowered in _PREFIX_BLOCKLIST:
        return False
    if re.fullmatch(_WEEKDAY_PATTERN, lowered) or re.fullmatch(_MONTH_PATTERN, lowered):
        return False
    return bool(_PREFIX_WORD_RE.fullmatch(word))


def _build_title(
    line: str,
    prefix: str,
    kw_start: int,
    kw_end: int,
    seg_end: int,
    spans: list[tuple[int, int]],
) -> str:
    end = seg_end
    stop = _TITLE_STOP_RE.search(line, kw_end, seg_end)
    if stop:
        end = stop.start()
    for start, _ in spans:
        if kw_end <= start < end:
            end = start

    body = _TRAILING_JUNK_RE.sub("", line[kw_start:end]).strip()
    title = " ".join(f"{prefix} {body}".split())
    if title and title[0].islower():
        title = title[0].upper() + title[1:]
    return title[:120]


def _task_type(keyword: str) -> str:
    kw = " ".join(keyword.lower().split())
    if kw.startswith("final project"):
        return "project"
    if kw.startswith("final presentation"):
        return "presentation"
    if kw.startswith(("final report", "final paper")):
        return "assignment"
    if kw.startswith("midterm"):
        return "midterm"
    if kw.startswith(("final", "exam")):
        return "exam"
    if kw == "hw" or kw.startswith("homework"):
        return "homework"
    for prefix in ("quiz", "project", "lab", "discussion", "essay", "assignment", "presentation"):
        if kw.startswith(prefix):
            return prefix
    return "other"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _date_from_match(match: re.Match[str], reference: date) -> date | None:
    raw_month = match.group("month")
    month = int(raw_month) if raw_month.isdigit() else _MONTHS[raw_month[:3].lower()]
    day = int(match.group("day"))
    raw_year = match.group("year")
    if raw_year is None:
        return _nearest_occurrence(month, day, reference)
    year = int(raw_year) + (2000 if len(raw_year) == 2 else 0)
    try:
        return date(year, month, day)
    except ValueError:
        return None


def _nearest_occurrence(month: int, day: int, reference: date) -> date | None:
    candidates: list[date] = []
    for year in (reference.year - 1, reference.year, reference.year + 1):
        try:
            candidates.append(date(year, month, day))
        except ValueError:
            continue
    if not candidates:
        return None
    # Closest to the reference date; ties go to the future occurrence.
    return min(candidates, key=lambda d: (abs((d - reference).days), d < reference))


def _overlaps(start: int, end: int, hits: list) -> bool:
    return any(start < h.end and h.start < end for h in hits)


def _parse_hhmm(value: str) -> time:
    hour, minute = value.split(":")
    return time(int(hour), int(minute))


def _normalize_course_code(code: str | None) -> str | None:
    if not code or not code.strip():
        return None
    return " ".join(code.upper().split())


def _task_id(course_code: str | None, title: str, due: date | None) -> str:
    key = f"{course_code or ''}|{title.lower()}|{due.isoformat() if due else ''}"
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
