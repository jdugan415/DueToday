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

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.result.courseCode);
    _items = List.of(widget.result.assignments);
  }

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
          _items.where((a) => a.title.trim().isNotEmpty).toList(),
        );
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = widget.result.warnings;
    return Scaffold(
      appBar: AppBar(title: Text('Review ${_items.length} items')),
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
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nothing left to save.', textAlign: TextAlign.center),
            ),
          for (final item in _items)
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
                onTitleChanged: (title) => _replace(item.copyWith(title: title)),
                onPickDate: () => _pickDate(item),
                onPickTime: () => _pickTime(item),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _items.isEmpty ? null : _save,
        icon: const Icon(Icons.check),
        label: Text('Save ${_items.length}'),
      ),
    );
  }
}

class _StagingTile extends StatelessWidget {
  const _StagingTile({
    required this.item,
    required this.onTitleChanged,
    required this.onPickDate,
    required this.onPickTime,
  });

  final Assignment item;
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
