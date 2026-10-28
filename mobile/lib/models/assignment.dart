import 'package:intl/intl.dart';

/// Importance of an assignment as computed by the backend parser
/// (exams and heavily weighted work are [Priority.high]).
enum Priority { high, medium, low }

Priority priorityFromName(String? name) => Priority.values.firstWhere(
      (p) => p.name == name,
      orElse: () => Priority.medium,
    );

final DateFormat _naiveFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

/// Formats a local wall-clock time the way the API expects it: ISO-8601
/// without a UTC offset (e.g. `2026-09-28T23:59:00`).
String formatNaiveDateTime(DateTime value) => _naiveFormat.format(value);

/// Parses an API datetime. Strings without an offset parse as device-local.
DateTime? parseNaiveDateTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value) : null;

class Assignment {
  const Assignment({
    required this.id,
    required this.courseCode,
    required this.title,
    this.taskType = 'other',
    this.dueAt,
    this.timeSpecified = false,
    this.weightPercent,
    this.points,
    this.priority = Priority.medium,
    this.confidence = 1.0,
    this.notes,
    this.completed = false,
    this.addedToCalendar = false,
    this.sourceLine,
  });

  final String id;
  final String courseCode;
  final String title;
  final String taskType;
  final DateTime? dueAt;
  final bool timeSpecified;
  final double? weightPercent;
  final int? points;
  final Priority priority;

  /// Parser confidence in [0, 1]. Values below [reviewThreshold] are flagged
  /// in the staging screen so the user double-checks them.
  final double confidence;
  final String? notes;
  final bool completed;
  final bool addedToCalendar;
  final String? sourceLine;

  static const double reviewThreshold = 0.8;

  bool get needsReview => dueAt == null || confidence < reviewThreshold;

  /// Builds an assignment from one item of `POST /api/parse` → `tasks[]`.
  factory Assignment.fromParsedJson(
    Map<String, dynamic> json, {
    required String courseCode,
  }) {
    return Assignment(
      id: json['id'] as String,
      courseCode: courseCode,
      title: json['title'] as String,
      taskType: json['task_type'] as String? ?? 'other',
      dueAt: parseNaiveDateTime(json['due_datetime']),
      timeSpecified: json['time_specified'] as bool? ?? false,
      weightPercent: (json['weight_percent'] as num?)?.toDouble(),
      points: (json['points'] as num?)?.toInt(),
      priority: priorityFromName(json['priority'] as String?),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      sourceLine: json['source_line'] as String?,
    );
  }

  /// Builds an assignment from one item of `GET /api/courses/{code}` → `tasks[]`.
  factory Assignment.fromSharedJson(
    Map<String, dynamic> json, {
    required String courseCode,
    required String shareCode,
  }) {
    final dueAt = parseNaiveDateTime(json['due_datetime']);
    return Assignment(
      id: 'shared-$shareCode-${json['id']}',
      courseCode: courseCode,
      title: json['title'] as String,
      taskType: json['task_type'] as String? ?? 'other',
      dueAt: dueAt,
      timeSpecified: dueAt != null,
      weightPercent: (json['weight_percent'] as num?)?.toDouble(),
      points: (json['points'] as num?)?.toInt(),
      priority: priorityFromName(json['priority'] as String?),
      notes: json['notes'] as String?,
    );
  }

  /// Local persistence format (SharedPreferences).
  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as String,
      courseCode: json['courseCode'] as String,
      title: json['title'] as String,
      taskType: json['taskType'] as String? ?? 'other',
      dueAt: parseNaiveDateTime(json['dueAt']),
      timeSpecified: json['timeSpecified'] as bool? ?? false,
      weightPercent: (json['weightPercent'] as num?)?.toDouble(),
      points: (json['points'] as num?)?.toInt(),
      priority: priorityFromName(json['priority'] as String?),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      notes: json['notes'] as String?,
      completed: json['completed'] as bool? ?? false,
      addedToCalendar: json['addedToCalendar'] as bool? ?? false,
      sourceLine: json['sourceLine'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseCode': courseCode,
        'title': title,
        'taskType': taskType,
        'dueAt': dueAt == null ? null : formatNaiveDateTime(dueAt!),
        'timeSpecified': timeSpecified,
        'weightPercent': weightPercent,
        'points': points,
        'priority': priority.name,
        'confidence': confidence,
        'notes': notes,
        'completed': completed,
        'addedToCalendar': addedToCalendar,
        'sourceLine': sourceLine,
      };

  /// Request body item for `POST /api/courses` → `tasks[]`.
  Map<String, dynamic> toTaskInJson() => {
        'title': title,
        'task_type': taskType,
        'due_datetime': dueAt == null ? null : formatNaiveDateTime(dueAt!),
        'weight_percent': weightPercent,
        'points': points,
        'priority': priority.name,
        'notes': notes,
      };

  Assignment copyWith({
    String? courseCode,
    String? title,
    DateTime? dueAt,
    bool? timeSpecified,
    Priority? priority,
    double? confidence,
    String? notes,
    bool? completed,
    bool? addedToCalendar,
  }) {
    return Assignment(
      id: id,
      courseCode: courseCode ?? this.courseCode,
      title: title ?? this.title,
      taskType: taskType,
      dueAt: dueAt ?? this.dueAt,
      timeSpecified: timeSpecified ?? this.timeSpecified,
      weightPercent: weightPercent,
      points: points,
      priority: priority ?? this.priority,
      confidence: confidence ?? this.confidence,
      notes: notes ?? this.notes,
      completed: completed ?? this.completed,
      addedToCalendar: addedToCalendar ?? this.addedToCalendar,
      sourceLine: sourceLine,
    );
  }
}
