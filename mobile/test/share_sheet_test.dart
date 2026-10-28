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

void main() {
  late List<String> clipboard;
  late List<String> haptics;

  setUp(() {
    clipboard = [];
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      },
    );
  });

  Future<(AssignmentStore, List<http.Request>)> pumpSheet(WidgetTester tester, {String? existingCode}) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(await StorageService.create());
    const course = Course(code: 'CSC 3380');
    await store.addAll(course, [Assignment(id: 'a', courseCode: 'CSC 3380', title: 'Lab 1', dueAt: DateTime(2026, 11, 2))]);
    if (existingCode != null) await store.setShareCode('CSC 3380', existingCode);

    final requests = <http.Request>[];
    final api = ApiService(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'share_code': 'K7Q2M'}), 201);
      }),
    );
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: store), Provider.value(value: api)],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ShareDialog.showExport(context, store.courseFor('CSC 3380')!),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (store, requests);
  }

  testWidgets('creates a code and shows it in a bottom sheet', (tester) async {
    final (store, requests) = await pumpSheet(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Share CSC 3380'), findsOneWidget);
    expect(find.text('K7Q2M'), findsOneWidget);
    expect(find.text('Tap to copy'), findsOneWidget);
    expect(find.text('Export as .ics Calendar File'), findsOneWidget);
    expect(requests.single.url.path, '/api/courses');
    expect(store.courseFor('CSC 3380')!.shareCode, 'K7Q2M');

    final code = tester.widget<Text>(find.text('K7Q2M'));
    expect(code.style!.fontSize, 28);
    expect(code.style!.letterSpacing, 8);
    expect(code.style!.fontFamily, 'monospace');
  });

  testWidgets('tapping the code copies it with haptic feedback', (tester) async {
    await pumpSheet(tester, existingCode: 'H4PSD');

    await tester.tap(find.text('H4PSD'));
    await tester.pumpAndSettle();

    expect(clipboard, ['H4PSD']);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    expect(find.text('✓ Copied to clipboard!'), findsOneWidget);
    expect(find.text('Tap to copy'), findsNothing);
  });

  testWidgets('an existing code is reused without calling the server', (tester) async {
    final (_, requests) = await pumpSheet(tester, existingCode: 'H4PSD');
    expect(find.text('H4PSD'), findsOneWidget);
    expect(requests, isEmpty);
  });
}
