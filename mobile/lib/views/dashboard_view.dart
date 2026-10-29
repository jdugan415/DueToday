import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/dashboard_buckets.dart';
import '../services/export_service.dart';
import '../state/assignment_store.dart';
import '../theme/app_theme.dart';
import '../widgets/assignment_card.dart';
import '../widgets/course_sheet.dart';
import '../widgets/share_dialog.dart';
import 'paste_view.dart';

/// Home screen: a hero header with today's counts, course filters, and
/// assignments grouped by urgency under sticky section headers.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  /// Selected course code, or null for all courses.
  String? _filter;

  static const Duration _fade = Duration(milliseconds: 250);

  void _openPaste() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PasteView()));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AssignmentStore>();
    final colors = context.colors;
    final courses = [...store.courses]..sort((a, b) => a.code.compareTo(b.code));
    final filter = courses.any((c) => c.code == _filter) ? _filter : null;
    final visible = filter == null ? store.assignments : store.assignmentsFor(filter);
    final now = store.now();
    final buckets = DashboardBuckets.from(visible, now);
    final hasOpenWork = visible.any((a) => !a.completed);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        actions: [
          IconButton(
            tooltip: 'Import shared course',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => ShareDialog.showImport(context),
          ),
          IconButton(
            tooltip: 'Share a course',
            icon: const Icon(Icons.ios_share_rounded),
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
                    leading: Icon(format == ExportFormat.markdown ? Icons.notes_rounded : Icons.table_chart_outlined),
                    title: Text('Export as ${format.label}'),
                    subtitle: Text(filter ?? 'All courses'),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: _fade,
        child: CustomScrollView(
          key: ValueKey('${filter ?? '*all*'}|${store.assignments.isEmpty}'),
          slivers: [
            SliverToBoxAdapter(
              child: _HeroHeader(
                now: now,
                overdue: buckets.overdue.length,
                dueToday: buckets.dueToday.length,
                thisWeek: buckets.thisWeek.length,
              ),
            ),
            if (courses.isNotEmpty)
              SliverToBoxAdapter(
                child: _CourseFilterBar(
                  courses: courses,
                  selected: filter,
                  onSelected: (code) => setState(() => _filter = code),
                ),
              ),
            if (store.assignments.isEmpty || !hasOpenWork && buckets.completed.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: const _CaughtUp())
            else ...[
              ..._section(context, 'Overdue', colors.urgent, buckets.overdue),
              ..._section(context, 'Due Today', const Color(0xFFFB7185), buckets.dueToday, showWhenEmpty: true),
              ..._section(context, 'This Week', colors.warning, buckets.thisWeek, showWhenEmpty: true),
              ..._section(context, 'Later', colors.textSecondary.withValues(alpha: 0.45), buckets.later),
              ..._section(context, 'No Date', colors.border, buckets.unscheduled),
              if (buckets.completed.isNotEmpty) SliverToBoxAdapter(child: _CompletedGroup(items: buckets.completed)),
              if (visible.isNotEmpty) const SliverToBoxAdapter(child: _SwipeHint()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPaste,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Add syllabus'),
      ),
    );
  }

  /// A sliver group whose header stays pinned while its cards scroll under it.
  List<Widget> _section(
    BuildContext context,
    String title,
    Color dot,
    List<Assignment> items, {
    bool showWhenEmpty = false,
  }) {
    if (items.isEmpty && !showWhenEmpty) return const [];
    return [
      SliverMainAxisGroup(
        slivers: [
          PinnedHeaderSliver(child: _SectionHeader(title: title, dot: dot, count: items.length)),
          if (items.isEmpty)
            const SliverToBoxAdapter(child: _SectionCaughtUp())
          else
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => AssignmentCard(key: ValueKey(items[i].id), assignment: items[i]),
            ),
        ],
      ),
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
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text('Share which course?', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      for (final c in courses)
                        ListTile(
                          leading: CoursePill(code: c.code, colorIndex: c.colorIndex),
                          title: Text(c.name ?? ''),
                          trailing: c.shareCode == null
                              ? const Icon(Icons.chevron_right_rounded)
                              : Text(c.shareCode!, style: const TextStyle(fontFamily: 'monospace')),
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

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.now, required this.overdue, required this.dueToday, required this.thisWeek});

  final DateTime now;
  final int overdue;
  final int dueToday;
  final int thisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(now).toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(color: colors.textSecondary, letterSpacing: 1.4),
          ),
          const SizedBox(height: 4),
          Text('My Deadlines', style: theme.textTheme.displaySmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (overdue > 0) _SummaryPill(count: overdue, label: 'Overdue', color: colors.urgent),
              _SummaryPill(count: dueToday, label: 'Due Today', color: const Color(0xFFFB7185)),
              _SummaryPill(count: thisWeek, label: 'This Week', color: colors.warning),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.count, required this.label, required this.color});

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = count > 0;
    final fg = active ? Color.lerp(color, colors.textPrimary, 0.25)! : colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? color.withValues(alpha: 0.25) : colors.border),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$count ', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: label),
        ]),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.dot, required this.count});

  final String title;
  final Color dot;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      color: colors.background,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(title, style: text.titleSmall),
          const SizedBox(width: 8),
          if (count > 0)
            Text('$count', style: text.labelMedium?.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
                avatar: CircleAvatar(backgroundColor: courseColor(course.colorIndex), radius: 5),
                label: Text(course.code),
                // No tooltip: Tooltip claims long-press, which opens the course sheet.
                selected: selected == course.code,
                onSelected: (isSelected) => onSelected(isSelected ? course.code : null),
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Edit course',
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () => showCourseSheet(
              context,
              courses.firstWhere((c) => c.code == selected, orElse: () => courses.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whole-dashboard empty state.
class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: colors.accent.withValues(alpha: 0.15), width: 8),
            ),
            child: Icon(Icons.task_alt_rounded, size: 38, color: colors.accent),
          ),
          const SizedBox(height: 20),
          Text('All caught up!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'No upcoming deadlines on your radar',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

        ],
      ),
    );
  }
}

/// Inline empty state for a single pinned section.
class _SectionCaughtUp extends StatelessWidget {
  const _SectionCaughtUp();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: colors.border.withValues(alpha: 0.8)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: colors.success),
            const SizedBox(width: 10),
            Text('All caught up', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CompletedGroup extends StatelessWidget {
  const _CompletedGroup({required this.items});

  final List<Assignment> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        childrenPadding: EdgeInsets.zero,
        leading: Icon(Icons.task_alt_rounded, size: 18, color: colors.success),
        title: Text('Completed (${items.length})', style: Theme.of(context).textTheme.titleSmall),
        children: [for (final a in items) AssignmentCard(key: ValueKey(a.id), assignment: a)],
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Text(
        'Swipe right to complete · left to delete · tap to edit',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
