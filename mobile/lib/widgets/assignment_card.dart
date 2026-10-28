import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../services/calendar_service.dart';
import '../state/assignment_store.dart';
import '../theme.dart';

String formatDue(Assignment assignment) {
  final due = assignment.dueAt;
  if (due == null) return 'No due date';
  final day = DateFormat('EEE, MMM d').format(due);
  return assignment.timeSpecified ? '$day · ${DateFormat('h:mm a').format(due)}' : day;
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<AssignmentStore>();
    final colorIndex = context.select<AssignmentStore, int>(
      (s) => s.courseFor(assignment.courseCode)?.colorIndex ?? 0,
    );
    final details = [
      formatDue(assignment),
      if (assignment.weightPercent != null) '${_trim(assignment.weightPercent!)}%',
      if (assignment.points != null) '${assignment.points} pts',
    ].join('  •  ');

    return Card(
      child: InkWell(
        onLongPress: () => _confirmDelete(context, store),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Checkbox(
                value: assignment.completed,
                onChanged: (_) => store.toggleCompleted(assignment.id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration: assignment.completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CourseBadge(code: assignment.courseCode, color: courseColor(colorIndex)),
                        Text(details, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              PriorityBadge(priority: assignment.priority),
              IconButton(
                tooltip: assignment.addedToCalendar ? 'Add to calendar again' : 'Add to calendar',
                icon: Icon(
                  assignment.addedToCalendar ? Icons.event_available : Icons.calendar_month_outlined,
                ),
                onPressed: () => _addToCalendar(context, store),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToCalendar(BuildContext context, AssignmentStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    final due = assignment.dueAt;
    if (due == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Set a due date first.')));
      return;
    }
    bool launched;
    try {
      launched = await CalendarService.addAssignmentToDeviceCalendar(
        courseCode: assignment.courseCode,
        title: assignment.title,
        dueDate: due,
        notes: assignment.notes,
      );
    } on PlatformException {
      launched = false;
    }
    if (launched) {
      await store.markAddedToCalendar(assignment.id);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('No calendar app found on this device.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, AssignmentStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete assignment?'),
        content: Text(assignment.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed ?? false) await store.remove(assignment.id);
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final Priority priority;

  @override
  Widget build(BuildContext context) {
    final style = priorityStyle(priority, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        style.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: style.foreground),
      ),
    );
  }
}

class CourseBadge extends StatelessWidget {
  const CourseBadge({super.key, required this.code, required this.color});

  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
