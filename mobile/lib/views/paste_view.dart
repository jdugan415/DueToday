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

/// Step 1: paste raw syllabus text and send it to `POST /api/parse`.
class PasteView extends StatefulWidget {
  const PasteView({super.key});

  @override
  State<PasteView> createState() => _PasteViewState();
}

class _PasteViewState extends State<PasteView> {
  final _textController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;

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

  Future<void> _parse() async {
    final raw = _textController.text.trim();
    if (raw.isEmpty) return;
    final api = context.read<ApiService>();
    final today = context.read<AssignmentStore>().now();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      final result = await api.parseSyllabus(raw, courseCode: _codeController.text, today: today);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StagingView(result: result)),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
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
            onPressed: _pasteFromClipboard,
          ),
          IconButton(
            tooltip: 'Load sample schedule',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => _textController.text = sampleSchedule,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Course code (optional)',
                  hintText: 'Detected automatically, e.g. CSC 4330',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _textController,
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
                onPressed: _loading ? null : _parse,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: Text(_loading ? 'Parsing…' : 'Parse Schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
