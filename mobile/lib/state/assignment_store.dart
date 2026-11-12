import 'package:flutter/foundation.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/dashboard_buckets.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

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

  /// Adds new assignments for [course], keeping saved assignments on ID matches.
  Future<void> addAll(Course course, List<Assignment> items) async {
    _mergeCourse(course);
    final byId = {for (final item in _assignments) item.id: item};
    for (final item in items) {
      byId.putIfAbsent(item.id, () => item.copyWith(courseCode: course.code));
    }
    _assignments = byId.values.toList();
    await _persist();
  }

  /// Adds a classmate's shared course. Items already on this phone are kept
  /// as they are (with their completed state): a match is the same id (the
  /// same code imported again) or, in the same course, the same title and
  /// due day (the student parsed this syllabus too, or the course was
  /// re-shared under a new code). Returns how many items were new.
  Future<int> importShared(Course course, List<Assignment> items) async {
    _mergeCourse(course);
    final ids = {for (final a in _assignments) a.id};
    final keys = {
      for (final a in _assignments)
        if (a.courseCode == course.code) _matchKey(a),
    };
    final added = <Assignment>[];
    for (final item in items) {
      final a = item.copyWith(courseCode: course.code);
      if (ids.contains(a.id) || !keys.add(_matchKey(a))) continue;
      ids.add(a.id);
      added.add(a);
    }
    _assignments = [..._assignments, ...added];
    await _persist();
    return added.length;
  }

  static String _matchKey(Assignment a) {
    final title = a.title.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    final due = a.dueAt;
    return due == null ? '$title|' : '$title|${due.year}-${due.month}-${due.day}';
  }

  void _mergeCourse(Course course) {
    final existing = _courses[course.code];
    _courses[course.code] = existing == null
        ? course.copyWith(colorIndex: courseColorIndexFor(course.code))
        : existing.copyWith(name: course.name, shareCode: course.shareCode);
  }

  Future<void> update(Assignment updated) async {
    _assignments = [for (final a in _assignments) a.id == updated.id ? updated : a];
    await _persist();
  }

  Future<void> remove(String id) async {
    _assignments = _assignments.where((a) => a.id != id).toList();
    await _persist();
  }

  /// Puts back an assignment removed with [remove] (the Undo action).
  Future<void> restore(Assignment assignment) async {
    _assignments = [..._assignments.where((a) => a.id != assignment.id), assignment];
    await _persist();
  }

  Future<void> updateCourse(Course course) async {
    if (!_courses.containsKey(course.code)) return;
    _courses[course.code] = course;
    await _persist();
  }

  /// Deletes a course and every assignment that belongs to it.
  Future<void> removeCourse(String code) async {
    _courses.remove(code);
    _assignments = _assignments.where((a) => a.courseCode != code).toList();
    await _persist();
  }

  Future<void> toggleCompleted(String id) => _modify(id, (a) => a.copyWith(completed: !a.completed));

  Future<void> markAddedToCalendar(String id) =>
      _modify(id, (a) => a.copyWith(addedToCalendar: true));

  /// Flags every assignment in [ids] as sent to the calendar (one write).
  Future<void> markAllAddedToCalendar(Iterable<String> ids) async {
    final marked = ids.toSet();
    if (marked.isEmpty) return;
    _assignments = [
      for (final a in _assignments) marked.contains(a.id) ? a.copyWith(addedToCalendar: true) : a,
    ];
    await _persist();
  }

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
