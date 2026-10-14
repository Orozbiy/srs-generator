import 'srs_config.dart';

/// Сакталган бир СРС жөнүндө маалымат.
class SrsRecord {
  final String id;
  final SrsConfig config;
  final DateTime createdAt;
  final String folder;
  final String pdfPath;
  final String docxPath;
  final String contentPath;
  final int charCount;
  final int diagramCount;

  /// Жасалган PDFтин чыныгы барак саны (эски жазууларда 0).
  final int pages;

  const SrsRecord({
    required this.id,
    required this.config,
    required this.createdAt,
    required this.folder,
    required this.pdfPath,
    required this.docxPath,
    required this.contentPath,
    required this.charCount,
    required this.diagramCount,
    this.pages = 0,
  });

  String get topic => config.topic;

  Map<String, dynamic> toJson() => {
        'id': id,
        'config': config.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'folder': folder,
        'pdfPath': pdfPath,
        'docxPath': docxPath,
        'contentPath': contentPath,
        'charCount': charCount,
        'diagramCount': diagramCount,
        'pages': pages,
      };

  factory SrsRecord.fromJson(Map<String, dynamic> j) => SrsRecord(
        id: (j['id'] ?? '') as String,
        config: SrsConfig.fromJson(
            Map<String, dynamic>.from(j['config'] as Map? ?? {})),
        createdAt:
            DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime.now(),
        folder: (j['folder'] ?? '') as String,
        pdfPath: (j['pdfPath'] ?? '') as String,
        docxPath: (j['docxPath'] ?? '') as String,
        contentPath: (j['contentPath'] ?? '') as String,
        charCount: (j['charCount'] ?? 0) as int,
        diagramCount: (j['diagramCount'] ?? 0) as int,
        pages: (j['pages'] ?? 0) as int,
      );
}
