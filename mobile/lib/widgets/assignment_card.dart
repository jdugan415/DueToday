import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/due_label.dart';
import '../services/calendar_service.dart';
import '../state/assignment_store.dart';
import '../theme/app_theme.dart';
import '../views/edit_assignment_view.dart';

String formatDue(Assignment assignment) {
  final due = assignment.dueAt;
  if (due == null) return 'No due date';
  final day = DateFormat('EEE, MMM d').format(due);
  return assignment.timeSpecified ? '$day · ${DateFormat('h:mm a').format(due)}' : day;
}

/// Dashboard card. Swipe right to complete (or un-complete), swipe left to
/// delete; both offer Undo. Tap opens [EditAssignmentView] with a container
/// transform. Items due within 24 hours get a rose accent strip.
class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.read<AssignmentStore>();

    return Dismissible(
      key: ValueKey('dismiss-${assignment.id}'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: colors.success.withValues(alpha: 0.14),
        foreground: colors.success,
        icon: assignment.completed ? Icons.undo_rounded : Icons.check_circle_rounded,
        label: assignment.completed ? 'Mark not done' : 'Complete',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: colors.urgent.withValues(alpha: 0.12),
        foreground: colors.urgent,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      onDismissed: (direction) => direction == DismissDirection.startToEnd
          ? _toggleWithUndo(context, store)
          : _deleteWithUndo(context, store),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: OpenContainer(
          closedColor: colors.surface,
          openColor: colors.background,
          middleColor: colors.surface,
          closedElevation: 0,
          openElevation: 0,
          closedShape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: hairline(context)),
          transitionDuration: const Duration(milliseconds: 350),
          openBuilder: (context, _) => EditAssignmentView(assignment: assignment),
          // During the transform the closed card is drawn in an overlay with no
          // Material ancestor, which Checkbox/InkWell require.
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
    if (!wasCompleted) HapticFeedback.mediumImpact();
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
    final colors = context.colors;
    final colorIndex = context.select<AssignmentStore, int>(
      (s) => s.courseFor(assignment.courseCode)?.colorIndex ?? courseColorIndexFor(assignment.courseCode),
    );
    final label = DueLabel.of(assignment, store.now());
    final showStrip = label.urgency == Urgency.imminent || label.urgency == Urgency.overdue;
    final titleStyle = theme.textTheme.titleMedium!;

    final meta = [
      formatDue(assignment),
      if (assignment.weightPercent != null) '${_trim(assignment.weightPercent!)}% of grade',
      if (assignment.points != null) '${assignment.points} pts',
    ].join('  ·  ');

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(showStrip ? 18 : 16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: CoursePill(code: assignment.courseCode, colorIndex: colorIndex)),
                        if (assignment.priority == Priority.high && !assignment.completed) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.flag_rounded, size: 15, color: colors.urgent, semanticLabel: 'High priority'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _UrgencyBadge(label: label),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: assignment.completed
                    ? titleStyle.copyWith(decoration: TextDecoration.lineThrough, color: colors.textSecondary)
                    : titleStyle,
                child: Text(assignment.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    assignment.weightPercent != null ? Icons.sell_outlined : Icons.schedule_rounded,
                    size: 13,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(meta, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _CalendarPill(
                    added: assignment.addedToCalendar,
                    enabled: assignment.dueAt != null,
                    onTap: () => _addToCalendar(context),
                  ),
                  const Spacer(),
                  Transform.scale(
                    scale: 1.15,
                    child: Checkbox(
                      value: assignment.completed,
                      semanticLabel: 'Mark ${assignment.title} complete',
                      onChanged: (_) {
                        if (!assignment.completed) {
                          HapticFeedback.mediumImpact();
                        } else {
                          HapticFeedback.selectionClick();
                        }
                        store.toggleCompleted(assignment.id);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showStrip)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: label.urgency == Urgency.overdue ? colors.urgent : const Color(0xFFFB7185)),
          ),
      ],
    );
  }

  Future<void> _addToCalendar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final due = assignment.dueAt;
    if (due == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Set a due date first.')));
      return;
    }
    HapticFeedback.lightImpact();
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
      messenger.showSnackBar(const SnackBar(content: Text('No calendar app found on this device.')));
    }
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
}

class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge({required this.label});

  final DueLabel label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color color, FontWeight weight) = switch (label.urgency) {
      Urgency.overdue || Urgency.imminent => (colors.urgent, FontWeight.w800),
      Urgency.soon => (colors.warning, FontWeight.w700),
      Urgency.calm => (label.text == 'Done' ? colors.success : colors.textSecondary, FontWeight.w600),
    };
    return Text(
      label.text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: weight),
    );
  }
}

class _CalendarPill extends StatelessWidget {
  const _CalendarPill({required this.added, required this.enabled, required this.onTap});

  final bool added;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final foreground = added ? colors.success : (enabled ? scheme.onPrimaryContainer : colors.textSecondary);
    final background = added
        ? colors.success.withValues(alpha: 0.12)
        : (enabled ? scheme.primaryContainer : colors.fieldFill);
    return Semantics(
      button: true,
      label: added ? 'Add to calendar again' : 'Add to calendar',
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    added ? Icons.event_available_rounded : Icons.calendar_today_rounded,
                    key: ValueKey(added),
                    size: 14,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  added ? 'In Calendar' : 'Add to Calendar',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.cardAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!leading) Text(label, style: style),
          if (!leading) const SizedBox(width: 8),
          Icon(icon, color: foreground),
          if (leading) const SizedBox(width: 8),
          if (leading) Text(label, style: style),
        ],
      ),
    );
  }
}

/// Soft rounded course tag, tinted from the course's color slot.
class CoursePill extends StatelessWidget {
  const CoursePill({super.key, required this.code, required this.colorIndex});

  final String code;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final pill = coursePillColors(colorIndex, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: pill.background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        code.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: pill.foreground),
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final Priority priority;

  @override
  Widget build(BuildContext context) {
    final style = priorityStyle(priority, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        style.label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: style.foreground),
      ),
    );
  }
}
