import 'dart:convert';

import '../models/diagram_spec.dart';
import '../models/doc_block.dart';
import '../models/srs_config.dart';
import 'latex_text.dart';

/// AI кайтарган markdown текстти PDF жана Word экөө тең колдоно турган
/// блокторго бөлөт.
class MarkdownParser {
  /// [lang] берилсе, сүрөттөрдүн жазуулары «1-сүрөт», «2-сүрөт» деп
  /// кезеги менен номерленет.
  static List<DocBlock> parse(String content,
      {bool markFormulas = false, Language? lang}) {
    final out = _parse(content, markFormulas, <String>{});
    _numberFigures(out, lang);
    return out;
  }

  /// Бир эле маалыматтан жасалган сүрөт эки жолу кирип калбашы үчүн
  /// ар бир диаграмманын «изи» сакталат.
  static String _signature(DiagramSpec spec) {
    final data = Map<String, dynamic>.from(spec.data)
      ..remove('caption')
      ..remove('title');
    return '${spec.kind.index}|${jsonEncode(data)}';
  }

  static final RegExp _figurePrefix = RegExp(
    r'^\s*(?:\d+\s*[-–—.]?\s*(?:сүрөтү|сүрөт|сурот|сурет)'
    r'|(?:сүрөт|рисунок|рис|figure|fig)\.?\s*\d+)\s*[.:)\-–—]*\s*',
    caseSensitive: false,
    unicode: true,
  );

  static String _figureLabel(int n, Language? lang) {
    switch (lang) {
      case Language.russian:
        return 'Рисунок $n.';
      case Language.english:
        return 'Figure $n.';
      default:
        return '$n-сүрөт.';
    }
  }

  static void _numberFigures(List<DocBlock> blocks, Language? lang) {
    if (lang == null) return;
    var n = 0;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final spec = b.diagram;
      if (b.type != BlockType.diagram || spec == null) continue;
      n++;
      var rest = spec.caption.replaceFirst(_figurePrefix, '').trim();
      if (rest.isEmpty) rest = spec.title.trim();
      final label = _figureLabel(n, lang);
      blocks[i] = DocBlock(
        BlockType.diagram,
        b.text,
        diagram: DiagramSpec(
          kind: spec.kind,
          title: spec.title,
          caption: rest.isEmpty ? label : '$label $rest',
          data: spec.data,
        ),
      );
    }
  }

  static List<DocBlock> _parse(
      String content, bool markFormulas, Set<String> seen) {
    String inl(String t) => LatexText.inline(t, mark: markFormulas);
    final out = <DocBlock>[];
    final raw = content.split('\n');
    String lastHeading = '';

    String key(String t) => t
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wа-яёөүңґ ]', unicode: true), '')
        .trim();

    void addHeading(BlockType type, String text) {
      final k = key(text);
      if (k.isEmpty) return;
      if (k == lastHeading) return; // аталыш эки жолу жазылып калбасын
      lastHeading = k;
      out.add(DocBlock(type, text));
    }

    bool isOpenMath(String t) => t == r'$$' || t == r'\[';
    bool isCloseMath(String t) => t == r'$$' || t == r'\]';

    for (var i = 0; i < raw.length; i++) {
      final line = raw[i].trim();

      // ```chart / ```circuit / ```block
      if (line.startsWith('```')) {
        final fence = line.substring(3).trim();
        final kind = DiagramSpec.kindOf(fence);
        final buf = <String>[];
        var j = i + 1;
        while (j < raw.length && !raw[j].trim().startsWith('```')) {
          buf.add(raw[j]);
          j++;
        }
        i = j;
        if (kind != null) {
          final spec = DiagramSpec.tryParse(kind, buf.join('\n'));
          if (spec != null && seen.add(_signature(spec))) {
            out.add(DocBlock(BlockType.diagram, spec.title, diagram: spec));
          }
        } else {
          // Башка код блогу. Ичинде таблица же кадимки текст болсо — аны
          // кайра markdown катары талдайбыз (чийки "|" саптар көрүнбөшү үчүн).
          final body = buf.join('\n');
          final hasTable = buf.any((b) => _isTableRow(b.trim()));
          final prose = buf.any((b) => b.trim().split(RegExp(r'\s+')).length > 5);
          if (hasTable || prose) {
            out.addAll(_parse(body.replaceAll('`', ''), markFormulas, seen));
          } else {
            for (final b in buf) {
              final t = b.trim();
              if (t.isEmpty) continue;
              out.add(
                  DocBlock(BlockType.formula, LatexText.toPlain(_stripDollars(t))));
            }
          }
        }
        continue;
      }

      // Модель кээде ``` белгисиз эле JSON жазат — аны да таанып алабыз.
      // JSON API тарабынан кыркылып калса да (finish_reason: length),
      // чийки JSON текст катары көрүнбөшү үчүн бул блок ар дайым өткөрүлүп
      // жиберилет (diagram катары таанылса — сүрөт, болбосо — жөн эле ташталат).
      if (line.startsWith('{')) {
        final buf = StringBuffer();
        var depth = 0;
        var j = i;
        var closed = false;
        while (j < raw.length && j - i < 400) {
          buf.writeln(raw[j]);
          for (final ch in raw[j].split('')) {
            if (ch == '{') depth++;
            if (ch == '}') depth--;
          }
          if (depth <= 0 && j > i) {
            closed = true;
            break;
          }
          j++;
        }
        if (closed) {
          final spec = _guessSpec(buf.toString());
          if (spec != null && seen.add(_signature(spec))) {
            out.add(DocBlock(BlockType.diagram, spec.title, diagram: spec));
          }
          i = j;
          continue;
        } else if (_looksLikeJsonFragment(buf.toString())) {
          // Кыркылган/бузулган JSON — тигине чейинки саптарды таштап кетебиз
          i = j;
          continue;
        }
      }

      // Көп саптуу формула блогу
      if (isOpenMath(line)) {
        final buf = <String>[];
        var j = i + 1;
        while (j < raw.length && !isCloseMath(raw[j].trim())) {
          final t = raw[j].trim();
          if (t.isNotEmpty) buf.add(t);
          j++;
        }
        i = j;
        if (buf.isNotEmpty) {
          out.add(DocBlock(BlockType.formula, LatexText.toPlain(buf.join(' '))));
        }
        continue;
      }

      // Markdown таблица
      if (_isTableRow(line)) {
        final rows = <List<String>>[];
        var j = i;
        while (j < raw.length && _isTableRow(raw[j].trim())) {
          final cells = _tableCells(raw[j].trim(), markFormulas);
          if (!_isSeparatorRow(cells)) rows.add(cells);
          j++;
        }
        i = j - 1;
        if (rows.isNotEmpty) {
          out.add(DocBlock(BlockType.table, '', rows: rows));
          continue;
        }
      }

      if (line.isEmpty) {
        out.add(const DocBlock(BlockType.spacer, ''));
      } else if (line.startsWith('#### ')) {
        addHeading(BlockType.h3, inl(line.substring(5)));
      } else if (line.startsWith('### ')) {
        addHeading(BlockType.h3, inl(line.substring(4)));
      } else if (line.startsWith('## ')) {
        addHeading(BlockType.h2, inl(line.substring(3)));
      } else if (line.startsWith('# ')) {
        addHeading(BlockType.h1, inl(line.substring(2)));
      } else if (line.length > 4 &&
          line.startsWith(r'$$') &&
          line.endsWith(r'$$')) {
        out.add(DocBlock(BlockType.formula,
            LatexText.toPlain(line.substring(2, line.length - 2))));
      } else if (line.length > 4 &&
          line.startsWith(r'\[') &&
          line.endsWith(r'\]')) {
        out.add(DocBlock(BlockType.formula,
            LatexText.toPlain(line.substring(2, line.length - 2))));
      } else if (line.length > 2 &&
          line.startsWith(r'$') &&
          line.endsWith(r'$') &&
          !line.substring(1, line.length - 1).contains(r'$')) {
        out.add(DocBlock(BlockType.formula,
            LatexText.toPlain(line.substring(1, line.length - 1))));
      } else if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('• ')) {
        out.add(DocBlock(BlockType.bullet, inl(line.substring(2))));
      } else if (RegExp(r'^\d+[.)]\s').hasMatch(line)) {
        final m = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(line)!;
        out.add(DocBlock(BlockType.numbered, inl(m.group(2)!),
            marker: '${m.group(1)}.'));
      } else if (line.length > 4 &&
          line.startsWith('**') &&
          line.endsWith('**')) {
        addHeading(BlockType.h3, inl(line));
      } else if (RegExp(r'^[-*_]{3,}$').hasMatch(line)) {
        out.add(const DocBlock(BlockType.spacer, ''));
      } else {
        out.add(DocBlock(BlockType.paragraph, inl(line)));
      }
    }

    while (out.isNotEmpty && out.last.type == BlockType.spacer) {
      out.removeLast();
    }
    return out;
  }

  static String _stripDollars(String t) {
    var s = t;
    while (s.startsWith(r'$')) {
      s = s.substring(1);
    }
    while (s.endsWith(r'$')) {
      s = s.substring(0, s.length - 1);
    }
    return s.trim();
  }

  static bool _looksLikeJsonFragment(String body) {
    final lines = body.trim().split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return false;
    final jsonish = RegExp(
        r'^[\{\}\[\],]*\s*("[\wА-Яа-яЁёӨөҮүҢңҐґ ./_-]+"\s*:.*)?[\{\}\[\],]*,?\s*$',
        unicode: true);
    final total = lines.length;
    final matching = lines.where((l) => jsonish.hasMatch(l.trim())).length;
    return total > 0 && matching / total > 0.6;
  }

  static DiagramSpec? _guessSpec(String body) {
    try {
      final decoded = jsonDecode(body.trim());
      if (decoded is! Map) return null;
      DiagramKind? kind;
      if (decoded['series'] is List) {
        kind = DiagramKind.chart;
      } else if (decoded['elements'] is List) {
        kind = DiagramKind.circuit;
      } else if (decoded['nodes'] is List || decoded['steps'] is List) {
        kind = DiagramKind.block;
      }
      if (kind == null) return null;
      return DiagramSpec.tryParse(kind, body);
    } catch (_) {
      return null;
    }
  }

  // Акыркы "|" белгиси унутулуп калса да (AI-дин кетирген каталары),
  // сап баары бир таблица сабы катары таанылып, чийки текст болуп
  // экранга чыкпашы үчүн endsWith талабы алынып салынды.
  static bool _isTableRow(String line) =>
      line.startsWith('|') && '|'.allMatches(line).length >= 2;

  static List<String> _tableCells(String line, bool mark) {
    var inner = line;
    if (inner.startsWith('|')) inner = inner.substring(1);
    if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
    return inner.split('|').map((c) => LatexText.inline(c.trim(), mark: mark)).toList();
  }

  static bool _isSeparatorRow(List<String> cells) =>
      cells.isNotEmpty &&
      cells.every(
          (c) => RegExp(r'^:?-{2,}:?$').hasMatch(c.replaceAll(' ', '')));
}
