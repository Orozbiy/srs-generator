import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';

import '../models/srs_config.dart';
import '../models/srs_record.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

/// Сакталган бардык СРСтер.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<SrsRecord> _records = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await LibraryService.load();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _delete(SrsRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Өчүрүлсүнбү?'),
        content: Text(
          '"${r.topic}" жана анын PDF/Word файлдары биротоло өчүрүлөт.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Жок')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Өчүрүү'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LibraryService.delete(r);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _query.trim().isEmpty
        ? _records
        : _records
            .where((r) =>
                r.topic.toLowerCase().contains(_query.toLowerCase()) ||
                r.config.subjectName
                    .toLowerCase()
                    .contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Менин СРСтерим'),
        actions: [
          IconButton(
            tooltip: 'Папканы ачуу',
            onPressed: () async {
              final dir = await LibraryService.rootDir();
              await OpenFile.open(dir.path);
            },
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Жаңылоо',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          hintText: 'Тема боюнча издөө...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? _empty()
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 30),
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _tile(list[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 54, color: AppTheme.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            const Text('Азырынча сакталган СРС жок',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Башкы беттен жаңы СРС жасаңыз',
                style: TextStyle(fontSize: 13, color: AppTheme.muted)),
          ],
        ),
      );

  Widget _tile(SrsRecord r) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ResultScreen(record: r)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(r.config.subject.icon,
                    style: const TextStyle(
                        fontSize: 20, color: AppTheme.primary)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r.config.subjectName} · ${r.config.language.code} · '
                      '${r.config.pageCount.value} барак · '
                      '${r.diagramCount} сүрөт · '
                      '${DateFormat('dd.MM.yyyy HH:mm').format(r.createdAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'PDF',
                onPressed: () => OpenFile.open(r.pdfPath),
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    color: AppTheme.error),
              ),
              IconButton(
                tooltip: 'Word',
                onPressed: () => OpenFile.open(r.docxPath),
                icon: const Icon(Icons.description_outlined,
                    color: AppTheme.primary),
              ),
              IconButton(
                tooltip: 'Өчүрүү',
                onPressed: () => _delete(r),
                icon: const Icon(Icons.delete_outline, color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
