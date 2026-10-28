import 'package:intl/intl.dart';

import 'assignment.dart';

enum Urgency {
  /// Already past due.
  overdue,

  /// Due within the next 24 hours.
  imminent,

  /// Due within the next 3 days.
  soon,

  /// Later, undated, or done.
  calm,
}

/// Countdown text for a card's urgency badge, e.g. "Due in 4h", "Tomorrow",
/// "Overdue 2d", "Thu", "Nov 12".
class DueLabel {
  const DueLabel(this.text, this.urgency);

  final String text;
  final Urgency urgency;

  static const Duration _imminentWindow = Duration(hours: 24);
  static const Duration _soonWindow = Duration(days: 3);

  factory DueLabel.of(Assignment assignment, DateTime now) {
    final due = assignment.dueAt;
    if (assignment.completed) return const DueLabel('Done', Urgency.calm);
    if (due == null) return const DueLabel('No date', Urgency.calm);

    final left = due.difference(now);
    if (left.isNegative) {
      final late = -left;
      final text = late.inMinutes < 60
          ? 'Overdue'
          : late.inHours < 24
              ? 'Overdue ${late.inHours}h'
              : 'Overdue ${late.inDays}d';
      return DueLabel(text, Urgency.overdue);
    }
    if (left < _imminentWindow) {
      final text = left.inMinutes < 60 ? 'Due in ${left.inMinutes.clamp(1, 59)}m' : 'Due in ${left.inHours}h';
      return DueLabel(text, Urgency.imminent);
    }

    final days = _calendarDaysBetween(now, due);
    final urgency = left < _soonWindow ? Urgency.soon : Urgency.calm;
    if (days == 1) return DueLabel('Tomorrow', urgency);
    if (days < 7) return DueLabel(DateFormat('EEEE').format(due), urgency);
    final format = due.year == now.year ? DateFormat('MMM d') : DateFormat('MMM d, y');
    return DueLabel(format.format(due), urgency);
  }

  /// Whole calendar days from [from]'s date to [to]'s date (DST-safe).
  static int _calendarDaysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}
