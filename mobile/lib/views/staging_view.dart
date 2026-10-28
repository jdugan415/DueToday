import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../services/api_service.dart';
import '../state/assignment_store.dart';
import '../widgets/assignment_card.dart';

/// Step 2: review what the parser found. Users fix titles and dates, swipe
/// away false positives, then save everything to the on-device store.
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

  /// What's shown and what Save stores.
  List<Assignment> get _visible =>
      _includePast ? _items : _items.where((a) => !_pastIds.contains(a.id)).toList();

  int get _hiddenPastCount => _items.where((a) => _pastIds.contains(a.id)).length;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _replace(Assignment updated) {
    setState(() {
      _items = [for (final a in _items) a.id == updated.id ? updated : a];
    });
  }

  Future<void> _pickDate(Assignment item) async {
    final now = DateTime.now();
    final initial = item.dueAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
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

  Future<void> _save() async {
    final code = Course.normalizeCode(_codeController.text);
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a course code first.')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = widget.result.warnings;
    final visible = _visible;
    final pastCount = _hiddenPastCount;
    return Scaffold(
      appBar: AppBar(title: Text('Review ${visible.length} items')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Course code'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Course name (optional)'),
                  ),
                ),
              ],
            ),
          ),
          for (final warning in warnings)
            ListTile(
              dense: true,
              leading: Icon(Icons.info_outline, color: theme.colorScheme.tertiary),
              title: Text(warning),
            ),
          if (pastCount > 0)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              elevation: 0,
              color: theme.colorScheme.secondaryContainer,
              child: SwitchListTile(
                secondary: Icon(Icons.history, color: theme.colorScheme.onSecondaryContainer),
                title: Text(
                  '$pastCount ${pastCount == 1 ? 'item is' : 'items are'} already past due',
                  style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                ),
                subtitle: Text(
                  _includePast
                      ? 'They will be saved and show up as Overdue.'
                      : 'Left out so they don\'t fill up Overdue.',
                  style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                ),
                value: _includePast,
                onChanged: (value) => setState(() => _includePast = value),
              ),
            ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nothing left to save.', textAlign: TextAlign.center),
            ),
          for (final item in visible)
            Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
              ),
              onDismissed: (_) => setState(() => _items.removeWhere((a) => a.id == item.id)),
              child: _StagingTile(
                item: item,
                isPast: _pastIds.contains(item.id),
                onTitleChanged: (title) => _replace(item.copyWith(title: title)),
                onPickDate: () => _pickDate(item),
                onPickTime: () => _pickTime(item),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: visible.isEmpty ? null : _save,
        icon: const Icon(Icons.check),
        label: Text('Save ${visible.length}'),
      ),
    );
  }
}

class _StagingTile extends StatelessWidget {
  const _StagingTile({
    required this.item,
    required this.isPast,
    required this.onTitleChanged,
    required this.onPickDate,
    required this.onPickTime,
  });

  final Assignment item;
  final bool isPast;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                PriorityBadge(priority: item.priority),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(formatDue(item)),
                ),
                if (item.dueAt != null)
                  TextButton.icon(
                    onPressed: onPickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(item.timeSpecified ? 'Change time' : 'Default 11:59 PM'),
                  ),
                const Spacer(),
                if (isPast)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Past due',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                if (item.needsReview)
                  Tooltip(
                    message: item.sourceLine ?? 'Please double-check this item',
                    child: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.tertiary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
