import 'assignment.dart';

/// Splits assignments into the dashboard's sections relative to [now].
class DashboardBuckets {
  DashboardBuckets._({
    required this.overdue,
    required this.dueToday,
    required this.thisWeek,
    required this.later,
    required this.unscheduled,
    required this.completed,
  });

  final List<Assignment> overdue;
  final List<Assignment> dueToday;

  /// Due after today and within the next 7 days.
  final List<Assignment> thisWeek;
  final List<Assignment> later;
  final List<Assignment> unscheduled;
  final List<Assignment> completed;

  factory DashboardBuckets.from(Iterable<Assignment> items, DateTime now) {
    final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
    final endOfWeek = DateTime(now.year, now.month, now.day + 8);

    final overdue = <Assignment>[];
    final dueToday = <Assignment>[];
    final thisWeek = <Assignment>[];
    final later = <Assignment>[];
    final unscheduled = <Assignment>[];
    final completed = <Assignment>[];

    for (final item in items) {
      final due = item.dueAt;
      if (item.completed) {
        completed.add(item);
      } else if (due == null) {
        unscheduled.add(item);
      } else if (due.isBefore(now)) {
        overdue.add(item);
      } else if (due.isBefore(startOfTomorrow)) {
        dueToday.add(item);
      } else if (due.isBefore(endOfWeek)) {
        thisWeek.add(item);
      } else {
        later.add(item);
      }
    }

    for (final list in [overdue, dueToday, thisWeek, later, unscheduled, completed]) {
      list.sort(compareByUrgency);
    }
    return DashboardBuckets._(
      overdue: overdue,
      dueToday: dueToday,
      thisWeek: thisWeek,
      later: later,
      unscheduled: unscheduled,
      completed: completed,
    );
  }

  /// Earliest due first; ties broken by priority (high before low).
  static int compareByUrgency(Assignment a, Assignment b) {
    final aDue = a.dueAt, bDue = b.dueAt;
    if (aDue != null && bDue != null) {
      final byDate = aDue.compareTo(bDue);
      if (byDate != 0) return byDate;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }
    return a.priority.index.compareTo(b.priority.index);
  }
}
