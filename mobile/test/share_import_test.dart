import 'dart:convert';

import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/course.dart';
import 'package:due_today/services/api_service.dart';
import 'package:due_today/services/storage_service.dart';
import 'package:due_today/state/assignment_store.dart';
import 'package:due_today/theme/app_theme.dart';
import 'package:due_today/widgets/share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AssignmentStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AssignmentStore(await StorageService.create());
  await store.load();
  return store;
}

ApiService _api(Object? body, {int status = 200}) => ApiService(
      baseUrl: 'http://test',
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
    );

Map<String, dynamic> _sharedCourse(List<Map<String, dynamic>> tasks) => {
      'share_code': 'H4PSD',
      'course_code': 'CSC 3380',
      'course_name': 'Object-Oriented Design',
      'created_at': '2026-11-01T12:00:00Z',
      'tasks': tasks,
    };

void main() {
  group('time_specified survives sharing', () {
    test('is sent with each shared task', () {
      final json = Assignment(
        id: '1',
        courseCode: 'CSC 3380',
        title: 'HW 1',
        dueAt: DateTime(2026, 9, 4, 23, 59),
      ).toTaskInJson();
      expect(json['time_specified'], isFalse);
    });

    test('is read back, and defaults to true for courses shared before the flag', () {
      Assignment read(Map<String, dynamic> extra) => Assignment.fromSharedJson(
            {'id': 1, 'title': 'HW 1', 'due_datetime': '2026-09-04T23:59:00', ...extra},
            courseCode: 'CSC 3380',
            shareCode: 'H4PSD',
          );
      expect(read({'time_specified': false}).timeSpecified, isFalse);
      expect(read({'time_specified': true}).timeSpecified, isTrue);
      expect(read({}).timeSpecified, isTrue);
    });
  });

  group('AssignmentStore.importShared', () {
    final parsed = Assignment(
      id: 'f305cf8b3c03',
      courseCode: 'CSC 3380',
      title: 'Midterm  Exam',
      dueAt: DateTime(2026, 10, 7, 23, 59),
      completed: true,
    );

    test('skips items the student already parsed, keeping their state', () async {
      final store = await _store();
      await store.addAll(const Course(code: 'CSC 3380'), [parsed]);

      final added = await store.importShared(const Course(code: 'CSC 3380', shareCode: 'H4PSD'), [
        Assignment(id: 'shared-H4PSD-1', courseCode: 'X', title: 'midterm exam', dueAt: DateTime(2026, 10, 7, 9)),
        Assignment(id: 'shared-H4PSD-2', courseCode: 'X', title: 'Quiz 1', dueAt: DateTime(2026, 9, 16)),
      ]);

      expect(added, 1);
      expect(store.assignments.map((a) => a.id), ['f305cf8b3c03', 'shared-H4PSD-2']);
      expect(store.assignments.first.completed, isTrue);
      expect(store.assignments.last.courseCode, 'CSC 3380');
    });

    test('importing the same code again, or a re-shared code, adds nothing', () async {
      final store = await _store();
      final first = [Assignment(id: 'shared-H4PSD-2', courseCode: 'CSC 3380', title: 'Quiz 1', dueAt: DateTime(2026, 9, 16))];
      await store.importShared(const Course(code: 'CSC 3380'), first);
      await store.toggleCompleted('shared-H4PSD-2');

      expect(await store.importShared(const Course(code: 'CSC 3380'), first), 0);
      final reshared = [Assignment(id: 'shared-K7Q2M-9', courseCode: 'CSC 3380', title: 'Quiz 1', dueAt: DateTime(2026, 9, 16))];
      expect(await store.importShared(const Course(code: 'CSC 3380'), reshared), 0);

      expect(store.assignments, hasLength(1));
      expect(store.assignments.single.completed, isTrue);
    });

    test('same title in a different course or on another day is still added', () async {
      final store = await _store();
      await store.addAll(const Course(code: 'CSC 3380'), [parsed]);
      final added = await store.importShared(const Course(code: 'CSC 3380'), [
        Assignment(id: 'shared-H4PSD-3', courseCode: 'CSC 3380', title: 'Midterm Exam', dueAt: DateTime(2026, 10, 8)),
      ]);
      final otherCourse = await store.importShared(const Course(code: 'MATH 2057'), [
        Assignment(id: 'shared-ABCDE-1', courseCode: 'MATH 2057', title: 'Midterm Exam', dueAt: DateTime(2026, 10, 7)),
      ]);
      expect(added, 1);
      expect(otherCourse, 1);
    });
  });

  group('ApiService rejects malformed responses as ApiException', () {
    test('importCourse with a wrong-typed field', () async {
      final api = _api({'course_code': 5, 'tasks': []});
      await expectLater(api.importCourse('H4PSD'), throwsA(isA<ApiException>()));
    });

    test('parseSyllabus with a bad date', () async {
      final api = _api({
        'course_code': 'CSC 3380',
        'tasks': [
          {'id': 'a', 'title': 'HW 1', 'due_datetime': 'not a date'},
        ],
        'warnings': [],
      });
      await expectLater(api.parseSyllabus('HW 1 due 9/4'), throwsA(isA<ApiException>()));
    });

    test('shareCourse without a share code', () async {
      final api = _api({'course_code': 'CSC 3380'}, status: 201);
      await expectLater(api.shareCourse(const Course(code: 'CSC 3380'), const []), throwsA(isA<ApiException>()));
    });

    test('parse warnings that are not strings fail up front', () async {
      final api = _api({'course_code': 'CSC 3380', 'tasks': [], 'warnings': [1]});
      await expectLater(api.parseSyllabus('x'), throwsA(isA<ApiException>()));
    });
  });

  group('import dialog', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    });

    Future<AssignmentStore> pumpDialog(WidgetTester tester, ApiService api, {List<Assignment> existing = const []}) async {
      final store = await _store();
      if (existing.isNotEmpty) await store.addAll(const Course(code: 'CSC 3380'), existing);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: store), Provider.value(value: api)],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => ShareDialog.showImport(context), child: const Text('open')),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'H4PSD');
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('says how many items were already on the phone', (tester) async {
      final api = _api(_sharedCourse([
        {'id': 1, 'title': 'Lab 1', 'due_datetime': '2026-11-02T23:59:00', 'time_specified': false},
        {'id': 2, 'title': 'Lab 2', 'due_datetime': '2026-11-09T23:59:00', 'time_specified': false},
      ]));
      final store = await pumpDialog(tester, api, existing: [
        Assignment(id: 'mine', courseCode: 'CSC 3380', title: 'Lab 1', dueAt: DateTime(2026, 11, 2, 23, 59)),
      ]);

      expect(find.text('Imported 1 item for CSC 3380 (1 already on your phone)'), findsOneWidget);
      expect(store.assignments, hasLength(2));
      expect(store.assignments.last.timeSpecified, isFalse);
    });

    testWidgets('a malformed response shows an error instead of spinning forever', (tester) async {
      await pumpDialog(tester, _api({'course_code': 5}));

      expect(find.textContaining('could not read'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Import'), findsOneWidget);
    });
  });
}
