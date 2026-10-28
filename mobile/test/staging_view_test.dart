import 'package:due_today/models/assignment.dart';
import 'package:due_today/services/api_service.dart';
import 'package:due_today/services/storage_service.dart';
import 'package:due_today/state/assignment_store.dart';
import 'package:due_today/theme/app_theme.dart';
import 'package:due_today/views/staging_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mid-semester: Tuesday Oct 27, 2026, 3 PM.
final _now = DateTime(2026, 10, 27, 15);

Assignment _item(String title, DateTime? due) =>
    Assignment(id: title, courseCode: 'CSC 3730', title: title, dueAt: due);

/// A tall phone-sized screen, so every review card is built.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 2.4;
  addTearDown(tester.view.reset);
}

Future<(Widget, AssignmentStore)> _staging(List<Assignment> items) async {
  SharedPreferences.setMockInitialValues({});
  final store = AssignmentStore(await StorageService.create(), clock: () => _now);
  final result = ParseResult(courseCode: 'CSC 3730', assignments: items, warnings: const []);
  final app = ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: StagingView(result: result)),
  );
  return (app, store);
}

void main() {
  final semester = [
    _item('Quiz 1', DateTime(2026, 9, 8, 23, 59)),
    _item('HW 2', DateTime(2026, 9, 27, 23, 59)),
    _item('Midterm Examination', DateTime(2026, 10, 15, 9)),
    _item('Quiz 4', DateTime(2026, 10, 29, 23, 59)),
    _item('Final Examination', DateTime(2026, 12, 7, 23, 59)),
    _item('Group Project', null),
  ];

  testWidgets('past items are left out by default', (tester) async {
    _usePhoneScreen(tester);
    final (app, store) = await _staging(semester);
    await tester.pumpWidget(app);

    expect(find.text('3 Assignments Detected'), findsOneWidget);
    expect(find.text('3 items are already past due'), findsOneWidget);
    expect(find.text('Quiz 1'), findsNothing);
    expect(find.text('Quiz 4'), findsOneWidget);
    expect(find.text('Group Project'), findsOneWidget); // undated items always stay

    await tester.tap(find.text('Confirm & Add All (3)'));
    await tester.pumpAndSettle();
    expect(store.assignments.map((a) => a.title), unorderedEquals(['Quiz 4', 'Final Examination', 'Group Project']));
  });

  testWidgets('the switch brings past items back, marked Past due', (tester) async {
    _usePhoneScreen(tester);
    final (app, store) = await _staging(semester);
    await tester.pumpWidget(app);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('6 Assignments Detected'), findsOneWidget);
    expect(find.text('They will be saved and show up as Overdue.'), findsOneWidget);
    expect(find.text('Quiz 1'), findsOneWidget);
    expect(find.text('PAST DUE'), findsNWidgets(3));

    await tester.tap(find.text('Confirm & Add All (6)'));
    await tester.pumpAndSettle();
    expect(store.assignments, hasLength(6));
  });

  testWidgets('something due later today is not past', (tester) async {
    _usePhoneScreen(tester);
    final (app, _) = await _staging([_item('Lab 5', DateTime(2026, 10, 27, 23, 59))]);
    await tester.pumpWidget(app);
    expect(find.textContaining('past due'), findsNothing);
    expect(find.text('1 Assignment Detected'), findsOneWidget);
  });

  testWidgets('an all-past syllabus is included by default', (tester) async {
    _usePhoneScreen(tester);
    final (app, _) = await _staging([
      _item('Quiz 1', DateTime(2026, 9, 8)),
      _item('Midterm Exam', DateTime(2026, 10, 15)),
    ]);
    await tester.pumpWidget(app);
    expect(find.text('2 Assignments Detected'), findsOneWidget);
    expect(find.text('2 items are already past due'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
  });
}
