import 'package:flutter/foundation.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/dashboard_buckets.dart';
import '../services/storage_service.dart';
import '../theme.dart';

/// App-wide state: every assignment and course on this device. Every
/// mutation is written through to [StorageService] immediately, so the app
/// works fully offline after the initial parse.
class AssignmentStore extends ChangeNotifier {
  AssignmentStore(this._storage, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final StorageService _storage;
  final DateTime Function() _clock;

  List<Assignment> _assignments = [];
  final Map<String, Course> _courses = {};

  List<Assignment> get assignments => List.unmodifiable(_assignments);
  List<Course> get courses => List.unmodifiable(_courses.values);

  DateTime now() => _clock();

  Course? courseFor(String code) => _courses[code];

  DashboardBuckets buckets() => DashboardBuckets.from(_assignments, _clock());

  List<Assignment> assignmentsFor(String courseCode) =>
      _assignments.where((a) => a.courseCode == courseCode).toList();

  Future<void> load() async {
    _assignments = _storage.loadAssignments();
    _courses
      ..clear()
      ..addEntries(_storage.loadCourses().map((c) => MapEntry(c.code, c)));
    notifyListeners();
  }

  /// Adds (or replaces, matched by id) assignments for [course]. Re-parsing
  /// the same syllabus therefore updates items instead of duplicating them.
  Future<void> addAll(Course course, List<Assignment> items) async {
    final existing = _courses[course.code];
    _courses[course.code] = existing == null
        ? course.copyWith(colorIndex: _courses.length % courseColors.length)
        : existing.copyWith(name: course.name, shareCode: course.shareCode);

    final incoming = {for (final item in items) item.id: item.copyWith(courseCode: course.code)};
    _assignments = [
      for (final a in _assignments)
        if (!incoming.containsKey(a.id)) a,
      ...incoming.values,
    ];
    await _persist();
  }

  Future<void> update(Assignment updated) async {
    _assignments = [for (final a in _assignments) a.id == updated.id ? updated : a];
    await _persist();
  }

  Future<void> remove(String id) async {
    _assignments = _assignments.where((a) => a.id != id).toList();
    await _persist();
  }

  Future<void> toggleCompleted(String id) => _modify(id, (a) => a.copyWith(completed: !a.completed));

  Future<void> markAddedToCalendar(String id) =>
      _modify(id, (a) => a.copyWith(addedToCalendar: true));

  Future<void> setShareCode(String courseCode, String shareCode) async {
    final course = _courses[courseCode];
    if (course == null) return;
    _courses[courseCode] = course.copyWith(shareCode: shareCode);
    await _persist();
  }

  Future<void> _modify(String id, Assignment Function(Assignment) change) async {
    _assignments = [for (final a in _assignments) a.id == id ? change(a) : a];
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await Future.wait([
      _storage.saveAssignments(_assignments),
      _storage.saveCourses(_courses.values.toList()),
    ]);
  }
}
