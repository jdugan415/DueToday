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

/// A tall phone-sized screen, so the lazily built dashboard shows every card.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.4;
  addTearDown(tester.view.reset);
}

void main() {
  final now = DateTime(2026, 9, 1, 9); // Tuesday 9 AM

  testWidgets('first launch shows the hero header and the caught-up state', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: _offlineApi()));

    expect(find.text('TUESDAY, SEP 1'), findsOneWidget);
    expect(find.text('My Deadlines'), findsOneWidget);
    expect(find.text('0 Due Today'), findsOneWidget);
    expect(find.text('All caught up!'), findsOneWidget);
    expect(find.text('No upcoming deadlines on your radar'), findsOneWidget);
    expect(find.text('Add Course'), findsNothing);
    expect(find.text('Add syllabus'), findsOneWidget);
  });

  testWidgets('lists saved assignments under Due Today and completes them', (tester) async {
    _usePhoneScreen(tester);
    final store = await _store(now);
    await store.addAll(const Course(code: 'CSC 4330'), [
      Assignment(
        id: 'a1',
        courseCode: 'CSC 4330',
        title: 'Lab 1',
        dueAt: DateTime(2026, 9, 1, 23, 59),
        timeSpecified: true,
        weightPercent: 15,
        priority: Priority.high,
      ),
    ]);

    await tester.pumpWidget(DueTodayApp(store: store, api: _offlineApi()));

    expect(find.text('1 Due Today'), findsOneWidget); // summary pill
    expect(find.text('Due Today'), findsOneWidget); // sticky section header
    expect(find.text('Lab 1'), findsOneWidget);
    expect(find.text('Due in 14h'), findsOneWidget);
    expect(find.text('Tue, Sep 1 · 11:59 PM  ·  15% of grade'), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget); // high priority
    expect(find.text('Add to Calendar'), findsOneWidget);

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

  testWidgets('summary pills and countdown badges reflect urgency', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(DueTodayApp(store: await seeded(), api: _offlineApi()));

    expect(find.text('1 Due Today'), findsOneWidget);
    expect(find.text('2 This Week'), findsOneWidget);
    expect(find.text('Due in 14h'), findsOneWidget); // Lab 1, tonight
    expect(find.text('Thursday'), findsOneWidget); // Quiz 2
    expect(find.text('Friday'), findsOneWidget); // Problem Set 1
  });

  testWidgets('swipe right completes, Undo restores', (tester) async {
    _usePhoneScreen(tester);
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
    _usePhoneScreen(tester);
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
    _usePhoneScreen(tester);
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
    _usePhoneScreen(tester);
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
    _usePhoneScreen(tester);
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

  testWidgets('Add syllabus opens the paste screen', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: _offlineApi()));
    await tester.tap(find.text('Add syllabus'));
    await tester.pumpAndSettle();

    expect(find.text('Parse Schedule'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('import explains share codes and validates input without truncation', (tester) async {
    _usePhoneScreen(tester);
    final requests = <http.Request>[];
    final api = ApiService(baseUrl: 'http://test', client: MockClient((request) async {
      requests.add(request);
      return http.Response('{"detail":"Not found"}', 404);
    }));
    await tester.pumpWidget(DueTodayApp(store: await _store(now), api: api));
    await tester.tap(find.byTooltip('Import shared course'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This is not your school course number'), findsOneWidget);
    final field = find.byType(TextField);
    final button = find.widgetWithText(FilledButton, 'Import');
    for (final code in ['AB', 'ABC234', 'ABCD0', 'ABCDI', 'ABC!2']) {
      await tester.enterText(field, code);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(tester.widget<TextField>(field).decoration!.errorText, isNotNull);
      expect(tester.widget<TextField>(field).controller!.text, code);
    }
    expect(requests, isEmpty);
    await tester.enterText(field, 'ab2cd');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'AB2CD');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/api/courses/AB2CD');
    expect(find.text('No class found with that code.'), findsOneWidget);
    await tester.enterText(field, 'K7Q2M');
    await tester.pumpAndSettle();
    expect(find.text('No class found with that code.'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    _usePhoneScreen(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(DueTodayApp(store: await seeded(), api: _offlineApi()));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(Theme.of(tester.element(find.byWidget(scaffold))).brightness, Brightness.dark);
    expect(find.text('My Deadlines'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
