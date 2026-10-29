"""Synthetic weekly tables; never include a student's actual syllabus."""
from datetime import date

from app.parser import parse_syllabus


def row(week='', first='', second='', notes=''):
    return f'{week:<20}{first:<40}{second:<40}{notes}'


def schedule():
    return '\n'.join([
        'DES 3010',
        row('', '1st Day of the week', '2nd Day of the Week', 'Important Dates'),
        row('WEEK 1', 'Presentation of syllabus', 'Project 7 Lecture'),
        row('Aug 16-22', 'Introduction to project 7'),
        row('WEEK 2', 'Workday', 'Project 7 - Mid Critique'),
        row('Aug 23-29'),
        row('WEEK 3', 'Project 7 - Final Due', 'Project 8 - Introduction', 'Sep 2 | Midterm grades due'),
        row('Aug 30-Sep 5'),
        row('WEEK 4', 'Workday', 'Project 8 - Final', 'September 8 | Fall Holiday'),
        row('Sep 6-12'),
        row('WEEK 5', '', 'Final Exams'),
        row('Sep 13-19'),
        '',
        'September 20 | Final date for dropping courses.',
    ])


def test_weekly_table_keeps_milestones_without_inventing_deadlines():
    result = parse_syllabus(schedule(), reference_date=date(2026, 8, 1))
    assert len(result.tasks) == 4
    titles = {t.title for t in result.tasks}
    assert 'Project 7 - Mid Critique (Week 2, second class)' in titles
    assert 'Project 7 - Final (Week 3, first class)' in titles
    assert 'Project 8 - Final (Week 4, second class)' in titles
    assert 'Final Exam (Week 5)' in titles
    assert all(t.due_date is None and t.confidence < .8 for t in result.tasks)
    assert all('Week' in t.source_line for t in result.tasks)
    assert any('class weekdays' in w for w in result.warnings)


def test_weekly_table_uses_only_dates_inside_assignment_cell():
    text = schedule().replace('Project 7 - Mid Critique', 'Project 7 due Sep 1 at 5pm')
    result = parse_syllabus(text, reference_date=date(2026, 8, 1))
    dated = [t for t in result.tasks if t.due_date]
    assert len(dated) == 1
    assert dated[0].due_date == date(2026, 9, 1)
    assert dated[0].due_time == '17:00'


def test_ordinary_schedule_not_routed_to_weekly_table():
    result = parse_syllabus('Week 2 (Sept 7)\nProject 7 due Friday', reference_date=date(2026, 8, 1))
    assert result.tasks[0].due_date == date(2026, 9, 11)


def test_confirmed_weekdays_resolve_sessions_but_not_exam_week():
    result = parse_syllabus(schedule(), reference_date=date(2026, 8, 1), class_days=[0, 2])
    assert [t.due_date for t in result.tasks] == [date(2026, 8, 26), date(2026, 8, 31), date(2026, 9, 9), None]
    assert not result.needs_class_days
    assert parse_syllabus(schedule(), reference_date=date(2026, 8, 1)).needs_class_days


def test_class_days_validation():
    import pytest
    from pydantic import ValidationError
    from app.models import ParseRequest
    for days in ([0], [0, 0], [-1, 2], [0, 7], [0, 2, 4]):
        with pytest.raises(ValidationError):
            ParseRequest(raw_text='schedule', class_days=days)


def test_explicit_meeting_days_avoid_question():
    result = parse_syllabus('Class days: Mondays and Wednesdays\n' + schedule(), reference_date=date(2026, 8, 1))
    assert not result.needs_class_days
    assert result.tasks[0].due_date == date(2026, 8, 26)


def test_weekly_table_with_different_column_widths():
    text = '\n'.join([
        f"{'':<12}{'First day of the week':<50}{'Second day of the week':<50}Important Dates",
        f"{'Week 1':<12}{'Project 9 Final Due':<50}{'Quiz 2':<50}September 4 Holiday",
        f"{'Aug 23-29':<12}",
    ])
    result = parse_syllabus(text, reference_date=date(2026, 8, 1), class_days=[1, 3])
    assert [(t.task_type, t.due_date) for t in result.tasks] == [('project', date(2026, 8, 25)), ('quiz', date(2026, 8, 27))]
