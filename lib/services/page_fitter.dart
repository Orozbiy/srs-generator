import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/diagram_spec.dart';
import '../models/doc_block.dart';
import '../models/handwriting_style.dart';
import '../models/srs_config.dart';
import 'markdown_parser.dart';

/// Текст канча A4 баракка батарын эсептейт жана суралган барак санына
/// ылайыкташтырат.
///
/// Мурда AIга «барак саны × 350 сөз» деп берилчү. Бирок кол жазма режиминде
/// тамгалар эки эсе чоң, ошондуктан 5 барак суралганда 15 барак чыгып калчу.
/// Бул жерде бет чындап эсептелет: шрифттин өлчөмү, саптын бийиктиги жана
/// беттин аянты боюнча.
class PageFitter {
  /// A4 бетинин текст аянты (PdfService'теги четтер менен бирдей), пункт.
  /// Туурасы: 210 - 25 - 15 = 170 мм. Бийиктиги: 297 - 20 - 20 = 257 мм.
  static const double contentW = 170 * 2.8346;
  static const double contentH = 257 * 2.8346;

  /// Бир сөздүн орточо узундугу (боштугу менен кошо).
  static const double _wordChars = 8.0;

  static bool _isHand(SrsConfig c) => c.handwriting != null;

  static double _scale(SrsConfig c) {
    final h = c.handwriting;
    if (h == null) return 1;
    // «Менин кол жазмам» — шрифт эмес, бирок өлчөмү болжол менен ушундай.
    if (h == HandwritingStyle.mine) return 1.15;
    return h.scale;
  }

  static double _lineFactor(SrsConfig c) => _isHand(c) ? 1.55 : 1.5;

  /// Бир белгинин орточо туурасы.
  static double _charW(SrsConfig c, double size) =>
      size * (_isHand(c) ? 0.46 : 0.50);

  /// Текст [width] туурасында канча пункт бийиктикти ээлейт.
  static double _textH(SrsConfig c, String text, double size, double width) {
    final perLine = math.max(8.0, width / _charW(c, size)).floor();
    final lines = math.max(1, (text.runes.length / perLine).ceil());
    return lines * size * _lineFactor(c);
  }

  /// Бир блоктун бийиктиги (пункт).
  static double blockHeight(DocBlock b, SrsConfig c) {
    final hand = _isHand(c);
    final s = _scale(c);
    switch (b.type) {
      case BlockType.h1:
        return _textH(c, b.text, hand ? 17 * s : 15, contentW) + 20;
      case BlockType.h2:
        return _textH(c, b.text, hand ? 15 * s : 13, contentW) + 16;
      case BlockType.h3:
        return _textH(c, b.text, hand ? 13 * s : 11.5, contentW) + 11;
      case BlockType.paragraph:
        return _textH(c, b.text, hand ? 12.5 * s : 11, contentW) + 3;
      case BlockType.bullet:
      case BlockType.numbered:
        return _textH(c, b.text, hand ? 12.5 * s : 11, contentW - 46) + 4;
      case BlockType.formula:
        return (hand ? 13.5 * s * 1.3 : 15.4) + (hand ? 14 : 28);
      case BlockType.table:
        final rows = b.rows ?? const <List<String>>[];
        if (rows.isEmpty) return 0;
        var cols = 1;
        for (final r in rows) {
          if (r.length > cols) cols = r.length;
        }
        final cw = math.max(40.0, contentW / cols - 12);
        var h = 16.0;
        for (final r in rows) {
          var tallest = 0.0;
          for (final cell in r) {
            final ch = _textH(c, cell, hand ? 10.5 * s : 9.5, cw);
            if (ch > tallest) tallest = ch;
          }
          h += tallest + 8;
        }
        return h;
      case BlockType.diagram:
        final spec = b.diagram;
        var body = 160.0;
        if (spec != null) {
          switch (spec.kind) {
            case DiagramKind.chart:
              body = 400 * 340 / 540;
              break;
            case DiagramKind.circuit:
              body = 220;
              break;
            case DiagramKind.block:
              body = math.min(270.0, 400 * (44 + spec.nodes.length * 64) / 520);
              break;
            case DiagramKind.image:
              body = 260;
              break;
          }
        }
        final cap = spec == null || spec.caption.isEmpty ? 0.0 : 16.0;
        return body + cap + 25;
      case BlockType.spacer:
        return 6;
    }
  }

  /// Сүрөт бетке батпай, мурунку бетти бош калтырбасын деп: сүрөттүн
  /// алдына андан кийинки абзацтарды алып келет. Блоктордун жаңы тартибин
  /// (эски индекстердин тизмеси) кайтарат. Аталыштардан аша албайт.
  static List<int> reflowOrder(List<DocBlock> blocks, SrsConfig c) {
    final n = blocks.length;
    final used = List<bool>.filled(n, false);
    final order = <int>[];
    var y = 0.0; // учурдагы беттин ээленген бийиктиги

    bool pullable(DocBlock b) =>
        b.type == BlockType.paragraph ||
        b.type == BlockType.bullet ||
        b.type == BlockType.numbered ||
        b.type == BlockType.spacer;

    void place(int i) {
      used[i] = true;
      order.add(i);
      final b = blocks[i];
      final bh = blockHeight(b, c);
      if (b.type == BlockType.diagram && y + bh > contentH) y = 0;
      y += bh;
      while (y > contentH) {
        y -= contentH;
      }
    }

    for (var i = 0; i < n; i++) {
      if (used[i]) continue;
      if (blocks[i].type == BlockType.diagram) {
        final bh = blockHeight(blocks[i], c);
        var j = i + 1;
        while (y + bh > contentH && j < n) {
          if (used[j]) {
            j++;
            continue;
          }
          if (!pullable(blocks[j])) break;
          place(j);
          j++;
        }
      }
      place(i);
    }
    return order;
  }

  /// Титул бетин кошуп эсептелген болжолдуу барак саны.
  static int estimatePages(List<DocBlock> blocks, SrsConfig c) {
    var total = 0.0;
    for (final b in blocks) {
      total += blockHeight(b, c);
    }
    if (total <= 0) return 1;
    return 1 + math.max(1, (total / contentH).ceil());
  }

  /// Бир баракка батчу болжолдуу сөз саны.
  static int wordsPerPage(SrsConfig c) {
    final size = _isHand(c) ? 12.5 * _scale(c) : 11.0;
    final lines = contentH / (size * _lineFactor(c));
    final perLine = contentW / (_charW(c, size) * _wordChars);
    // Аталыштар, формулалар жана абзац аралары үчүн ~22% калтырабыз.
    return math.max(60, (lines * perLine * 0.78).round());
  }

  /// Бүт СРСке керектүү болжолдуу сөз саны.
  /// Титул бети жана адабияттар тизмеси эсептен чыгарылат.
  static int totalWords(SrsConfig c) {
    var pages = c.pageCount.value - 1.45;
    if (pages < 1) pages = 1;
    var words = wordsPerPage(c) * pages;
    if (c.withDiagrams) words *= 0.9; // сүрөттөр да орун ээлейт
    return words.round();
  }

  // ------------------------------------------------------- текстти кыскартуу
  /// [markdown] тексттин суралган барак санына батпаган бөлүгүн кыскартат.
  ///
  /// Аталыштар, формулалар, таблицалар, сүрөттөр, тизмелер, корутунду жана
  /// адабияттар тийилбейт — негизги бөлүмдөрдүн артыкча абзацтары гана
  /// алынат. [shrinkBy] — чыныгы PDF ашып кеткен барак саны.
  static String fit(String markdown, SrsConfig config, {int shrinkBy = 0}) {
    final target = config.pageCount.value - shrinkBy;
    if (target < 2 || markdown.trim().isEmpty) return markdown;

    final chunks = _split(markdown);
    if (chunks.isEmpty) return markdown;

    final heights = <double>[
      for (final ch in chunks) _chunkHeight(ch.text, config),
    ];
    var total = 0.0;
    for (final h in heights) {
      total += h;
    }

    // Акыркы эки бөлүм (корутунду жана адабияттар) тийилбейт.
    final sections = <int>{for (final ch in chunks) ch.section}.toList()..sort();
    final protect = sections.length >= 3
        ? 2
        : sections.length == 2
            ? 1
            : 0;
    final keep = <int>{};
    for (var i = sections.length - protect; i < sections.length; i++) {
      if (i >= 0) keep.add(sections[i]);
    }

    final removed = <int>{};
    final limit = (target - 1) * contentH;
    var guard = 0;
    while (total > limit && guard++ < 500) {
      final victim = _pickVictim(chunks, removed, keep);
      if (victim < 0) break;
      removed.add(victim);
      total -= heights[victim];
    }
    if (removed.isEmpty) return markdown;

    final out = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (!removed.contains(i)) out.add(chunks[i].text);
    }
    return out.join('\n\n');
  }

  static double _chunkHeight(String text, SrsConfig c) {
    var h = 6.0;
    for (final b in MarkdownParser.parse(text)) {
      h += blockHeight(b, c);
    }
    return h;
  }

  /// Эң көп абзацы бар бөлүмдүн акыркы абзацын тандайт.
  static int _pickVictim(
      List<_Chunk> chunks, Set<int> removed, Set<int> keep) {
    final bySection = <int, List<int>>{};
    for (var i = 0; i < chunks.length; i++) {
      final ch = chunks[i];
      if (removed.contains(i) || !ch.droppable || keep.contains(ch.section)) {
        continue;
      }
      (bySection[ch.section] ??= <int>[]).add(i);
    }
    var best = -1;
    var bestCount = 1; // ар бир бөлүмдө эң кеминде бир абзац калсын
    bySection.forEach((section, list) {
      if (list.length > bestCount) {
        bestCount = list.length;
        best = list.last;
      }
    });
    return best;
  }

  static List<_Chunk> _split(String md) {
    final out = <_Chunk>[];
    final buf = <String>[];
    var section = 0;
    var inFence = false;

    void flush() {
      if (buf.isEmpty) return;
      final text = buf.join('\n');
      if (text.trim().isNotEmpty) out.add(_Chunk(text, section));
      buf.clear();
    }

    for (final line in md.split('\n')) {
      final t = line.trim();
      if (t.startsWith('```')) {
        if (!inFence) flush();
        buf.add(line);
        inFence = !inFence;
        if (!inFence) flush();
        continue;
      }
      if (inFence) {
        buf.add(line);
        continue;
      }
      if (t.isEmpty) {
        flush();
        continue;
      }
      if (t.startsWith('#')) {
        flush();
        section++;
        buf.add(line);
        flush();
        continue;
      }
      buf.add(line);
    }
    flush();
    return out;
  }

  // ---------------------------------------------------- даяр PDFти өлчөө
  /// Жасалган PDFтин чыныгы барак саны. Окулбай калса 0.
  static int countPdfPages(Uint8List bytes) {
    sf.PdfDocument? doc;
    try {
      doc = sf.PdfDocument(inputBytes: bytes);
      return doc.pages.count;
    } catch (_) {
      return 0;
    } finally {
      try {
        doc?.dispose();
      } catch (_) {
        // мааниси жок
      }
    }
  }
}

/// Markdown тексттин бир бөлүгү (бош сап менен ажыратылган).
class _Chunk {
  final String text;
  final int section;

  const _Chunk(this.text, this.section);

  /// Бул кадимки абзацпы (кыскартууга болобу)?
  bool get droppable {
    final t = text.trim();
    if (t.length < 60) return false;
    if (t.startsWith('#') ||
        t.startsWith('|') ||
        t.startsWith('```') ||
        t.startsWith(r'$$') ||
        t.startsWith(r'\[') ||
        t.startsWith('{')) {
      return false;
    }
    if (t.contains('```') || t.contains(r'$$')) return false;
    if (RegExp(r'^[-*•]\s').hasMatch(t)) return false;
    if (RegExp(r'^\d+[.)]\s').hasMatch(t)) return false;
    return true;
  }
}
