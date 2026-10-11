import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';

import '../models/srs_config.dart';
import '../models/srs_record.dart';
import '../services/library_service.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';

class ResultScreen extends StatefulWidget {
  final SrsRecord record;

  const ResultScreen({super.key, required this.record});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late SrsRecord record = widget.record;
  int _version = 0; // PDF алдын-ала көрүүнү жаңыртуу үчүн

  Future<void> _edit(BuildContext context) async {
    final content = await LibraryService.readContent(record);
    if (!context.mounted) return;
    if (content == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('СРСтин тексти табылган жок.')),
      );
      return;
    }
    final author = await PrefsService.author();
    if (!context.mounted) return;
    final updated = await Navigator.push<SrsRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          config: record.config,
          author: author,
          content: content,
          existing: record,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        record = updated;
        _version++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Өзгөртүүлөр сакталды')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = record.config;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 20),
            SizedBox(width: 8),
            Text('СРС даяр'),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Өзгөртүү'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Басып чыгаруу',
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Башкы бет',
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.topic,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${config.subjectName} · ${config.language.label} · '
                  '${config.pageCount.label(config.language)} · '
                  '${record.diagramCount} сүрөт · '
                  '${DateFormat('dd.MM.yyyy HH:mm').format(record.createdAt)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _action(
                    icon: Icons.edit_outlined,
                    label: 'Өзгөртүү',
                    color: AppTheme.accent,
                    onTap: () => _edit(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _action(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDF ачуу',
                    color: AppTheme.error,
                    onTap: () => _open(context, record.pdfPath),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _action(
                    icon: Icons.description_outlined,
                    label: 'Word ачуу',
                    color: AppTheme.primary,
                    onTap: () => _open(context, record.docxPath),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _action(
                    icon: Icons.folder_open_outlined,
                    label: 'Папканы ачуу',
                    color: AppTheme.warning,
                    onTap: () => _open(context, record.folder),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _action(
                    icon: Icons.add_circle_outline,
                    label: 'Жаңы СРС',
                    color: AppTheme.success,
                    onTap: () =>
                        Navigator.popUntil(context, (r) => r.isFirst),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PdfPreview(
                  key: ValueKey(_version),
                  build: (_) => File(record.pdfPath).readAsBytes(),
                  allowPrinting: true,
                  allowSharing: false, // Windows'то "бөлүшүү" PDF программасы жок болсо ката берет
                  actions: [
                    PdfPreviewAction(
                      icon: const Icon(Icons.save_alt),
                      onPressed: (ctx, build, format) => _saveCopy(ctx),
                    ),
                  ],
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  loadingWidget: const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Файлды ачат. PDF/Word үчүн программа жок болсо — Проводникте көрсөтөт.
  static Future<void> _open(BuildContext context, String path) async {
    final result = await OpenFile.open(path);
    if (result.type == ResultType.done) return;

    if (Platform.isWindows && await File(path).exists()) {
      await Process.run('explorer.exe', ['/select,', path]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Бул файлды ачуучу программа жок, ошондуктан папкада көрсөтүлдү. '
                'PDFти браузерге сүйрөп ачсаңыз болот.'),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ачылбады: ${result.message}')),
      );
    }
  }

  /// PDFтин көчүрмөсүн колдонуучу тандаган жерге сактайт (бөлүшүү үчүн).
  Future<void> _saveCopy(BuildContext context) async {
    final name = record.pdfPath.split(RegExp(r'[\\/]')).last;
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'PDFти сактоо',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (target == null) return;
    final path = target.toLowerCase().endsWith('.pdf') ? target : '$target.pdf';
    try {
      await File(record.pdfPath).copy(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сакталды: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сактоо мүмкүн болгон жок: $e')),
        );
      }
    }
  }

  Future<void> _print(BuildContext context) async {
    final bytes = await File(record.pdfPath).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }
}
