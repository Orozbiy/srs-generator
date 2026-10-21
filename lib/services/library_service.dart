import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diagram_spec.dart';
import '../models/doc_block.dart';
import '../models/srs_config.dart';
import '../models/srs_record.dart';
import 'diagram_service.dart';
import 'doc_importer.dart';
import 'docx_service.dart';
import 'markdown_parser.dart';
import 'page_fitter.dart';
import 'pdf_service.dart';

/// Жасалган СРСтерди Документтер\СРС папкасына сактайт жана тизмесин жүргүзөт.
class LibraryService {
  static const String _rootName = 'СРС';
  static const String _indexName = 'index.json';

  static Future<Directory> rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_rootName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _indexFile() async {
    final root = await rootDir();
    return File('${root.path}${Platform.pathSeparator}$_indexName');
  }

  static Future<List<SrsRecord>> load() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      final list = raw
          .whereType<Map>()
          .map((e) => SrsRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<SrsRecord> records) async {
    final file = await _indexFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(records.map((e) => e.toJson()).toList()),
    );
  }

  /// Бир жолку чийүү: блокторго бөлүп, сүрөттөрдү, PDF жана Word жасайт.
  static Future<_Rendered> _renderOnce(SrsConfig config, AuthorInfo author,
      String content, void Function(String status)? onProgress) async {
    final blocks = MarkdownParser.parse(content, lang: config.language);
    // Кол жазма режиминде PDF үчүн формулалар белгиленет (өзгөрүүсүз калышы үчүн)
    final pdfBlocks = config.handwriting == null
        ? blocks
        : MarkdownParser.parse(content,
            markFormulas: true, lang: config.language);

    onProgress?.call('Схема жана графиктер чийилип жатат...');
    final images = <int, Uint8List>{};
    for (var i = 0; i < blocks.length; i++) {
      final spec = blocks[i].diagram;
      if (spec == null) continue;
      final png = spec.kind == DiagramKind.image
          ? await DocImporter.loadPng(spec.imagePath)
          : await DiagramService.render(spec,
              hand: config.handwriting, handProfile: config.handProfile);
      if (png != null) images[i] = png;
    }

    onProgress?.call('PDF даярдалып жатат...');
    final pdfBytes = await PdfService.build(
      config: config,
      blocks: pdfBlocks,
      author: author,
      images: images,
    );

    onProgress?.call('Word файлы даярдалып жатат...');
    final docxBytes = await DocxService.build(
      config: config,
      blocks: blocks,
      author: author,
      images: images,
    );
    return _Rendered(
      pdf: pdfBytes,
      docx: docxBytes,
      images: images,
      content: content,
      pages: PageFitter.countPdfPages(pdfBytes),
    );
  }

  /// PDFти жасап, анын ЧЫНЫГЫ барак санын өлчөйт. Суралгандан ашып кетсе,
  /// текстти кыскартып, бир жолу кайра жасайт — ошондо «5 барак» дегенде
  /// 15 барак чыкпайт.
  static Future<_Rendered> _render(SrsConfig config, AuthorInfo author,
      String content, void Function(String status)? onProgress) async {
    var out = await _renderOnce(config, author, content, onProgress);
    final target = config.pageCount.value;
    // Даяр документ кыскартылбайт (asIs)
    if (!config.asIs && out.pages > target) {
      final shorter =
          PageFitter.fit(content, config, shrinkBy: out.pages - target);
      if (shorter.trim().length < content.trim().length) {
        onProgress?.call(
            'Барак саны ылайыкташтырылууда (${out.pages} → $target)...');
        out = await _renderOnce(config, author, shorter, onProgress);
      }
    }
    return out;
  }

  /// Бар СРСтин текстин өзгөртүп, ошол эле папкадагы PDF + Word + content.md
  /// файлдарын жаңыртат (жаңы жазуу кошулбайт).
  static Future<SrsRecord> update({
    required SrsRecord record,
    required AuthorInfo author,
    required String content,
    void Function(String status)? onProgress,
  }) async {
    final out = await _render(record.config, author, content, onProgress);

    try {
      await File(record.pdfPath).writeAsBytes(out.pdf);
      await File(record.docxPath).writeAsBytes(out.docx);
    } on FileSystemException {
      throw Exception(
          'Файлды жаңыртуу мүмкүн болгон жок. PDF же Word ачык болсо, аны жаап кайра сактаңыз.');
    }
    await File(record.contentPath).writeAsString(out.content);

    final updated = SrsRecord(
      id: record.id,
      config: record.config,
      createdAt: record.createdAt,
      folder: record.folder,
      pdfPath: record.pdfPath,
      docxPath: record.docxPath,
      contentPath: record.contentPath,
      charCount: out.content.length,
      diagramCount: out.images.length,
      pages: out.pages,
    );
    final records = await load();
    final i = records.indexWhere((r) => r.id == record.id);
    if (i >= 0) {
      records[i] = updated;
    } else {
      records.insert(0, updated);
    }
    await _write(records);
    return updated;
  }

  /// Текстти PDF + Word кылып сактайт жана тизмеге кошот.
  static Future<SrsRecord> save({
    required SrsConfig config,
    required AuthorInfo author,
    required String content,
    void Function(String status)? onProgress,
  }) async {
    final out = await _render(config, author, content, onProgress);
    final pdfBytes = out.pdf;
    final docxBytes = out.docx;
    final images = out.images;

    final now = DateTime.now();
    final root = await rootDir();
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(now);
    final safe = safeName(config.topic);
    var folder =
        Directory('${root.path}${Platform.pathSeparator}${stamp}_$safe');
    var attempt = 1;
    while (await folder.exists()) {
      folder = Directory(
          '${root.path}${Platform.pathSeparator}${stamp}_${safe}_$attempt');
      attempt++;
    }
    await folder.create(recursive: true);

    final base = '${folder.path}${Platform.pathSeparator}СРС_$safe';
    final pdf = File('$base.pdf');
    final docx = File('$base.docx');
    final md = File('${folder.path}${Platform.pathSeparator}content.md');

    await pdf.writeAsBytes(pdfBytes);
    await docx.writeAsBytes(docxBytes);
    await md.writeAsString(out.content);

    final record = SrsRecord(
      id: now.microsecondsSinceEpoch.toString(),
      config: config,
      createdAt: now,
      folder: folder.path,
      pdfPath: pdf.path,
      docxPath: docx.path,
      contentPath: md.path,
      charCount: out.content.length,
      diagramCount: images.length,
      pages: out.pages,
    );

    final records = await load();
    records.insert(0, record);
    await _write(records);
    return record;
  }

  static Future<void> delete(SrsRecord record,
      {bool deleteFiles = true}) async {
    if (deleteFiles) {
      try {
        final dir = Directory(record.folder);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        // файл бөгөттөлүп турса — тизмеден гана алып салабыз
      }
    }
    final records = await load();
    records.removeWhere((r) => r.id == record.id);
    await _write(records);
  }

  static Future<String?> readContent(SrsRecord record) async {
    try {
      final file = File(record.contentPath);
      if (!await file.exists()) return null;
      return file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static String safeName(String input) {
    var name = input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), '_');
    if (name.length > 50) name = name.substring(0, 50);
    if (name.isEmpty) name = 'SRS';
    return name;
  }
}

/// Бир жолку чийүүнүн натыйжасы.
class _Rendered {
  final Uint8List pdf;
  final Uint8List docx;
  final Map<int, Uint8List> images;

  /// Чындап сакталган текст (кыскартылган болушу мүмкүн).
  final String content;

  /// PDFтин чыныгы барак саны (окулбай калса 0).
  final int pages;

  const _Rendered({
    required this.pdf,
    required this.docx,
    required this.images,
    required this.content,
    required this.pages,
  });
}

/// Блокторду тышкы жерден да эсептей алуу үчүн.
List<DocBlock> parseContentBlocks(String content) =>
    MarkdownParser.parse(content);
