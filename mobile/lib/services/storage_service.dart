import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/course.dart';

/// Offline-first persistence. The device is the source of truth for a
/// student's assignments; the backend is only used to parse text and to
/// exchange class codes.
class StorageService {
  StorageService(this._prefs);

  static const String assignmentsKey = 'assignments_v1';
  static const String coursesKey = 'courses_v1';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async =>
      StorageService(await SharedPreferences.getInstance());

  List<Assignment> loadAssignments() => _decodeList(assignmentsKey, Assignment.fromJson);

  List<Course> loadCourses() => _decodeList(coursesKey, Course.fromJson);

  Future<void> saveAssignments(List<Assignment> items) =>
      _prefs.setString(assignmentsKey, jsonEncode(items.map((a) => a.toJson()).toList()));

  Future<void> saveCourses(List<Course> items) =>
      _prefs.setString(coursesKey, jsonEncode(items.map((c) => c.toJson()).toList()));

  List<T> _decodeList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final item in jsonDecode(raw) as List) fromJson(item as Map<String, dynamic>)];
    } on Object catch (error) {
      // Corrupt or schema-incompatible cache: start fresh rather than crash.
      debugPrint('StorageService: discarding unreadable "$key": $error');
      return [];
    }
  }
}
