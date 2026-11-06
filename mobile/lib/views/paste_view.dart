import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../state/assignment_store.dart';
import 'staging_view.dart';

const String sampleSchedule = '''CSC 4330 - Software Systems Development
Week 1 (Aug 24) Intro; Lab 0 setup due Friday
9/4  HW 1 due by 11:59 PM (5%)
Sept 16  Quiz 1 (10 pts)
Oct 7    Midterm Exam (20%)
Project Milestone 1 due October 2nd at 5 PM
Dec 9    Final Project presentation (25%)''';

typedef PickedPdf = ({String name, Uint8List bytes});

/// Opens the system document picker (Storage Access Framework). The app gets
/// one-off read access to the chosen file only, with no storage permission.
Future<PickedPdf?> pickPdfWithSystemPicker() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
  if (files.isEmpty) return null;
  final file = files.first;
  return (name: file.name, bytes: await file.readAsBytes());
}

/// Step 1: paste raw syllabus text (POST /api/parse) or upload a PDF
/// (POST /api/parse-pdf). Both continue to the same review screen.
class PasteView extends StatefulWidget {
  const PasteView({super.key, this.pickPdf = pickPdfWithSystemPicker});

  /// Injectable for tests, which can't open the platform picker.
  final Future<PickedPdf?> Function() pickPdf;

  @override
  State<PasteView> createState() => _PasteViewState();
}

class _PasteViewState extends State<PasteView> {
  final _textController = TextEditingController();
  final _codeController = TextEditingController();

  /// Non-null while a request is running; describes what's happening.
  String? _busy;
  bool _picking = false;
  String? _error;
  Future<void> Function()? _retry;

  bool get _loading => _busy != null || _picking;

  @override
  void dispose() {
    _textController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    // Reading the clipboard needs no permission; Android 12+ shows a toast.
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _textController.text = text;
  }

  Future<void> _parseText() async {
    if (_loading) return;
    final raw = _textController.text.trim();
    if (raw.isEmpty) return;
    final api = context.read<ApiService>();
    final today = context.read<AssignmentStore>().now();
    await _run(
      'Parsing schedule…',
      () => api.parseSyllabus(raw, courseCode: _codeController.text, today: today),
    );
  }

  Future<void> _uploadPdf() async {
    if (_loading) return;
    final api = context.read<ApiService>();
    final today = context.read<AssignmentStore>().now();
    final messenger = ScaffoldMessenger.of(context);

    final PickedPdf? picked;
    setState(() => _picking = true);
    try {
      picked = await widget.pickPdf();
    } on PlatformException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the file: ${error.message ?? error.code}')));
      return;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (picked == null || !mounted) return; // user backed out of the picker

    if (picked.bytes.length > ApiService.maxPdfBytes) {
      messenger.showSnackBar(const SnackBar(
        content: Text('That PDF is larger than 10 MB. Try exporting just the schedule pages.'),
      ));
      return;
    }
    await _run(
      'Reading ${picked.name}…',
      () => api.parseSyllabusPdf(
        bytes: picked!.bytes,
        filename: picked.name,
        courseCode: _codeController.text,
        today: today,
      ),
    );
  }

  /// Shows progress while [request] runs, then opens the review screen.
  Future<void> _run(String status, Future<ParseResult> Function() request) async {
    if (_loading || !mounted) return;
    setState(() {
      _busy = status;
      _error = null;
      _retry = null;
    });
    try {
      final result = await request();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StagingView(result: result)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _retry = status == 'Parsing schedule…' ? _parseText : () => _run(status, request);
      });
    } finally {
      if (mounted && _busy != null) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add syllabus'),
        actions: [
          IconButton(
            tooltip: 'Paste from clipboard',
            icon: const Icon(Icons.content_paste),
            onPressed: _loading ? null : _pasteFromClipboard,
          ),
          IconButton(
            tooltip: 'Load sample schedule',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _loading ? null : () => _textController.text = sampleSchedule,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _loading ? const LinearProgressIndicator() : const SizedBox(height: 4),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _codeController,
                enabled: !_loading,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Course code (optional)',
                  hintText: 'Detected automatically, e.g. CSC 4330',
                ),
              ),
              const SizedBox(height: 12),
              _PdfUploadCard(busy: _busy, onChoose: _loading ? null : _uploadPdf),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        const Text('Your syllabus and course code are still here.'),
                        TextButton.icon(
                          onPressed: _loading ? null : _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: TextField(
                  controller: _textController,
                  enabled: !_loading,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Syllabus schedule',
                    hintText: 'Paste the course schedule or the whole syllabus here…',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _parseText,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Parse Schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfUploadCard extends StatelessWidget {
  const _PdfUploadCard({required this.busy, required this.onChoose});

  final String? busy;
  final VoidCallback? onChoose;

  static const Color _rose = Color(0xFFE11D48);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _rose.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: _rose, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Or upload syllabus PDF', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    busy ?? 'Supports .pdf files up to 10MB',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: onChoose, child: const Text('Choose File')),
          ],
        ),
      ),
    );
  }
}
