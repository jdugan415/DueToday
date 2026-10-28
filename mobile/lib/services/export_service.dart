import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/dashboard_buckets.dart';

enum ExportFormat {
  markdown('Markdown', 'md', 'text/markdown'),
  notionCsv('Notion CSV', 'csv', 'text/csv');

  const ExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

/// Turns assignments into portable files and hands them to the Android share
/// sheet (`ACTION_SEND` through share_plus's private FileProvider). The user
/// picks the destination (Drive, Notion, email, Files), so no storage
/// permission is ever needed.
class ExportService {
  ExportService._();

  static final DateFormat _humanDue = DateFormat('EEE, MMM d');
  static final DateFormat _humanTime = DateFormat('h:mm a');
  static final DateFormat _notionDue = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _notionDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _stamp = DateFormat('EEE, MMM d, yyyy');

  static String render(
    ExportFormat format,
    List<Course> courses,
    List<Assignment> assignments, {
    DateTime? now,
  }) =>
      switch (format) {
        ExportFormat.markdown => toMarkdown(courses, assignments, now: now),
        ExportFormat.notionCsv => toNotionCsv(courses, assignments),
      };

  /// A checklist per course, soonest first, ready to paste into Obsidian,
  /// GitHub, or Notion (which converts `- [ ]` to to-do blocks).
  static String toMarkdown(List<Course> courses, List<Assignment> assignments, {DateTime? now}) {
    final buffer = StringBuffer()
      ..writeln('# DueToday assignments')
      ..writeln()
      ..writeln('_Exported ${_stamp.format(now ?? DateTime.now())}_');

    for (final group in _groupByCourse(courses, assignments)) {
      buffer
        ..writeln()
        ..writeln('## ${_markdownEscape(group.course.displayName)}')
        ..writeln();
      for (final a in group.items) {
        final details = [
          _humanDueText(a),
          if (a.weightPercent != null) '${_number(a.weightPercent!)}%',
          if (a.points != null) '${a.points} pts',
          _capitalize(a.priority.name),
        ];
        buffer.writeln(
          '- [${a.completed ? 'x' : ' '}] **${_markdownEscape(a.title)}**: ${details.join(' · ')}',
        );
        if (a.notes != null && a.notes!.trim().isNotEmpty) {
          buffer.writeln('  - ${_markdownEscape(a.notes!.trim().replaceAll('\n', ' '))}');
        }
      }
    }
    return buffer.toString();
  }

  /// RFC 4180 CSV with columns Notion maps onto a database on import:
  /// Name (title), Course/Type/Priority/Status (select), Due (date), Weight/Points (number).
  static String toNotionCsv(List<Course> courses, List<Assignment> assignments) {
    const header = ['Name', 'Course', 'Type', 'Due', 'Weight', 'Points', 'Priority', 'Status', 'Notes'];
    final rows = <List<String>>[header];
    for (final group in _groupByCourse(courses, assignments)) {
      for (final a in group.items) {
        final due = a.dueAt;
        rows.add([
          a.title,
          group.course.code,
          _capitalize(a.taskType),
          due == null ? '' : (a.timeSpecified ? _notionDue.format(due) : _notionDate.format(due)),
          a.weightPercent == null ? '' : _number(a.weightPercent!),
          a.points?.toString() ?? '',
          _capitalize(a.priority.name),
          a.completed ? 'Done' : 'Not started',
          a.notes ?? '',
        ]);
      }
    }
    return '${rows.map((row) => row.map(_csvField).join(',')).join('\r\n')}\r\n';
  }

  static String fileName(ExportFormat format, DateTime now) =>
      'duetoday-${DateFormat('yyyy-MM-dd').format(now)}.${format.extension}';

  /// Opens the system share sheet with the export attached as a file.
  static Future<ShareResult> share(
    ExportFormat format,
    List<Course> courses,
    List<Assignment> assignments,
  ) {
    final now = DateTime.now();
    final content = render(format, courses, assignments, now: now);
    final name = fileName(format, now);
    return SharePlus.instance.share(ShareParams(
      subject: 'DueToday assignments',
      title: 'Export ${format.label}',
      files: [XFile.fromData(utf8.encode(content), mimeType: format.mimeType, name: name)],
      fileNameOverrides: [name],
    ));
  }

  static List<({Course course, List<Assignment> items})> _groupByCourse(
    List<Course> courses,
    List<Assignment> assignments,
  ) {
    final byCode = {for (final c in courses) c.code: c};
    final grouped = <String, List<Assignment>>{};
    for (final a in assignments) {
      grouped.putIfAbsent(a.courseCode, () => []).add(a);
    }
    final codes = grouped.keys.toList()..sort();
    return [
      for (final code in codes)
        (
          course: byCode[code] ?? Course(code: code),
          items: grouped[code]!..sort(DashboardBuckets.compareByUrgency),
        ),
    ];
  }

  static String _humanDueText(Assignment a) {
    final due = a.dueAt;
    if (due == null) return 'No due date';
    final day = _humanDue.format(due);
    return a.timeSpecified ? '$day, ${_humanTime.format(due)}' : day;
  }

  static String _csvField(String value) {
    if (value.contains(RegExp(r'[",\r\n]'))) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _markdownEscape(String value) => value.replaceAllMapped(
        RegExp(r'([\\`*_\[\]<>#|])'),
        (m) => '\\${m[1]}',
      );

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}
