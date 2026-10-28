import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/course.dart';
import 'package:due_today/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const courses = [
    Course(code: 'CSC 4330', name: 'Software Systems'),
    Course(code: 'MATH 2057'),
  ];
  final assignments = [
    Assignment(
      id: '1',
      courseCode: 'CSC 4330',
      title: 'Midterm Exam',
      taskType: 'midterm',
      dueAt: DateTime(2026, 9, 28, 23, 59),
      timeSpecified: true,
      weightPercent: 20,
      priority: Priority.high,
    ),
    Assignment(
      id: '2',
      courseCode: 'CSC 4330',
      title: 'HW 1, "warm-up"',
      taskType: 'homework',
      dueAt: DateTime(2026, 9, 4),
      points: 10,
      priority: Priority.low,
      completed: true,
      notes: 'Submit on Moodle\nbefore class',
    ),
    const Assignment(id: '3', courseCode: 'MATH 2057', title: 'Quiz *bonus*', taskType: 'quiz'),
  ];

  test('Markdown groups by course with checklists, soonest first', () {
    final md = ExportService.toMarkdown(courses, assignments, now: DateTime(2026, 10, 27));
    expect(md, '''
# DueToday assignments

_Exported Tue, Oct 27, 2026_

## CSC 4330 · Software Systems

- [x] **HW 1, "warm-up"**: Fri, Sep 4 · 10 pts · Low
  - Submit on Moodle before class
- [ ] **Midterm Exam**: Mon, Sep 28, 11:59 PM · 20% · High

## MATH 2057

- [ ] **Quiz \\*bonus\\***: No due date · Medium
''');
  });

  test('Notion CSV quotes fields per RFC 4180', () {
    final csv = ExportService.toNotionCsv(courses, assignments);
    expect(
      csv,
      'Name,Course,Type,Due,Weight,Points,Priority,Status,Notes\r\n'
      '"HW 1, ""warm-up""",CSC 4330,Homework,2026-09-04,,10,Low,Done,"Submit on Moodle\nbefore class"\r\n'
      'Midterm Exam,CSC 4330,Midterm,2026-09-28 23:59,20,,High,Not started,\r\n'
      'Quiz *bonus*,MATH 2057,Quiz,,,,Medium,Not started,\r\n',
    );
  });

  test('file names carry the date and extension', () {
    expect(ExportService.fileName(ExportFormat.notionCsv, DateTime(2026, 10, 27)), 'duetoday-2026-10-27.csv');
    expect(ExportService.fileName(ExportFormat.markdown, DateTime(2026, 1, 5)), 'duetoday-2026-01-05.md');
  });
}
