"""Edge-case coverage for the syllabus parser. Run from backend/: pytest -q"""

from datetime import date

import pytest

from app.parser import compute_priority, detect_course_code, parse_syllabus

# Monday, Aug 24 2026: the first week of a fall semester.
REF = date(2026, 8, 24)


def parse(text: str, **kwargs):
    kwargs.setdefault("reference_date", REF)
    return parse_syllabus(text, **kwargs)


def only_task(text: str, **kwargs):
    result = parse(text, **kwargs)
    assert len(result.tasks) == 1, [t.title for t in result.tasks]
    return result.tasks[0]


# ---------------------------------------------------------------------------
# Date formats
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("9/28 Midterm Exam", date(2026, 9, 28)),
        ("Quiz 1 - 09/04", date(2026, 9, 4)),
        ("HW 2 due 10/02/2026", date(2026, 10, 2)),
        ("HW 2 due 10/2/26", date(2026, 10, 2)),
        ("Sept 28: Quiz 2", date(2026, 9, 28)),
        ("Sep. 28 Quiz 2", date(2026, 9, 28)),
        ("October 4th - Project 1 Proposal", date(2026, 10, 4)),
        ("Lab 3 due Nov 1st, 2026", date(2026, 11, 1)),
        ("2026-11-03 Exam 2", date(2026, 11, 3)),
        ("dec 9 final exam", date(2026, 12, 9)),
    ],
)
def test_date_formats(text, expected):
    assert only_task(text).due_date == expected


def test_relative_weekday_with_time():
    task = only_task("Lab 4 — Due Tuesday by 11:59 PM")
    assert task.title == "Lab 4"
    assert task.due_date == date(2026, 8, 25)
    assert task.due_time == "23:59"
    assert task.time_specified is True
    assert task.confidence < 1.0  # relative dates are flagged for review


def test_next_weekday_skips_a_week():
    assert only_task("Discussion post due Friday").due_date == date(2026, 8, 28)
    assert only_task("Discussion post due next Friday").due_date == date(2026, 9, 4)


def test_today_and_tomorrow():
    assert only_task("Quiz tomorrow").due_date == date(2026, 8, 25)
    assert only_task("HW 1 due today").due_date == REF


def test_year_rolls_forward_for_next_spring():
    task = only_task("1/15 Exam 1", reference_date=date(2026, 12, 10))
    assert task.due_date == date(2027, 1, 15)


def test_invalid_dates_are_ignored():
    result = parse("13/45 Quiz 3")
    assert result.tasks[0].due_date is None
    assert any("No date found" in w for w in result.warnings)


def test_range_uses_end_date_and_anchors_weekdays():
    task = only_task("Oct 12 – Oct 16: Project 2 due Wednesday")
    assert task.due_date == date(2026, 10, 14)
    assert only_task("Oct 12 - Oct 16: Project 2").due_date == date(2026, 10, 16)


# ---------------------------------------------------------------------------
# Times
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("HW 3 due 10/02 at 5pm", "17:00"),
        ("HW 3 due 10/02 at 5 p.m.", "17:00"),
        ("Quiz 4 9/30 at noon", "12:00"),
        ("Essay due 9/30 at midnight", "23:59"),
        ("Lab 2 due 9/30 14:30", "14:30"),
        ("Lab 2 due 9/30 12:15 AM", "00:15"),
    ],
)
def test_times(text, expected):
    task = only_task(text)
    assert task.due_time == expected
    assert task.time_specified is True


def test_default_time_when_omitted():
    task = only_task("9/30 Quiz 4")
    assert task.due_time == "23:59"
    assert task.time_specified is False
    assert task.due_datetime.isoformat() == "2026-09-30T23:59:00"


def test_custom_default_time():
    assert only_task("9/30 Quiz 4", default_due_time="08:00").due_time == "08:00"


# ---------------------------------------------------------------------------
# Titles and task types
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "title", "task_type"),
    [
        ("9/28 Midterm Exam (20%)", "Midterm Exam", "midterm"),
        ("October 4th - Project 1 Proposal - 50 pts", "Project 1 Proposal", "project"),
        ("Lab 3: Sorting Algorithms due 9/14", "Lab 3: Sorting Algorithms", "lab"),
        ("HW3 due 9/10", "HW3", "homework"),
        ("Homework 5 due 9/10", "Homework 5", "homework"),
        ("Sept 30 Group Project Checkpoint", "Group Project Checkpoint", "project"),
        ("9/5 Chapter 5 Quiz", "Chapter 5 Quiz", "quiz"),
        ("Week 3 Quiz 9/9", "Quiz", "quiz"),
        ("Final Exam - Dec 10, 2026", "Final Exam", "exam"),
        ("Discussion Board Post #2 due 9/3", "Discussion Board Post #2", "discussion"),
        ("Quiz on 9/12", "Quiz", "quiz"),
    ],
)
def test_titles(text, title, task_type):
    task = only_task(text)
    assert task.title == title
    assert task.task_type == task_type


@pytest.mark.parametrize(
    ("text", "title"),
    [
        ("Sept 16      Sorting      Quiz 1 (10 pts)", "Quiz 1"),
        ("Oct 9\tGraph Search\tProject 2 Proposal", "Project 2 Proposal"),
        ("Oct 9   Linked Lists   Lab 3", "Lab 3"),
        ("Sept 16 Sorting Quiz 1", "Sorting Quiz 1"),  # single spaces: still one cell
    ],
)
def test_table_cells_do_not_leak_into_titles(text, title):
    assert only_task(text).title == title


@pytest.mark.parametrize(
    "text",
    [
        "No class - Labor Day 9/7",
        "Exam 1 review session 9/20",
        "HW 4 assigned 9/1",
        "Midterm grades posted 10/10",
        "Study for the midterm 10/1",
        "Labor statistics reading 9/8",
        "Bring a projector adapter 9/8",
        "Fall break Oct 15-16",
    ],
)
def test_non_deliverables_are_skipped(text):
    assert parse(text).tasks == []


@pytest.mark.parametrize(
    "text",
    [
        # Policy prose found in real syllabi: none of these are deliverables.
        "Homework assignments should be submitted through Moodle by the deadline.",
        "The final examination accounts for 35% of the final course grade.",
        "Each homework assignment contributes approximately 2% to the course grade.",
        "Quizzes will assess students' understanding of recently covered material.",
        "Final date to drop courses without receiving a grade of W is Sept 2.",
        "Final course grade will be determined according to the following distribution.",
        "Late work on quiz, laboratory, and exam scores is not accepted after Dec 7.",
        "Group project announced and requirements discussed on Sept 17.",
        "Programming Assignment Policy",
        "Assignment dates and topics may be adjusted as needed.",
        "Labs and quizzes together account for 15%.",
        "Students should consult the University final examination schedule for Dec 7.",
    ],
)
def test_syllabus_prose_is_not_a_task(text):
    assert parse(text).tasks == []


def test_wrapped_prose_verb_is_still_prose():
    # PDF extraction can wrap "accounts / for" onto two lines.
    assert parse("The midterm examination accounts\nfor 25% of the grade.").tasks == []


@pytest.mark.parametrize(
    ("text", "title"),
    [
        ("Dec 9   Final", "Final"),
        ("Final (35%) Dec 9", "Final"),
        ("Dec 9 Final Examination", "Final Examination"),
        ("Dec 1 Final Presentation", "Final Presentation"),
        ("Midterm examination will be held on Oct 15", "Midterm examination will be held"),
    ],
)
def test_real_final_and_midterm_forms_are_kept(text, title):
    assert only_task(text).title == title


def test_grading_table_weight_merges_into_schedule_item():
    text = """Grading
    Group Project        15%
    Midterm Examination  25%
    Final Examination    35%

    Schedule
    Oct 15   Midterm Examination
    Dec 7    Final Examination
    """
    by_title = {t.title: t for t in parse(text).tasks}
    assert by_title["Midterm Examination"].due_date == date(2026, 10, 15)
    assert by_title["Midterm Examination"].weight_percent == 25
    assert by_title["Final Examination"].weight_percent == 35
    # No dated twin: kept undated so the user can set a date in review.
    assert by_title["Group Project"].due_date is None
    assert len(by_title) == 3


def test_sentence_duplicate_of_a_dated_item_is_dropped():
    text = "Oct 15 9:00 AM   Midterm Exam   25%\nThe midterm exam will be held on Oct 15 at 9:00 AM in Room 1200."
    assert [t.title for t in parse(text).tasks] == ["Midterm Exam"]


def test_headings_and_long_lines_do_not_inherit_dates():
    text = "Dec 7   Final Exam\nHomework\nProject using a real-world dataset to apply clustering methods\nLab 6"
    by_title = {t.title: t.due_date for t in parse(text).tasks}
    assert by_title == {"Final Exam": date(2026, 12, 7), "Lab 6": date(2026, 12, 7)}


def test_empty_result_warns():
    result = parse("Welcome to the course! Read chapter 1.")
    assert result.tasks == []
    assert result.warnings


# ---------------------------------------------------------------------------
# Multiple tasks on one line
# ---------------------------------------------------------------------------


def test_shared_leading_date():
    result = parse("9/12 Quiz 1 and HW 2")
    assert [(t.title, t.due_date) for t in result.tasks] == [
        ("HW 2", date(2026, 9, 12)),
        ("Quiz 1", date(2026, 9, 12)),
    ]


def test_each_task_owns_preceding_date():
    result = parse("9/12 Quiz 1, 9/14 HW 2")
    assert [(t.title, t.due_date) for t in result.tasks] == [
        ("Quiz 1", date(2026, 9, 12)),
        ("HW 2", date(2026, 9, 14)),
    ]


def test_each_task_owns_trailing_due_date():
    result = parse("Quiz 2 due 9/12; HW 3 due 9/14")
    assert [(t.title, t.due_date) for t in result.tasks] == [
        ("Quiz 2", date(2026, 9, 12)),
        ("HW 3", date(2026, 9, 14)),
    ]


def test_line_date_anchors_weekday_in_same_line():
    result = parse("Mon 9/14: Lab 2 in class, HW 2 due Fri")
    by_title = {t.title: t.due_date for t in result.tasks}
    assert by_title == {"Lab 2 in class": date(2026, 9, 14), "HW 2": date(2026, 9, 18)}


# ---------------------------------------------------------------------------
# Weights, points and priority
# ---------------------------------------------------------------------------


def test_weight_percent():
    task = only_task("9/28 Midterm Exam (20%)")
    assert task.weight_percent == 20
    assert task.priority == "high"


def test_decimal_weight_and_points():
    assert only_task("Final Exam 12/10 25.5%").weight_percent == 25.5
    task = only_task("Quiz 3 (10 pts) 9/18")
    assert task.points == 10
    assert task.priority == "low"


def test_weights_stay_with_their_task():
    result = parse("9/12 Quiz 1 (5%), Project 1 (15%) due 9/20")
    by_title = {t.title: t.weight_percent for t in result.tasks}
    assert by_title == {"Quiz 1": 5, "Project 1": 15}


@pytest.mark.parametrize(
    ("task_type", "weight", "points", "expected"),
    [
        ("exam", None, None, "high"),
        ("homework", 15, None, "high"),
        ("lab", None, 100, "high"),
        ("project", None, None, "medium"),
        ("quiz", 5, None, "medium"),
        ("homework", 2, 10, "low"),
    ],
)
def test_priority(task_type, weight, points, expected):
    assert compute_priority(task_type, weight, points) == expected


# ---------------------------------------------------------------------------
# Whole-document behaviour
# ---------------------------------------------------------------------------


def test_context_date_from_week_header():
    text = "Week 5 (Sept 21)\n  - Discussion post due Friday\n  - Lab 5\n"
    result = parse(text)
    by_title = {t.title: t for t in result.tasks}
    assert by_title["Discussion post"].due_date == date(2026, 9, 25)
    assert by_title["Lab 5"].due_date == date(2026, 9, 21)
    assert by_title["Lab 5"].confidence < 0.8


def test_full_schedule_is_sorted_and_deduplicated():
    text = """CSC 4330 - Software Systems Development
    Tentative Schedule
    1. Aug 26   Intro, syllabus
    2. 9/2      HW 1 due (5%)
    3. 9/7      No class - Labor Day
    4. Sept 16  Quiz 1 (10 pts)
    5. 9/2      HW 1 due (5%)
    6. Oct 7    Midterm Exam (20%)
    7. Dec 9    Final Project presentation (25%)
    Lab 6
    """
    result = parse(text)
    assert result.course_code == "CSC 4330"
    assert [t.title for t in result.tasks] == [
        "HW 1",
        "Quiz 1",
        "Midterm Exam",
        "Final Project presentation",
        "Lab 6",
    ]
    assert result.tasks[-1].due_date == date(2026, 12, 9)  # inherits the last schedule date


def test_explicit_course_code_wins():
    assert parse("CSC 4330\n9/2 HW 1", course_code="math 1550").course_code == "MATH 1550"


def test_course_code_detection():
    assert detect_course_code("Welcome to CSC-4330!") == "CSC 4330"
    assert detect_course_code("HW 1234 and OCT 2026") is None


def test_ids_are_stable():
    first = parse("9/28 Midterm Exam", course_code="CSC 4330").tasks[0].id
    second = parse("9/28 Midterm Exam", course_code="CSC 4330").tasks[0].id
    assert first == second and len(first) == 12
