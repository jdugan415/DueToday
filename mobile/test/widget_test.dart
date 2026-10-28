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

  Future<AssignmentStore> seeded() async {
    final store = await _store(now);
    await store.addAll(const Course(code: 'CSC 4330'), [
      Assignment(id: 'a1', courseCode: 'CSC 4330', title: 'Lab 1', dueAt: DateTime(2026, 9, 1, 23, 59)),
      Assignment(id: 'a2', courseCode: 'CSC 4330', title: 'Quiz 2', dueAt: DateTime(2026, 9, 3, 23, 59)),
    ]);
    await store.addAll(const Course(code: 'MATH 2057'), [
      Assignment(id: 'm1', courseCode: 'MATH 2057', title: 'Problem Set 1', dueAt: DateTime(2026, 9, 4)),
    ]);
    return store;
  }

  testWidgets('swipe right completes, Undo restores', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    await tester.drag(find.text('Lab 1'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(store.assignments.firstWhere((a) => a.id == 'a1').completed, isTrue);
    expect(find.text('Completed "Lab 1"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.assignments.firstWhere((a) => a.id == 'a1').completed, isFalse);
  });

  testWidgets('swipe left deletes, Undo restores', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    await tester.drag(find.text('Quiz 2'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(store.assignments.any((a) => a.id == 'a2'), isFalse);
    expect(find.text('Quiz 2'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz 2'), findsOneWidget);
  });

  testWidgets('tapping a card opens the editor and saves changes', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    await tester.tap(find.text('Lab 1'));
    await tester.pumpAndSettle();
    expect(find.text('Edit assignment'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Lab 1: Git basics');
    await tester.tap(find.text('High'));
    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Bring laptop');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = store.assignments.firstWhere((a) => a.id == 'a1');
    expect(saved.title, 'Lab 1: Git basics');
    expect(saved.priority, Priority.high);
    expect(saved.notes, 'Bring laptop');
    expect(find.text('Lab 1: Git basics'), findsOneWidget);
  });

  testWidgets('course chips filter the dashboard', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));
    expect(find.text('Problem Set 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'CSC 4330'));
    await tester.pumpAndSettle();
    expect(find.text('Problem Set 1'), findsNothing);
    expect(find.text('Lab 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.text('Problem Set 1'), findsOneWidget);
  });

  testWidgets('course sheet renames and deletes a course', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    await tester.longPress(find.widgetWithText(ChoiceChip, 'MATH 2057'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Course name'), 'Calculus III');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.courseFor('MATH 2057')!.name, 'Calculus III');

    await tester.longPress(find.widgetWithText(ChoiceChip, 'MATH 2057'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete course'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.courseFor('MATH 2057'), isNull);
    expect(store.assignments.any((a) => a.courseCode == 'MATH 2057'), isFalse);
  });

  testWidgets('opens the paste screen', (tester) async {
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: _offlineApi()));
    await tester.tap(find.text('Add syllabus'));
    await tester.pumpAndSettle();

    expect(find.text('Parse Schedule'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
