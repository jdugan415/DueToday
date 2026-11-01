import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../models/assignment.dart';
import 'calendar_service.dart';
import 'export_service.dart';

/// "Add all to calendar": builds one RFC 5545 `.ics` file holding many
/// assignments and hands it to the Android share sheet, where the user picks
/// their calendar app to import it.
///
/// Like [CalendarService], this keeps DueToday at zero permissions: the
/// calendar app does the writing, and share_plus serves the file from its
/// private FileProvider in the cache dir (no storage permission).
///
/// The format mirrors `backend/app/ics.py`: floating local times (no TZID,
/// no Z), escaped TEXT values, 75-octet line folding, CRLF line endings, and
/// a stable UID per assignment so calendars that honour UIDs update an event
/// on re-import instead of duplicating it.
class IcsService {
  IcsService._();

  static const String mimeType = 'text/calendar';

  /// Assignments worth exporting: dated, not completed, still ahead of [now],
  /// and not already sent one by one (those events have no UID link, so
  /// exporting them again would create duplicates). Soonest first.
  static List<Assignment> eligible(Iterable<Assignment> assignments, DateTime now) => [
        for (final a in assignments)
          if (a.dueAt != null && !a.completed && !a.addedToCalendar && a.dueAt!.isAfter(now)) a,
      ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  /// Renders [assignments] as a VCALENDAR. Undated items are skipped.
  static String build(
    List<Assignment> assignments, {
    required DateTime now,
    String calendarName = 'DueToday',
  }) {
    final stamp = '${_floating(now.toUtc())}Z';
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//DueToday//Syllabus Tracker//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escape(calendarName)}',
      for (final a in assignments)
        if (a.dueAt != null) ..._event(a, stamp),
      'END:VCALENDAR',
    ];
    return lines.map((line) => '${_fold(line)}\r\n').join();
  }

  static String fileName(DateTime now) =>
      'duetoday-${now.year}-${_two(now.month)}-${_two(now.day)}.ics';

  /// Opens the share sheet with the `.ics` attached. On Android the result is
  /// [ShareResultStatus.success] once the user picks a target app.
  static Future<ShareResult> share(List<Assignment> assignments, {String calendarName = 'DueToday'}) {
    final now = DateTime.now();
    return ExportService.shareFile(
      content: build(assignments, now: now, calendarName: calendarName),
      fileName: fileName(now),
      mimeType: mimeType,
      subject: 'DueToday deadlines',
      title: 'Add to calendar',
    );
  }

  static List<String> _event(Assignment a, String stamp) {
    final due = a.dueAt!;
    final notes = a.notes?.trim();
    final details = [
      'Type: ${a.taskType}',
      'Priority: ${a.priority.name}',
      if (a.weightPercent != null) 'Weight: ${_number(a.weightPercent!)}%',
      if (a.points != null) 'Points: ${a.points}',
      if (notes != null && notes.isNotEmpty) notes,
    ];
    return [
      'BEGIN:VEVENT',
      'UID:assignment-${a.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}@duetoday',
      'DTSTAMP:$stamp',
      'DTSTART:${_floating(due)}',
      'DTEND:${_floating(due.add(CalendarService.eventLength))}',
      // Same title format as the single-event intent in CalendarService.
      'SUMMARY:${_escape('[${a.courseCode}] ${a.title}')}',
      'DESCRIPTION:${_escape(details.join('\n'))}',
      'CATEGORIES:${_escape(a.taskType.toUpperCase())}',
      'TRANSP:TRANSPARENT',
      'END:VEVENT',
    ];
  }

  /// `yyyyMMddTHHmmss` with ASCII digits whatever the device locale.
  static String _floating(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}'
      'T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Escapes a TEXT value (RFC 5545 §3.3.11).
  static String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  /// Folds lines longer than 75 octets (RFC 5545 §3.1) without splitting a
  /// multi-byte UTF-8 character. Continuation lines start with a space.
  static String _fold(String line, {int limit = 75}) {
    if (utf8.encode(line).length <= limit) return line;
    final parts = <String>[];
    final current = StringBuffer();
    var size = 0;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final width = utf8.encode(char).length;
      if (size + width > (parts.isEmpty ? limit : limit - 1)) {
        parts.add(current.toString());
        current.clear();
        size = 0;
      }
      current.write(char);
      size += width;
    }
    parts.add(current.toString());
    return parts.join('\r\n ');
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
}
