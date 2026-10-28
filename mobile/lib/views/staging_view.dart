import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../services/api_service.dart';
import '../state/assignment_store.dart';
import '../theme/app_theme.dart';
import '../widgets/assignment_card.dart';

/// Step 2: triage what the parser found. Users set the course once, fix
/// titles and dates inline, discard false positives, then confirm.
class StagingView extends StatefulWidget {
  const StagingView({super.key, required this.result});

  final ParseResult result;

  @override
  State<StagingView> createState() => _StagingViewState();
}

class _StagingViewState extends State<StagingView> {
  late final TextEditingController _codeController;
  final _nameController = TextEditingController();
  late List<Assignment> _items;

  /// Items already due when the screen opened. Fixed at open time so editing
  /// a date doesn't make an item vanish mid-review.
  late final Set<String> _pastIds;

  /// Mid-semester imports would otherwise flood Overdue with work the student
  /// already finished, so past items are left out unless the user opts in.
  late bool _includePast;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.result.courseCode);
    _items = List.of(widget.result.assignments);
    final now = context.read<AssignmentStore>().now();
    _pastIds = {
      for (final a in _items)
        if (a.dueAt != null && a.dueAt!.isBefore(now)) a.id,
    };
    // An old syllabus with nothing upcoming: hiding everything would be confusing.
    _includePast = _items.every((a) => _pastIds.contains(a.id));
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// What's shown and what Confirm stores.
  List<Assignment> get _visible =>
      _includePast ? _items : _items.where((a) => !_pastIds.contains(a.id)).toList();

  int get _pastCount => _items.where((a) => _pastIds.contains(a.id)).length;

  void _replace(Assignment updated) {
    setState(() {
      _items = [for (final a in _items) a.id == updated.id ? updated : a];
    });
  }

  void _discard(Assignment item) => setState(() => _items.removeWhere((a) => a.id == item.id));

  Future<void> _pickDate(Assignment item) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: item.dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final time = item.dueAt == null
        ? const TimeOfDay(hour: 23, minute: 59)
        : TimeOfDay.fromDateTime(item.dueAt!);
    _replace(item.copyWith(
      dueAt: DateTime(picked.year, picked.month, picked.day, time.hour, time.minute),
      confidence: 1.0,
    ));
  }

  Future<void> _pickTime(Assignment item) async {
    final due = item.dueAt;
    if (due == null) return _pickDate(item);
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(due));
    if (picked == null) return;
    _replace(item.copyWith(
      dueAt: DateTime(due.year, due.month, due.day, picked.hour, picked.minute),
      timeSpecified: true,
    ));
  }

  Future<void> _confirm() async {
    final code = Course.normalizeCode(_codeController.text);
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a course tag first.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    final navigator = Navigator.of(context);
    await context.read<AssignmentStore>().addAll(
          Course(code: code, name: name.isEmpty ? null : name),
          _visible.where((a) => a.title.trim().isNotEmpty).toList(),
        );
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _discardAll() async {
    final count = _visible.length;
    final discard = count == 0 ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard all?'),
                content: Text('The $count detected item${count == 1 ? '' : 's'} won\'t be added. '
                    'You can parse the syllabus again any time.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep reviewing')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
                ],
              ),
            ) ==
            true;
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final pastCount = _pastCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _DetectedBanner(
            count: visible.length,
            codeController: _codeController,
            nameController: _nameController,
          ),
          for (final warning in widget.result.warnings) _WarningRow(text: warning),
          if (pastCount > 0) ...[
            const SizedBox(height: 10),
            _PastItemsToggle(
              count: pastCount,
              included: _includePast,
              onChanged: (value) => setState(() => _includePast = value),
            ),
          ],
          const SizedBox(height: 6),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing left to add.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
              ),
            ),
          for (final item in visible)
            Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.only(right: 24),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: context.colors.urgent.withValues(alpha: 0.12),
                  borderRadius: AppRadius.cardAll,
                ),
                child: Icon(Icons.delete_outline_rounded, color: context.colors.urgent),
              ),
              onDismissed: (_) => _discard(item),
              child: _StagingCard(
                item: item,
                isPast: _pastIds.contains(item.id),
                onTitleChanged: (title) => _replace(item.copyWith(title: title)),
                onPickDate: () => _pickDate(item),
                onPickTime: () => _pickTime(item),
                onDiscard: () => _discard(item),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _BottomDock(
        count: visible.length,
        onDiscardAll: _discardAll,
        onConfirm: visible.isEmpty ? null : _confirm,
      ),
    );
  }
}

class _DetectedBanner extends StatelessWidget {
  const _DetectedBanner({required this.count, required this.codeController, required this.nameController});

  final int count;
  final TextEditingController codeController;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primaryContainer, colors.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.auto_awesome_rounded, size: 18, color: theme.colorScheme.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'Assignment' : 'Assignments'} Detected',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Set the course once, it applies to every item. Tap a date or time to change it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          // Stacked, not side by side: course codes like "MATH 2057" need the
          // full width on narrow phones.
          TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Course tag (applies to all items)',
              prefixIcon: Icon(Icons.sell_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Course name (optional)'),
          ),
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _PastItemsToggle extends StatelessWidget {
  const _PastItemsToggle({required this.count, required this.included, required this.onChanged});

  final int count;
  final bool included;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A Material (not a colored Container) so the tile's ink ripple is visible.
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: colors.border)),
      child: SwitchListTile(
        secondary: Icon(Icons.history_rounded, color: colors.textSecondary),
        title: Text(
          '$count ${count == 1 ? 'item is' : 'items are'} already past due',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          included ? 'They will be saved and show up as Overdue.' : 'Left out so they don\'t fill up Overdue.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: included,
        onChanged: onChanged,
      ),
    );
  }
}

class _StagingCard extends StatelessWidget {
  const _StagingCard({
    required this.item,
    required this.isPast,
    required this.onTitleChanged,
    required this.onPickDate,
    required this.onPickTime,
    required this.onDiscard,
  });

  final Assignment item;
  final bool isPast;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final due = item.dueAt;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.title,
                    onChanged: onTitleChanged,
                    style: theme.textTheme.titleMedium,
                    decoration: const InputDecoration(
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                if (item.needsReview)
                  Tooltip(
                    message: item.sourceLine ?? 'Please double-check this item',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.error_outline_rounded, size: 18, color: colors.warning),
                    ),
                  ),
                IconButton(
                  tooltip: 'Discard',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.textSecondary),
                  onPressed: onDiscard,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _PickerChip(
                  icon: Icons.event_rounded,
                  label: due == null ? 'Set date' : DateFormat('MMM d, y').format(due),
                  emphasize: due == null,
                  onTap: onPickDate,
                ),
                if (due != null)
                  _PickerChip(
                    icon: Icons.schedule_rounded,
                    label: DateFormat('h:mm a').format(due),
                    onTap: onPickTime,
                  ),
                PriorityBadge(priority: item.priority),
                if (isPast)
                  Text('PAST DUE', style: theme.textTheme.labelSmall?.copyWith(color: colors.urgent)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tap-to-pick chip: `[ 📅 Nov 12, 2026 ]`, `[ ⏰ 11:59 PM ]`.
class _PickerChip extends StatelessWidget {
  const _PickerChip({required this.icon, required this.label, required this.onTap, this.emphasize = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final fg = emphasize ? scheme.onPrimaryContainer : colors.textPrimary;
    return Material(
      color: emphasize ? scheme.primaryContainer : colors.fieldFill,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: emphasize ? fg : colors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted dock pinned above the system navigation bar.
class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.count, required this.onDiscardAll, required this.onConfirm});

  final int count;
  final VoidCallback onDiscardAll;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.86),
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(onPressed: onDiscardAll, child: const Text('Discard All')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirm,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              'Confirm & Add All ($count)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
