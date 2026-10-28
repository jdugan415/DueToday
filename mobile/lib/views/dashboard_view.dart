import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../state/assignment_store.dart';
import '../widgets/assignment_card.dart';
import '../widgets/share_dialog.dart';
import 'paste_view.dart';

/// Home screen: every saved assignment, grouped by urgency.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AssignmentStore>();
    final buckets = store.buckets();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DueToday'),
        actions: [
          IconButton(
            tooltip: 'Import class code',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => ShareDialog.showImport(context),
          ),
          IconButton(
            tooltip: 'Share a course',
            icon: const Icon(Icons.ios_share),
            onPressed: store.courses.isEmpty ? null : () => _pickCourseToShare(context, store.courses),
          ),
        ],
      ),
      body: store.assignments.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                ..._section(context, 'Overdue', buckets.overdue),
                ..._section(context, 'Due Today', buckets.dueToday, showWhenEmpty: true),
                ..._section(context, 'This Week', buckets.thisWeek, showWhenEmpty: true),
                ..._section(context, 'Later', buckets.later),
                ..._section(context, 'No Date', buckets.unscheduled),
                if (buckets.completed.isNotEmpty)
                  ExpansionTile(
                    title: Text('Completed (${buckets.completed.length})'),
                    children: [
                      for (final a in buckets.completed) AssignmentCard(key: ValueKey(a.id), assignment: a),
                    ],
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PasteView()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add syllabus'),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<Assignment> items, {
    bool showWhenEmpty = false,
  }) {
    if (items.isEmpty && !showWhenEmpty) return const [];
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          items.isEmpty ? title : '$title (${items.length})',
          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Nothing due.', style: theme.textTheme.bodySmall),
        ),
      for (final a in items) AssignmentCard(key: ValueKey(a.id), assignment: a),
    ];
  }

  Future<void> _pickCourseToShare(BuildContext context, List<Course> courses) async {
    final course = courses.length == 1
        ? courses.first
        : await showModalBottomSheet<Course>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Share which course?')),
                  for (final c in courses)
                    ListTile(
                      leading: const Icon(Icons.class_outlined),
                      title: Text(c.displayName),
                      trailing: c.shareCode == null ? null : Text(c.shareCode!),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          );
    if (course == null || !context.mounted) return;
    await ShareDialog.showExport(context, course);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No assignments yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Paste a syllabus schedule, or import a class code from a classmate.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
