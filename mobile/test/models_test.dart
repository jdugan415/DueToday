import 'dart:convert';

import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/dashboard_buckets.dart';
import 'package:due_today/models/share_code.dart';
import 'package:due_today/services/api_service.dart';
import 'package:due_today/services/calendar_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Assignment _assignment(String id, {DateTime? dueAt, bool completed = false, Priority? priority}) =>
    Assignment(
      id: id,
      courseCode: 'CSC 4330',
      title: 'Task $id',
      dueAt: dueAt,
      completed: completed,
      priority: priority ?? Priority.medium,
    );

void main() {
  group('Assignment JSON', () {
    test('parses a POST /api/parse task', () {
      final a = Assignment.fromParsedJson({
        'id': 'abc123',
        'title': 'Midterm Exam',
        'task_type': 'midterm',
        'due_date': '2026-09-28',
        'due_time': '23:59',
        'due_datetime': '2026-09-28T23:59:00',
        'time_specified': false,
        'weight_percent': 20,
        'points': null,
        'priority': 'high',
        'confidence': 0.95,
        'source_line': '9/28 Midterm Exam (20%)',
      }, courseCode: 'CSC 4330');

      expect(a.dueAt, DateTime(2026, 9, 28, 23, 59));
      expect(a.weightPercent, 20.0);
      expect(a.priority, Priority.high);
      expect(a.needsReview, isFalse);
    });

    test('round-trips through local storage JSON', () {
      final original = _assignment('1', dueAt: DateTime(2026, 10, 2, 17)).copyWith(completed: true);
      final restored = Assignment.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.id, original.id);
      expect(restored.dueAt, original.dueAt);
      expect(restored.completed, isTrue);
    });

    test('serializes due dates without a UTC offset for the API', () {
      final json = _assignment('1', dueAt: DateTime(2026, 10, 2, 17, 5)).toTaskInJson();
      expect(json['due_datetime'], '2026-10-02T17:05:00');
    });

    test('flags undated and low-confidence items for review', () {
      expect(_assignment('1').needsReview, isTrue);
      expect(
        _assignment('2', dueAt: DateTime(2026)).copyWith(confidence: 0.5).needsReview,
        isTrue,
      );
    });
  });

  group('DashboardBuckets', () {
    final now = DateTime(2026, 9, 1, 15); // Tuesday 3 PM

    test('groups by urgency', () {
      final buckets = DashboardBuckets.from([
        _assignment('overdue', dueAt: DateTime(2026, 9, 1, 9)),
        _assignment('today', dueAt: DateTime(2026, 9, 1, 23, 59)),
        _assignment('week', dueAt: DateTime(2026, 9, 8, 12)),
        _assignment('later', dueAt: DateTime(2026, 9, 9, 0, 1)),
        _assignment('none'),
        _assignment('done', dueAt: DateTime(2026, 9, 1, 23), completed: true),
      ], now);

      expect(buckets.overdue.single.id, 'overdue');
      expect(buckets.dueToday.single.id, 'today');
      expect(buckets.thisWeek.single.id, 'week');
      expect(buckets.later.single.id, 'later');
      expect(buckets.unscheduled.single.id, 'none');
      expect(buckets.completed.single.id, 'done');
    });

    test('sorts by due date, then priority', () {
      final due = DateTime(2026, 9, 3);
      final buckets = DashboardBuckets.from([
        _assignment('low', dueAt: due, priority: Priority.low),
        _assignment('high', dueAt: due, priority: Priority.high),
        _assignment('earlier', dueAt: DateTime(2026, 9, 2)),
      ], now);
      expect(buckets.thisWeek.map((a) => a.id), ['earlier', 'high', 'low']);
    });
  });

  group('ShareCode', () {
    test('accepts 5 unambiguous characters', () {
      expect(ShareCode.isValid('ab2cd'), isTrue);
      expect(ShareCode.isValid('ABCD'), isFalse);
      expect(ShareCode.isValid('ABCD0'), isFalse); // 0 is excluded
      expect(ShareCode.isValid('ABCDI'), isFalse); // I is excluded
    });
  });

  group('CalendarService', () {
    test('builds a pre-filled one-hour event', () {
      final due = DateTime(2026, 9, 28, 23, 59);
      final event = CalendarService.buildEvent(courseCode: 'CSC 4330', title: 'Midterm', dueDate: due);
      expect(event.title, '[CSC 4330] Midterm');
      expect(event.startDate, due);
      expect(event.endDate, due.add(const Duration(hours: 1)));
      expect(event.allDay, isFalse);
    });
  });

  group('ApiService', () {
    test('parseSyllabus sends reference_date and maps tasks', () async {
      late Map<String, dynamic> sent;
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://test/api/parse');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'course_code': 'CSC 4330',
              'reference_date': '2026-08-24',
              'warnings': <String>[],
              'tasks': [
                {
                  'id': 'x1',
                  'title': 'HW 1',
                  'task_type': 'homework',
                  'due_date': '2026-09-04',
                  'due_time': '23:59',
                  'due_datetime': '2026-09-04T23:59:00',
                  'time_specified': true,
                  'priority': 'low',
                  'confidence': 1.0,
                  'source_line': 'HW 1 due 9/4',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.parseSyllabus('HW 1 due 9/4', today: DateTime(2026, 8, 24));
      expect(sent['reference_date'], '2026-08-24');
      expect(result.courseCode, 'CSC 4330');
      expect(result.assignments.single.dueAt, DateTime(2026, 9, 4, 23, 59));
    });

    test('surfaces FastAPI error details', () async {
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('{"detail": "No course found for code ABCDE"}', 404)),
      );
      await expectLater(
        api.importCourse('abcde'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', contains('ABCDE'))),
      );
    });
  });
}
