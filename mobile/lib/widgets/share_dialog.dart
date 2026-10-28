import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/share_code.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';
import '../state/assignment_store.dart';
import '../theme/app_theme.dart';

const TextStyle _codeStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['RobotoMono', 'Courier New'],
  fontSize: 28,
  fontWeight: FontWeight.w700,
  letterSpacing: 8,
);

/// Class-code sharing: one student publishes a parsed course and gets a
/// 5-character code; classmates type the code to import the same schedule.
class ShareDialog {
  ShareDialog._();

  /// Bottom sheet with the course's share code (created on first open).
  static Future<void> showExport(BuildContext context, Course course) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ShareSheet(course: course),
      );

  static Future<void> showImport(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _ImportDialog());
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.course});

  final Course course;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  String? _code;
  String? _error;
  bool _loading = false;
  bool _copied = false;
  bool _exporting = false;

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
      _copied = false;
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

  Future<void> _copyCode(String code) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _copyFeedLink(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: context.read<ApiService>().calendarFeedUrl(code)));
    messenger.showSnackBar(const SnackBar(
      content: Text('Subscribe link copied. In Google Calendar: Other calendars → From URL.'),
    ));
  }

  Future<void> _exportIcs(String code) async {
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final ics = await api.fetchCalendarIcs(code);
      await ExportService.shareFile(
        content: ics,
        fileName: '${widget.course.code.replaceAll(' ', '')}-$code.ics',
        mimeType: 'text/calendar',
        subject: '${widget.course.code} deadlines',
        title: 'Export ${widget.course.code} calendar',
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final code = _code;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share ${widget.course.code}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Classmates enter this code in DueToday to import the same schedule.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorBox(message: _error!, onRetry: _generate)
            else if (code != null) ...[
              Material(
                color: colors.fieldFill,
                borderRadius: AppRadius.cardAll,
                child: InkWell(
                  borderRadius: AppRadius.cardAll,
                  onTap: () => _copyCode(code),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Column(
                      children: [
                        Semantics(
                          label: 'Share code ${code.split('').join(' ')}. Tap to copy.',
                          excludeSemantics: true,
                          child: Text(code, style: _codeStyle.copyWith(color: colors.textPrimary)),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _copied ? '✓ Copied to clipboard!' : 'Tap to copy',
                            key: ValueKey(_copied),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: _copied ? colors.success : colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _exporting ? null : () => _exportIcs(code),
                icon: _exporting
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.event_note_rounded),
                label: const Text('Export as .ics Calendar File'),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _copyFeedLink(code),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('Copy subscribe link'),
                  ),
                  TextButton(onPressed: _generate, child: const Text('New code')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.urgent.withValues(alpha: 0.08),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: colors.urgent.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
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
      HapticFeedback.mediumImpact();
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
        style: _codeStyle.copyWith(color: context.colors.textPrimary),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          const UpperCaseTextFormatter(),
        ],
        decoration: InputDecoration(hintText: 'ABC23', errorText: _error, counterText: ''),
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
