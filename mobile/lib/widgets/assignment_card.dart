import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../services/calendar_service.dart';
import '../state/assignment_store.dart';
import '../theme.dart';
import '../views/edit_assignment_view.dart';

String formatDue(Assignment assignment) {
  final due = assignment.dueAt;
  if (due == null) return 'No due date';
  final day = DateFormat('EEE, MMM d').format(due);
  return assignment.timeSpecified ? '$day · ${DateFormat('h:mm a').format(due)}' : day;
}

/// Dashboard row. Swipe right to complete (or un-complete), swipe left to
/// delete; both offer Undo. Tap opens [EditAssignmentView] with a container
/// transform.
class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.read<AssignmentStore>();

    return Dismissible(
      key: ValueKey('dismiss-${assignment.id}'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        icon: assignment.completed ? Icons.undo : Icons.check_circle_outline,
        label: assignment.completed ? 'Mark not done' : 'Complete',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.delete_outline,
        label: 'Delete',
      ),
      onDismissed: (direction) => direction == DismissDirection.startToEnd
          ? _toggleWithUndo(context, store)
          : _deleteWithUndo(context, store),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: OpenContainer(
          closedColor: scheme.surfaceContainerLow,
          openColor: scheme.surface,
          middleColor: scheme.surface,
          closedElevation: 0,
          closedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          transitionDuration: const Duration(milliseconds: 350),
          openBuilder: (context, _) => EditAssignmentView(assignment: assignment),
          // During the transform the closed card is drawn in an overlay with no
          // Material ancestor, which Checkbox/IconButton require.
          closedBuilder: (context, _) => Material(
            type: MaterialType.transparency,
            child: _CardBody(assignment: assignment, store: store),
          ),
        ),
      ),
    );
  }

  void _toggleWithUndo(BuildContext context, AssignmentStore store) {
    final messenger = ScaffoldMessenger.of(context);
    final wasCompleted = assignment.completed;
    store.toggleCompleted(assignment.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(wasCompleted ? 'Marked "${assignment.title}" not done' : 'Completed "${assignment.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.toggleCompleted(assignment.id)),
      ));
  }

  void _deleteWithUndo(BuildContext context, AssignmentStore store) {
    final messenger = ScaffoldMessenger.of(context);
    final removed = assignment;
    store.remove(removed.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${removed.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(removed)),
      ));
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.assignment, required this.store});

  final Assignment assignment;
  final AssignmentStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorIndex = context.select<AssignmentStore, int>(
      (s) => s.courseFor(assignment.courseCode)?.colorIndex ?? 0,
    );
    final details = [
      formatDue(assignment),
      if (assignment.weightPercent != null) '${_trim(assignment.weightPercent!)}%',
      if (assignment.points != null) '${assignment.points} pts',
    ].join('  •  ');
    final titleStyle = theme.textTheme.titleMedium!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Checkbox(
            value: assignment.completed,
            semanticLabel: 'Mark ${assignment.title} complete',
            onChanged: (_) => store.toggleCompleted(assignment.id),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: assignment.completed
                      ? titleStyle.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : titleStyle,
                  child: Text(assignment.title),
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
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                assignment.addedToCalendar ? Icons.event_available : Icons.calendar_month_outlined,
                key: ValueKey(assignment.addedToCalendar),
              ),
            ),
            onPressed: () => _addToCalendar(context),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCalendar(BuildContext context) async {
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

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final leading = alignment == Alignment.centerLeft;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!leading) Text(label, style: TextStyle(color: foreground)),
          if (!leading) const SizedBox(width: 8),
          Icon(icon, color: foreground),
          if (leading) const SizedBox(width: 8),
          if (leading) Text(label, style: TextStyle(color: foreground)),
        ],
      ),
    );
  }
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
