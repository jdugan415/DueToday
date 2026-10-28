import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/share_code.dart';
import '../services/api_service.dart';
import '../state/assignment_store.dart';

/// Class-code sharing: one student publishes a parsed course and gets a
/// 5-character code; classmates type the code to import the same schedule.
class ShareDialog {
  ShareDialog._();

  static Future<void> showExport(BuildContext context, Course course) =>
      showDialog<void>(context: context, builder: (_) => _ExportDialog(course: course));

  static Future<void> showImport(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _ImportDialog());
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.course});

  final Course course;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  String? _code;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _code = widget.course.shareCode;
    if (_code == null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  Future<void> _generate() async {
    final api = context.read<ApiService>();
    final store = context.read<AssignmentStore>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await api.shareCourse(widget.course, store.assignmentsFor(widget.course.code));
      await store.setShareCode(widget.course.code, code);
      if (!mounted) return;
      setState(() => _code = code);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(String text, String confirmation) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return AlertDialog(
      title: Text('Share ${widget.course.code}'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (code != null) ...[
              const Text('Classmates can enter this code to import the schedule:'),
              const SizedBox(height: 16),
              SelectableText(
                code,
                style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 8),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Copy calendar link'),
                onPressed: () => _copy(
                  context.read<ApiService>().calendarFeedUrl(code),
                  'Calendar link copied. In Google Calendar, add it under Other calendars → From URL.',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_loading)
          TextButton(
            onPressed: _generate,
            child: Text(code == null ? 'Retry' : 'New code'),
          ),
        if (code != null && !_loading)
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () => _copy(code, 'Copied $code'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final api = context.read<ApiService>();
    final store = context.read<AssignmentStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shared = await api.importCourse(_controller.text);
      await store.addAll(shared.course, shared.assignments);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${shared.assignments.length} items for ${shared.course.code}'),
      ));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.statusCode == 404 ? 'No class found with that code.' : error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = ShareCode.isValid(_controller.text);
    return AlertDialog(
      title: const Text('Import class code'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: ShareCode.length,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          const UpperCaseTextFormatter(),
        ],
        decoration: InputDecoration(hintText: 'ABC23', errorText: _error),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) {
          if (valid && !_loading) _import();
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid && !_loading ? _import : null,
          child: _loading
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Import'),
        ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
