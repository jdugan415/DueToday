import 'dart:convert';

import 'package:due_today/models/assignment.dart';
import 'package:due_today/services/ics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 1, 9); // Tuesday 9 AM
  final midterm = Assignment(
    id: 'f305cf8b3c03',
    courseCode: 'CSC 4330',
    title: 'Midterm Exam',
    taskType: 'midterm',
    dueAt: DateTime(2026, 9, 28, 23, 59),
    timeSpecified: true,
    weightPercent: 20,
    priority: Priority.high,
    notes: 'Room 110; bring a calculator, pencil',
  );
  final lab = Assignment(
    id: 'shared-H4PSD-7',
    courseCode: 'CSC 4330',
    title: 'Lab 2',
    taskType: 'lab',
    dueAt: DateTime(2026, 9, 3, 17),
    points: 10,
    priority: Priority.low,
  );

  group('eligible', () {
    test('keeps dated, open, upcoming, not-yet-added items, soonest first', () {
      final items = IcsService.eligible([
        midterm,
        lab,
        Assignment(id: 'past', courseCode: 'X', title: 'HW 0', dueAt: DateTime(2026, 8, 30)),
        Assignment(id: 'done', courseCode: 'X', title: 'HW 1', dueAt: DateTime(2026, 9, 5), completed: true),
        Assignment(id: 'added', courseCode: 'X', title: 'HW 2', dueAt: DateTime(2026, 9, 6), addedToCalendar: true),
        const Assignment(id: 'undated', courseCode: 'X', title: 'Final Project'),
      ], now);
      expect(items.map((a) => a.id), ['shared-H4PSD-7', 'f305cf8b3c03']);
    });
  });

  group('build', () {
    final ics = IcsService.build(
      [midterm, lab],
      now: DateTime.utc(2026, 9, 1, 14),
      calendarName: 'DueToday · CSC 4330',
    );
    final unfolded = ics.replaceAll('\r\n ', '');

    test('wraps one VEVENT per dated assignment in a VCALENDAR with CRLF endings', () {
      expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse);
      expect(RegExp('BEGIN:VEVENT').allMatches(ics), hasLength(2));
      expect(ics, contains('X-WR-CALNAME:DueToday · CSC 4330\r\n'));
    });

    test('uses floating local times, a UTC stamp, and a one-hour event', () {
      expect(ics, contains('DTSTAMP:20260901T140000Z\r\n'));
      expect(ics, contains('DTSTART:20260928T235900\r\nDTEND:20260929T005900\r\n'));
      expect(ics, contains('DTSTART:20260903T170000\r\nDTEND:20260903T180000\r\n'));
    });

    test('gives each assignment a stable UID and the [COURSE] Title summary', () {
      expect(ics, contains('UID:assignment-f305cf8b3c03@duetoday\r\n'));
      expect(ics, contains('UID:assignment-shared-H4PSD-7@duetoday\r\n'));
      expect(ics, contains('SUMMARY:[CSC 4330] Midterm Exam\r\n'));
      expect(ics, contains('CATEGORIES:MIDTERM\r\n'));
    });

    test('escapes TEXT values in the description', () {
      expect(
        unfolded,
        contains(r'DESCRIPTION:Type: midterm\nPriority: high\nWeight: 20%\nRoom 110\; bring a calculator\, pencil'
            '\r\n'),
      );
      expect(unfolded, contains(r'DESCRIPTION:Type: lab\nPriority: low\nPoints: 10' '\r\n'));
    });

    test('skips undated assignments', () {
      final only = IcsService.build(
        [const Assignment(id: 'u', courseCode: 'X', title: 'Final Project')],
        now: now,
      );
      expect(only, isNot(contains('BEGIN:VEVENT')));
    });
  });

  test('folds long lines at 75 octets without splitting UTF-8 characters', () {
    final long = Assignment(
      id: 'long',
      courseCode: 'FREN 2101',
      title: 'Rédaction finale — étude détaillée des œuvres de Molière et de Racine 📚',
      dueAt: DateTime(2026, 10, 2, 12),
    );
    final ics = IcsService.build([long], now: now);
    for (final line in ics.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
    }
    expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:[FREN 2101] ${long.title}\r\n'));
  });

  test('file name is dated', () {
    expect(IcsService.fileName(DateTime(2026, 9, 1)), 'duetoday-2026-09-01.ics');
  });
}
