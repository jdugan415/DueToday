import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../models/course.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ParseResult {
  const ParseResult({
    required this.courseCode,
    required this.assignments,
    required this.warnings,
  });

  final String courseCode;
  final List<Assignment> assignments;
  final List<String> warnings;
}

class SharedCourse {
  const SharedCourse({required this.course, required this.assignments});

  final Course course;
  final List<Assignment> assignments;
}

/// HTTP client for the FastAPI backend. See AGENT_HANDOVER.md §3 for the
/// contract. Override the server with
/// `flutter run --dart-define=API_BASE_URL=https://your-api.onrender.com`.
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? defaultBaseUrl;

  /// 10.0.2.2 is the Android emulator's alias for the host machine.
  static const String defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// Free-tier hosts (Render) cold-start in ~30-50 s, so be generous.
  static const Duration timeout = Duration(seconds: 60);

  static const String fallbackCourseCode = 'GENERAL';

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// `POST /api/parse`. [today] is sent as `reference_date` so relative
  /// dates resolve against the device's calendar day, not the server's.
  Future<ParseResult> parseSyllabus(
    String rawText, {
    String? courseCode,
    DateTime? today,
  }) async {
    final requestedCode = courseCode == null || courseCode.trim().isEmpty
        ? null
        : Course.normalizeCode(courseCode);
    final body = await _send(() => _client.post(
          _uri('/api/parse'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'raw_text': rawText,
            'course_code': requestedCode,
            'reference_date': DateFormat('yyyy-MM-dd').format(today ?? DateTime.now()),
          }),
        ));

    final code = body['course_code'] as String? ?? requestedCode ?? fallbackCourseCode;
    final tasks = (body['tasks'] as List).cast<Map<String, dynamic>>();
    return ParseResult(
      courseCode: code,
      assignments: tasks.map((t) => Assignment.fromParsedJson(t, courseCode: code)).toList(),
      warnings: (body['warnings'] as List? ?? const []).cast<String>(),
    );
  }

  /// `POST /api/courses`. Returns the new 5-character share code.
  Future<String> shareCourse(Course course, List<Assignment> assignments) async {
    final body = await _send(() => _client.post(
          _uri('/api/courses'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'course_code': course.code,
            'course_name': course.name,
            'tasks': assignments.map((a) => a.toTaskInJson()).toList(),
          }),
        ));
    return body['share_code'] as String;
  }

  /// `GET /api/courses/{code}`.
  Future<SharedCourse> importCourse(String shareCode) async {
    final code = shareCode.trim().toUpperCase();
    final body = await _send(() => _client.get(_uri('/api/courses/$code')));
    final courseCode = body['course_code'] as String;
    final tasks = (body['tasks'] as List).cast<Map<String, dynamic>>();
    return SharedCourse(
      course: Course(
        code: courseCode,
        name: body['course_name'] as String?,
        shareCode: body['share_code'] as String?,
      ),
      assignments: tasks
          .map((t) => Assignment.fromSharedJson(t, courseCode: courseCode, shareCode: code))
          .toList(),
    );
  }

  /// Public iCalendar feed for a shared course
  /// (`GET /api/courses/{code}/calendar.ics`). Subscribing to it in Google
  /// Calendar ("Other calendars → From URL") keeps every deadline synced
  /// without the app holding calendar permissions.
  String calendarFeedUrl(String shareCode) =>
      '$baseUrl/api/courses/${shareCode.trim().toUpperCase()}/calendar.ics';

  void close() => _client.close();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond. Try again in a moment.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the DueToday server (${error.message}).');
    }

    final decoded = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw ApiException(_errorMessage(response.statusCode, decoded), statusCode: response.statusCode);
  }

  static String _errorMessage(int status, Object? decoded) {
    final detail = decoded is Map ? decoded['detail'] : null;
    if (detail is String) return detail;
    if (status == 404) return 'Not found.';
    if (status == 422) return 'The server rejected that input.';
    return 'Server error ($status).';
  }
}
