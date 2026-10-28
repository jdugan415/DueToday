import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../state/assignment_store.dart';
import '../theme.dart';

/// Bottom sheet to rename a course, change its badge color, or delete it.
Future<void> showCourseSheet(BuildContext context, Course course) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CourseSheet(course: course),
    );

class _CourseSheet extends StatefulWidget {
  const _CourseSheet({required this.course});

  final Course course;

  @override
  State<_CourseSheet> createState() => _CourseSheetState();
}

class _CourseSheetState extends State<_CourseSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.course.name ?? '');
  late int _colorIndex = widget.course.colorIndex % courseColors.length;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    await context.read<AssignmentStore>().updateCourse(
          widget.course.copyWith(name: name, clearName: name.isEmpty, colorIndex: _colorIndex),
        );
    navigator.pop();
  }

  Future<void> _delete() async {
    final store = context.read<AssignmentStore>();
    final navigator = Navigator.of(context);
    final count = store.assignmentsFor(widget.course.code).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.course.code}?'),
        content: Text('This removes the course and its $count assignment${count == 1 ? '' : 's'} '
            'from this phone. Events already added to your calendar are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.removeCourse(widget.course.code);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.course.code, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Course name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('Badge color', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < courseColors.length; i++)
                Semantics(
                  label: 'Color ${i + 1}',
                  selected: i == _colorIndex,
                  button: true,
                  child: InkResponse(
                    onTap: () => setState(() => _colorIndex = i),
                    radius: 24,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: courseColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == _colorIndex ? theme.colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: i == _colorIndex ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                label: Text('Delete course', style: TextStyle(color: theme.colorScheme.error)),
              ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
