import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:due_today/services/api_service.dart';
import 'package:due_today/services/storage_service.dart';
import 'package:due_today/state/assignment_store.dart';
import 'package:due_today/views/paste_view.dart';
import 'package:due_today/views/staging_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scannedMessage =
    'Could not extract text. If this is a scanned document, please copy and paste the text directly.';

final _fakePdf = Uint8List.fromList(utf8.encode('%PDF-1.4 fake syllabus'));

Map<String, dynamic> _parseResponse() => {
      'course_code': 'CSC 4330',
      'reference_date': '2026-08-24',
      'warnings': <String>[],
      'tasks': [
        {
          'id': 'p1',
          'title': 'Midterm Exam',
          'task_type': 'midterm',
          'due_date': '2026-10-07',
          'due_time': '23:59',
          'due_datetime': '2026-10-07T23:59:00',
          'time_specified': false,
          'weight_percent': 20,
          'priority': 'high',
          'confidence': 1.0,
          'source_line': 'Oct 7   Midterm Exam (20%)',
        },
      ],
    };

Future<Widget> _app({required ApiService api, required Future<PickedPdf?> Function() pick}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AssignmentStore(await StorageService.create(), clock: () => DateTime(2026, 8, 24));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: store),
      Provider.value(value: api),
    ],
    child: MaterialApp(home: PasteView(pickPdf: pick)),
  );
}

void main() {
  testWidgets('network failure preserves text and code; retry opens Review once', (tester) async {
    var calls = 0;
    final retryResponse = Completer<http.Response>();
    final bodies = <Map<String, dynamic>>[];
    final api = ApiService(baseUrl: 'http://test', client: MockClient((request) async {
      calls++;
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (calls == 1) throw http.ClientException('Connection refused');
      return retryResponse.future;
    }));
    await tester.pumpWidget(await _app(api: api, pick: () async => null));
    await tester.enterText(find.byType(TextField).at(0), 'CSC 4330');
    await tester.enterText(find.byType(TextField).at(1), 'Nov 12 Homework 1');
    await tester.tap(find.text('Parse Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Your syllabus and course code are still here.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, 'Nov 12 Homework 1');
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, 'CSC 4330');
    final retry = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry')).onPressed!;
    retry();
    retry(); // A second callback before the next frame must not send another request.
    await tester.pump();
    expect(calls, 2);
    for (final body in bodies) {
      expect(body['raw_text'], 'Nov 12 Homework 1');
      expect(body['course_code'], 'CSC 4330');
    }
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Parse Schedule')).onPressed, isNull);
    retryResponse.complete(http.Response(jsonEncode(_parseResponse()), 200));
    await tester.pumpAndSettle();
    expect(find.byType(StagingView), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StagingView), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('PDF retry reuses selected bytes without reopening picker', (tester) async {
    var picks = 0;
    var calls = 0;
    final api = ApiService(baseUrl: 'http://test', client: MockClient((request) async {
      calls++;
      expect(utf8.decode(request.bodyBytes, allowMalformed: true), contains('%PDF-1.4 fake syllabus'));
      if (calls == 1) throw http.ClientException('Connection refused');
      return http.Response(jsonEncode(_parseResponse()), 200);
    }));
    await tester.pumpWidget(await _app(api: api, pick: () async {
      picks++;
      return (name: 'schedule.pdf', bytes: _fakePdf);
    }));
    await tester.tap(find.text('Choose File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(calls, 2);
    expect(find.byType(StagingView), findsOneWidget);
  });

  group('ApiService.parseSyllabusPdf', () {
    test('sends a multipart upload with the form fields', () async {
      late http.Request sent;
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode(_parseResponse()), 200);
        }),
      );

      final result = await api.parseSyllabusPdf(
        bytes: _fakePdf,
        filename: 'Syllabus',
        courseCode: 'csc 4330',
        today: DateTime(2026, 8, 24),
      );

      expect(sent.url.toString(), 'http://test/api/parse-pdf');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      final body = utf8.decode(sent.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"; filename="Syllabus.pdf"'));
      expect(body, contains('%PDF-1.4 fake syllabus'));
      expect(body, contains('name="reference_date"\r\n\r\n2026-08-24'));
      expect(body, contains('name="course_code"\r\n\r\nCSC 4330'));
      expect(result.assignments.single.title, 'Midterm Exam');
      expect(result.courseCode, 'CSC 4330');
    });

    test('surfaces the scanned-PDF message from the server', () async {
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(
              jsonEncode({'detail': _scannedMessage, 'error': _scannedMessage}),
              422,
            )),
      );
      await expectLater(
        api.parseSyllabusPdf(bytes: _fakePdf, filename: 'scan.pdf'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', _scannedMessage)),
      );
    });

    test('rejects files over 10 MB without uploading', () async {
      var called = false;
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.parseSyllabusPdf(bytes: Uint8List(ApiService.maxPdfBytes + 1), filename: 'big.pdf'),
        throwsA(isA<ApiException>()),
      );
      expect(called, isFalse);
    });
  });

  group('PasteView PDF upload', () {
    testWidgets('shows the upload card', (tester) async {
      await tester.pumpWidget(await _app(
        api: ApiService(baseUrl: 'http://test', client: MockClient((_) async => http.Response('', 500))),
        pick: () async => null,
      ));
      expect(find.text('Or upload syllabus PDF'), findsOneWidget);
      expect(find.text('Supports .pdf files up to 10MB'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('uploads the picked PDF and opens the review screen', (tester) async {
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(jsonEncode(_parseResponse()), 200);
        }),
      );
      await tester.pumpWidget(await _app(api: api, pick: () async => (name: 'CSC4330.pdf', bytes: _fakePdf)));

      await tester.tap(find.text('Choose File'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Reading CSC4330.pdf…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('1 Assignment Detected'), findsOneWidget);
      expect(find.text('Midterm Exam'), findsOneWidget);
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      var requests = 0;
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await tester.pumpWidget(await _app(api: api, pick: () async => null));
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('scanned PDFs show the paste-instead message', (tester) async {
      final api = ApiService(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(
              jsonEncode({'detail': _scannedMessage, 'error': _scannedMessage}),
              422,
            )),
      );
      await tester.pumpWidget(await _app(api: api, pick: () async => (name: 'scan.pdf', bytes: _fakePdf)));
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();

      expect(find.text(_scannedMessage), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget); // still on the paste screen
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
