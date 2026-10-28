import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../state/assignment_store.dart';
import '../theme.dart';
import '../widgets/assignment_card.dart';

/// Full editor for a saved assignment. Opened from a dashboard card with a
/// Material container transform (see AssignmentCard).
class EditAssignmentView extends StatefulWidget {
  const EditAssignmentView({super.key, required this.assignment});

  final Assignment assignment;

  @override
  State<EditAssignmentView> createState() => _EditAssignmentViewState();
}

class _EditAssignmentViewState extends State<EditAssignmentView> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime? _dueAt;
  late bool _timeSpecified;
  late Priority _priority;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    _title = TextEditingController(text: a.title);
    _notes = TextEditingController(text: a.notes ?? '');
    _dueAt = a.dueAt;
    _timeSpecified = a.timeSpecified;
    _priority = a.priority;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _dueAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final time = current == null ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay.fromDateTime(current);
    setState(() => _dueAt = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute));
  }

  Future<void> _pickTime() async {
    final current = _dueAt;
    if (current == null) return _pickDate();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(current.year, current.month, current.day, picked.hour, picked.minute);
      _timeSpecified = true;
    });
  }

  Future<void> _save() async {
    final store = context.read<AssignmentStore>();
    final navigator = Navigator.of(context);
    final notes = _notes.text.trim();
    await store.update(widget.assignment.copyWith(
      title: _title.text.trim(),
      dueAt: _dueAt,
      clearDueAt: _dueAt == null,
      timeSpecified: _timeSpecified,
      priority: _priority,
      notes: notes.isEmpty ? null : notes,
      clearNotes: notes.isEmpty,
      confidence: 1.0,
    ));
    navigator.pop();
  }

  Future<void> _delete() async {
    final store = context.read<AssignmentStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final original = widget.assignment;
    await store.remove(original.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted "${original.title}"'),
      action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(original)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorIndex = context.select<AssignmentStore, int>(
      (s) => s.courseFor(widget.assignment.courseCode)?.colorIndex ?? 0,
    );
    final due = _dueAt;
    final preview = widget.assignment.copyWith(dueAt: due, clearDueAt: due == null, timeSpecified: _timeSpecified);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit assignment'),
        actions: [
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _canSave ? _save : null, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CourseBadge(code: widget.assignment.courseCode, color: courseColor(colorIndex)),
              const SizedBox(width: 8),
              Text(toBeginningOfSentenceCase(widget.assignment.taskType), style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text('Due', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(due == null ? 'Set date' : formatDue(preview.copyWith(timeSpecified: false))),
              ),
              if (due != null)
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(DateFormat('h:mm a').format(due)),
                ),
              if (due != null)
                TextButton.icon(
                  onPressed: () => setState(() => _dueAt = null),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Priority', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<Priority>(
            segments: const [
              ButtonSegment(value: Priority.high, label: Text('High'), icon: Icon(Icons.priority_high)),
              ButtonSegment(value: Priority.medium, label: Text('Medium')),
              ButtonSegment(value: Priority.low, label: Text('Low')),
            ],
            selected: {_priority},
            onSelectionChanged: (selection) => setState(() => _priority = selection.first),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Rubric link, room number, what to bring…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (widget.assignment.sourceLine != null) ...[
            const SizedBox(height: 24),
            Text('From syllabus', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(widget.assignment.sourceLine!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
