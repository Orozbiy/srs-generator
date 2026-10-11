import 'package:flutter/material.dart';

import '../models/doc_block.dart';
import '../models/srs_config.dart';
import '../models/srs_record.dart';
import '../services/library_service.dart';
import '../services/markdown_parser.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

/// PDF/Word жасаардан мурун текстти окуп, оңдоо экраны.
class EditorScreen extends StatefulWidget {
  final SrsConfig config;
  final AuthorInfo author;
  final String content;
  final SrsRecord? existing;

  const EditorScreen({
    super.key,
    required this.config,
    required this.author,
    required this.content,
    this.existing,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.content.trim());
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<DocBlock> get _blocks => MarkdownParser.parse(_ctrl.text);

  Future<void> _export() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _status = 'Даярдалып жатат...';
    });
    try {
      void progress(String s) {
        if (mounted) setState(() => _status = s);
      }

      final old = widget.existing;
      if (old != null) {
        // Бар СРСти жаңыртуу — натыйжа бетине кайтабыз
        final updated = await LibraryService.update(
          record: old,
          author: widget.author,
          content: _ctrl.text,
          onProgress: progress,
        );
        if (!mounted) return;
        Navigator.pop(context, updated);
        return;
      }
      final record = await LibraryService.save(
        config: widget.config,
        author: widget.author,
        content: _ctrl.text,
        onProgress: progress,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ResultScreen(record: record)),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: AppTheme.error, size: 36),
          title: const Text('Сактоодо ката'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: SelectableText('$e')),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Жабуу')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    final diagrams =
        blocks.where((b) => b.type == BlockType.diagram).length;
    final tables = blocks.where((b) => b.type == BlockType.table).length;
    final formulas = blocks.where((b) => b.type == BlockType.formula).length;
    final words = _ctrl.text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'СРСти өзгөртүү' : 'Текстти текшерүү'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _export,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: Text(_saving
                  ? 'Сакталып жатат'
                  : widget.existing != null
                      ? 'Сактоо'
                      : 'PDF + Word жасоо'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _stat(Icons.subject_outlined, '$words сөз'),
                      _stat(Icons.functions_outlined, '$formulas формула'),
                      _stat(Icons.insights_outlined, '$diagrams сүрөт'),
                      _stat(Icons.table_chart_outlined, '$tables таблица'),
                      if (_saving)
                        Text(_status,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppTheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.line),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.6, color: AppTheme.ink),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'СРСтин тексти...',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Кеңеш: ## менен башталган сап — бөлүмдүн аталышы, '
                  r'$$...$$ — формула, ```chart{...}``` — график.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.muted),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w600)),
        ],
      );
}
