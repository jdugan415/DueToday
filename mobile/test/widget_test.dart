import 'package:due_today/main.dart';
import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/course.dart';
import 'package:due_today/services/api_service.dart';
import 'package:due_today/services/storage_service.dart';
import 'package:due_today/state/assignment_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AssignmentStore> _store(DateTime now) async {
  SharedPreferences.setMockInitialValues({});
  final store = AssignmentStore(await StorageService.create(), clock: () => now);
  await store.load();
  return store;
}

ApiService _offlineApi() =>
    ApiService(baseUrl: 'http://test', client: MockClient((_) async => http.Response('', 503)));

void main() {
  final now = DateTime(2026, 9, 1, 9);

  testWidgets('shows the empty state on first launch', (tester) async {
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: _offlineApi()));

    expect(find.text('DueToday'), findsOneWidget);
    expect(find.text('No assignments yet'), findsOneWidget);
    expect(find.text('Add syllabus'), findsOneWidget);
  });

  testWidgets('lists saved assignments under Due Today and completes them', (tester) async {
    final store = await _store(now);
    await store.addAll(const Course(code: 'CSC 4330'), [
      Assignment(
        id: 'a1',
        courseCode: 'CSC 4330',
        title: 'Lab 1',
        dueAt: DateTime(2026, 9, 1, 23, 59),
        priority: Priority.high,
      ),
    ]);

    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    expect(find.text('Due Today (1)'), findsOneWidget);
    expect(find.text('Lab 1'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(store.assignments.single.completed, isTrue);
    expect(find.text('Completed (1)'), findsOneWidget);
  });

  testWidgets('opens the paste screen', (tester) async {
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: _offlineApi()));
    await tester.tap(find.text('Add syllabus'));
    await tester.pumpAndSettle();

    expect(find.text('Parse Schedule'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
