import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/dashboard_buckets.dart';
import '../services/export_service.dart';
import '../state/assignment_store.dart';
import '../theme.dart';
import '../widgets/assignment_card.dart';
import '../widgets/course_sheet.dart';
import '../widgets/share_dialog.dart';
import 'paste_view.dart';

/// Home screen: every saved assignment, grouped by urgency, optionally
/// filtered to one course.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  /// Selected course code, or null for all courses.
  String? _filter;

  static const Duration _fade = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AssignmentStore>();
    final courses = [...store.courses]..sort((a, b) => a.code.compareTo(b.code));
    final filter = courses.any((c) => c.code == _filter) ? _filter : null;
    final visible = filter == null ? store.assignments : store.assignmentsFor(filter);
    final buckets = DashboardBuckets.from(visible, store.now());

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
            onPressed: courses.isEmpty ? null : () => _share(context, courses, filter),
          ),
          PopupMenuButton<ExportFormat>(
            tooltip: 'Export',
            icon: const Icon(Icons.file_download_outlined),
            enabled: visible.isNotEmpty,
            onSelected: (format) => _export(context, format, courses, visible),
            itemBuilder: (context) => [
              for (final format in ExportFormat.values)
                PopupMenuItem(
                  value: format,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(format == ExportFormat.markdown ? Icons.notes : Icons.table_chart_outlined),
                    title: Text('Export as ${format.label}'),
                    subtitle: Text(filter ?? 'All courses'),
                  ),
                ),
            ],
          ),
        ],
        bottom: courses.length < 2
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _CourseFilterBar(
                  courses: courses,
                  selected: filter,
                  onSelected: (code) => setState(() => _filter = code),
                ),
              ),
      ),
      body: AnimatedSwitcher(
        duration: _fade,
        child: store.assignments.isEmpty
            ? const _EmptyState()
            : KeyedSubtree(
                key: ValueKey(filter ?? '*all*'),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (courses.length == 1) _SingleCourseHeader(course: courses.single),
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
                    if (visible.isNotEmpty) const _SwipeHint(),
                  ],
                ),
              ),
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

  Future<void> _export(
    BuildContext context,
    ExportFormat format,
    List<Course> courses,
    List<Assignment> assignments,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ExportService.share(format, courses, assignments);
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _share(BuildContext context, List<Course> courses, String? filter) async {
    final preselected = filter == null ? null : courses.firstWhere((c) => c.code == filter);
    final course = preselected ??
        (courses.length == 1
            ? courses.first
            : await showModalBottomSheet<Course>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const ListTile(title: Text('Share which course?')),
                      for (final c in courses)
                        ListTile(
                          leading: Icon(Icons.circle, color: courseColor(c.colorIndex)),
                          title: Text(c.displayName),
                          trailing: c.shareCode == null ? null : Text(c.shareCode!),
                          onTap: () => Navigator.pop(context, c),
                        ),
                    ],
                  ),
                ),
              ));
    if (course == null || !context.mounted) return;
    await ShareDialog.showExport(context, course);
  }
}

class _CourseFilterBar extends StatelessWidget {
  const _CourseFilterBar({required this.courses, required this.selected, required this.onSelected});

  final List<Course> courses;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final course in courses) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: () => showCourseSheet(context, course),
              child: ChoiceChip(
                avatar: CircleAvatar(backgroundColor: courseColor(course.colorIndex), radius: 6),
                label: Text(course.code),
                // No tooltip: Tooltip claims long-press, which opens the course sheet.
                selected: selected == course.code,
                onSelected: (isSelected) => onSelected(isSelected ? course.code : null),
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Edit course',
              icon: const Icon(Icons.tune),
              onPressed: () => showCourseSheet(context, courses.firstWhere((c) => c.code == selected)),
            ),
          ],
        ],
      ),
    );
  }
}

/// With one course there's nothing to filter, but it still needs a way into
/// its settings.
class _SingleCourseHeader extends StatelessWidget {
  const _SingleCourseHeader({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(backgroundColor: courseColor(course.colorIndex), radius: 8),
      title: Text(course.displayName),
      trailing: IconButton(
        tooltip: 'Edit course',
        icon: const Icon(Icons.tune),
        onPressed: () => showCourseSheet(context, course),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Text(
        'Swipe right to complete · swipe left to delete · tap to edit',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
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
