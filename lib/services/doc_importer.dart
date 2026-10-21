import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/doc_item.dart';
import 'document_reader.dart';

/// Даяр документтен (DOCX, PPTX ...) алынган, сүрөттөрү өз ордунда турган
/// markdown. AI колдонулбайт — токен кетпейт.
class ImportedDoc {
  final String markdown;
  final int images;
  final int skippedImages;
  final String title;

  const ImportedDoc({
    required this.markdown,
    required this.images,
    required this.skippedImages,
    required this.title,
  });
}

/// Документти түзүмү (аталыш, абзац, тизме, таблица, формула, сүрөт) менен
/// тартиби бузулбай окуйт. Сүрөттөр папкага сакталып, markdown ичинде
/// `![жазуусу](жолу)` болуп, өз ордунда турат.
class DocImporter {
  static const Set<String> _imageExt = {
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'
  };

  static Future<ImportedDoc> importFile(
      String fileName, Uint8List bytes) async {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    final base = dot < 0 ? fileName : fileName.substring(0, dot);

    List<String>? lines;
    final ctx = _Ctx();
    try {
      if (ext == 'docx') {
        lines = await _docx(bytes, ctx);
      } else if (ext == 'pptx') {
        lines = await _pptx(bytes, ctx);
      }
    } catch (_) {
      lines = null; // бузулса — жөнөкөй текст окуу менен улантабыз
    }

    if (lines == null || lines.where((l) => l.trim().isNotEmpty).isEmpty) {
      // Жөнөкөй форматтар (PDF, TXT, ...): текст гана.
      final text = await DocumentReader.read(fileName, bytes);
      lines = [
        for (final it in DocItem.split(text))
          it.isHeading ? '### ${it.text}' : it.text,
      ];
    }

    lines = _mergeCaptions(lines);
    var title = base;
    for (final l in lines) {
      final m = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(l);
      if (m != null) {
        title = m.group(1)!.trim();
        break;
      }
    }
    if (title.length > 120) title = title.substring(0, 120);
    return ImportedDoc(
      markdown: lines.join('\n'),
      images: ctx.count,
      skippedImages: ctx.skipped,
      title: title,
    );
  }

  // --------------------------------------------------------- сүрөт жүктөө
  /// Сакталган сүрөттү (png/jpg/gif/bmp/webp) PNGге айландырат.
  /// Өтө чоң болсо кичирейтет (PDF оор болбошу үчүн).
  static Future<Uint8List?> loadPng(String path, {int maxWidth = 1400}) async {
    try {
      final bytes = await File(path).readAsBytes();
      var codec = await ui.instantiateImageCodec(bytes);
      var frame = await codec.getNextFrame();
      if (frame.image.width > maxWidth) {
        frame.image.dispose();
        codec.dispose();
        codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
        frame = await codec.getNextFrame();
      }
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------ "Сүрөт 1 — ..." жазуусу
  static final RegExp _figCap = RegExp(
    r'^(?:\d+\s*[-–—.]?\s*(?:сүрөтү|сүрөт|сурот|сурет)|(?:сүрөт|рисунок|рис|figure|fig)\.?\s*\d+)',
    caseSensitive: false,
    unicode: true,
  );

  /// Сүрөттүн алдындагы же артындагы "Рисунок 1 — ..." саптарын сүрөттүн
  /// жазуусу кылат.
  static List<String> _mergeCaptions(List<String> lines) {
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final im = RegExp(r'^!\[(.*?)\]\((.+)\)$').firstMatch(l);
      if (im != null && im.group(1)!.isEmpty) {
        if (i + 1 < lines.length &&
            _figCap.hasMatch(lines[i + 1].trim()) &&
            lines[i + 1].length < 220) {
          out.add('![${lines[i + 1].trim().replaceAll(RegExp(r'[\[\]]'), '')}]'
              '(${im.group(2)})');
          i++;
          continue;
        }
      }
      out.add(l);
    }
    return out;
  }

  // ===================================================================
  //                               DOCX
  // ===================================================================
  static Future<List<String>> _docx(Uint8List bytes, _Ctx c) async {
    final zip = ZipDecoder().decodeBytes(bytes);
    c.files = {
      for (final f in zip)
        if (f.isFile) f.name: f,
    };
    final docXml = c.text('word/document.xml');
    if (docXml == null) return const [];
    c.base = 'word/';
    c.rels = c.readRels('word/_rels/document.xml.rels');
    final root = _X.parse(docXml);
    final body = root.descendants('w:body').firstOrNull;
    final out = <String>[];
    if (body != null) await _docxBody(body, c, out);
    return out;
  }

  static Future<void> _docxBody(_X node, _Ctx c, List<String> out) async {
    for (final k in node.kids) {
      switch (k.name) {
        case 'w:p':
          await _docxPara(k, c, out);
          break;
        case 'w:tbl':
          await _docxTable(k, c, out);
          break;
        case 'w:sdt':
        case 'w:sdtContent':
        case 'w:ins':
        case 'w:customXml':
          await _docxBody(k, c, out);
          break;
        case 'mc:AlternateContent':
          final ch = k.child('mc:Choice') ?? k.child('mc:Fallback');
          if (ch != null) await _docxBody(ch, c, out);
          break;
      }
    }
  }

  static int? _headingLevel(String style, int? outline) {
    final m = RegExp(r'^(heading|заголовок|title|subtitle|название|подзаголовок)\s*(\d)?$',
            caseSensitive: false, unicode: true)
        .firstMatch(style.trim());
    if (m != null) {
      final word = m.group(1)!.toLowerCase();
      if (word == 'title' || word == 'название') return 1;
      if (word == 'subtitle' || word == 'подзаголовок') return 3;
      final n = int.tryParse(m.group(2) ?? '1') ?? 1;
      return (n + 1).clamp(2, 3);
    }
    if (outline != null && outline >= 0 && outline < 9) {
      return (outline + 2).clamp(2, 3);
    }
    return null;
  }

  static Future<void> _docxPara(_X p, _Ctx c, List<String> out) async {
    final pPr = p.child('w:pPr');
    final style = pPr?.child('w:pStyle')?.attrs['w:val'] ?? '';
    final isList = pPr?.child('w:numPr') != null;
    final outline =
        int.tryParse(pPr?.child('w:outlineLvl')?.attrs['w:val'] ?? '');
    final buf = StringBuffer();
    final imgs = <String>[];
    var mathPara = false;

    Future<void> run(_X n) async {
      for (final k in n.kids) {
        switch (k.name) {
          case 'w:t':
            buf.write(k.allText);
            break;
          case 'w:tab':
          case 'w:br':
          case 'w:cr':
            buf.write(' ');
            break;
          case 'w:drawing':
          case 'w:pict':
          case 'w:object':
            for (final b in k.descendants('a:blip')) {
              final path = await c.image(b.attrs['r:embed']);
              if (path != null) imgs.add(path);
            }
            for (final b in k.descendants('v:imagedata')) {
              final path = await c.image(b.attrs['r:id']);
              if (path != null) imgs.add(path);
            }
            break;
          case 'm:oMathPara':
            mathPara = true;
            for (final m in k.children('m:oMath')) {
              buf.write(' \$${_omml(m).trim()}\$ ');
            }
            break;
          case 'm:oMath':
            buf.write(' \$${_omml(k).trim()}\$ ');
            break;
          case 'mc:AlternateContent':
            final ch = k.child('mc:Choice') ?? k.child('mc:Fallback');
            if (ch != null) await run(ch);
            break;
          case 'w:del':
          case 'w:pPr':
          case 'w:rPr':
            break;
          default:
            await run(k);
        }
      }
    }

    await run(p);
    final text = buf.toString().replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
    final level = _headingLevel(style, outline);

    if (text.isNotEmpty) {
      // Бир гана формуладан турган абзац — өзүнчө формула
      final single = text.startsWith(r'$') &&
          text.endsWith(r'$') &&
          text.length > 2 &&
          text.indexOf(r'$', 1) == text.length - 1;
      if (single && (mathPara || level == null)) {
        out.add('\$\$${text.substring(1, text.length - 1).trim()}\$\$');
      } else if (level != null) {
        out.add('${'#' * level} $text');
      } else if (isList) {
        out.add('- $text');
      } else {
        out.add(text);
      }
    }
    for (final path in imgs) {
      out.add('![]($path)');
    }
  }

  static Future<void> _docxTable(_X t, _Ctx c, List<String> out) async {
    final rows = <List<String>>[];
    final imgs = <String>[];
    for (final tr in t.children('w:tr')) {
      final cells = <String>[];
      for (final tc in tr.children('w:tc')) {
        final tmp = <String>[];
        await _docxBody(tc, c, tmp);
        final parts = <String>[];
        for (final l in tmp) {
          if (l.startsWith('![')) {
            imgs.add(l);
          } else {
            parts.add(l
                .replaceFirst(RegExp(r'^(?:#{1,3} |- )'), '')
                .replaceAll('|', '/'));
          }
        }
        cells.add(parts.join(' ').trim());
      }
      if (cells.any((e) => e.isNotEmpty)) rows.add(cells);
    }
    _emitTable(rows, out);
    out.addAll(imgs);
  }

  static void _emitTable(List<List<String>> rows, List<String> out) {
    if (rows.isEmpty) return;
    var cols = 1;
    for (final r in rows) {
      if (r.length > cols) cols = r.length;
    }
    if (rows.length == 1 && cols == 1) {
      out.add(rows.first.first);
      return;
    }
    String row(List<String> r) {
      final cells = [
        for (var i = 0; i < cols; i++) i < r.length ? r[i] : '',
      ];
      return '| ${cells.join(' | ')} |';
    }

    out.add(row(rows.first));
    out.add('|${List.filled(cols, ' --- ').join('|')}|');
    for (var i = 1; i < rows.length; i++) {
      out.add(row(rows[i]));
    }
  }

  // ---------------------------------------------- Office Math → LaTeX
  static String _ommlKids(_X? n) {
    if (n == null) return '';
    final b = StringBuffer();
    for (final k in n.kids) {
      b.write(_omml(k));
    }
    return b.toString();
  }

  static String _omml(_X n) {
    if (n.isText) return '';
    if (n.name.startsWith('m:') && n.name.endsWith('Pr')) return '';
    switch (n.name) {
      case 'm:t':
        return n.allText;
      case 'm:f':
        return '\\frac{${_ommlKids(n.child('m:num'))}}'
            '{${_ommlKids(n.child('m:den'))}}';
      case 'm:sSup':
        return '{${_ommlKids(n.child('m:e'))}}^{${_ommlKids(n.child('m:sup'))}}';
      case 'm:sSub':
        return '{${_ommlKids(n.child('m:e'))}}_{${_ommlKids(n.child('m:sub'))}}';
      case 'm:sSubSup':
        return '{${_ommlKids(n.child('m:e'))}}'
            '_{${_ommlKids(n.child('m:sub'))}}'
            '^{${_ommlKids(n.child('m:sup'))}}';
      case 'm:rad':
        final deg = _ommlKids(n.child('m:deg')).trim();
        final e = _ommlKids(n.child('m:e'));
        return deg.isEmpty || deg == '2' ? '\\sqrt{$e}' : '\\sqrt[$deg]{$e}';
      case 'm:nary':
        final chr =
            n.child('m:naryPr')?.child('m:chr')?.attrs['m:val'] ?? '∫';
        const map = {
          '∑': '\\sum',
          '∏': '\\prod',
          '∫': '\\int',
          '∮': '\\oint',
        };
        final op = map[chr] ?? chr;
        final sub = _ommlKids(n.child('m:sub'));
        final sup = _ommlKids(n.child('m:sup'));
        final e = _ommlKids(n.child('m:e'));
        return '$op${sub.isEmpty ? '' : '_{$sub}'}'
            '${sup.isEmpty ? '' : '^{$sup}'} $e';
      case 'm:d':
        final pr = n.child('m:dPr');
        final beg = pr?.child('m:begChr') != null
            ? (pr!.child('m:begChr')!.attrs['m:val'] ?? '')
            : '(';
        final end = pr?.child('m:endChr') != null
            ? (pr!.child('m:endChr')!.attrs['m:val'] ?? '')
            : ')';
        final parts = [for (final e in n.children('m:e')) _ommlKids(e)];
        return '$beg${parts.join(',')}$end';
      case 'm:func':
        return '${_ommlKids(n.child('m:fName'))} ${_ommlKids(n.child('m:e'))}';
      default:
        return _ommlKids(n);
    }
  }

  // ===================================================================
  //                               PPTX
  // ===================================================================
  static Future<List<String>> _pptx(Uint8List bytes, _Ctx c) async {
    final zip = ZipDecoder().decodeBytes(bytes);
    c.files = {
      for (final f in zip)
        if (f.isFile) f.name: f,
    };
    final slides = <int, String>{};
    for (final name in c.files.keys) {
      final m = RegExp(r'^ppt/slides/slide(\d+)\.xml$').firstMatch(name);
      if (m != null) slides[int.parse(m.group(1)!)] = name;
    }
    final order = slides.keys.toList()..sort();
    final out = <String>[];
    c.base = 'ppt/slides/';
    for (final n in order) {
      final xml = c.text(slides[n]!);
      if (xml == null) continue;
      c.rels = c.readRels('ppt/slides/_rels/slide$n.xml.rels');
      c.saved.clear();
      final tree = _X.parse(xml).descendants('p:spTree').firstOrNull;
      if (tree == null) continue;
      final title = <String>[];
      final body = <String>[];
      await _pptxShapes(tree, c, title, body);
      out.add('## ${title.isEmpty ? 'Слайд $n' : title.join(' ')}');
      out.addAll(body);
    }
    return out;
  }

  static String _aText(_X p) {
    final b = StringBuffer();
    void walk(_X n) {
      for (final k in n.kids) {
        switch (k.name) {
          case 'a:t':
            b.write(k.allText);
            break;
          case 'a:br':
            b.write(' ');
            break;
          case 'a:pPr':
          case 'a:endParaRPr':
            break;
          default:
            walk(k);
        }
      }
    }

    walk(p);
    return b.toString().replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
  }

  static Future<void> _pptxShapes(
      _X node, _Ctx c, List<String> title, List<String> body) async {
    for (final k in node.kids) {
      switch (k.name) {
        case 'p:sp':
          final ph = k.descendants('p:ph').firstOrNull;
          final type = ph?.attrs['type'] ?? '';
          if (type == 'sldNum' || type == 'ftr' || type == 'dt') break;
          final isTitle = type.toLowerCase().contains('title');
          for (final p in k.descendants('a:p')) {
            final t = _aText(p);
            if (t.isEmpty) continue;
            if (isTitle) {
              title.add(t);
            } else {
              body.add(t.length > 200 ? t : '- $t');
            }
          }
          break;
        case 'p:pic':
          final blip = k.descendants('a:blip').firstOrNull;
          final path = await c.image(blip?.attrs['r:embed']);
          if (path != null) body.add('![]($path)');
          break;
        case 'p:graphicFrame':
          final tbl = k.descendants('a:tbl').firstOrNull;
          if (tbl != null) {
            final rows = <List<String>>[];
            for (final tr in tbl.children('a:tr')) {
              rows.add([
                for (final tc in tr.children('a:tc'))
                  [for (final p in tc.descendants('a:p')) _aText(p)]
                      .where((e) => e.isNotEmpty)
                      .join(' ')
                      .replaceAll('|', '/'),
              ]);
            }
            _emitTable(rows, body);
          }
          break;
        case 'p:grpSp':
          await _pptxShapes(k, c, title, body);
          break;
        case 'mc:AlternateContent':
          final ch = k.child('mc:Choice') ?? k.child('mc:Fallback');
          if (ch != null) await _pptxShapes(ch, c, title, body);
          break;
      }
    }
  }
}

// =====================================================================
//                      Көмөкчү: контекст жана XML
// =====================================================================
class _Ctx {
  Map<String, ArchiveFile> files = {};
  String base = '';
  Map<String, String> rels = {};
  final Map<String, String?> saved = {};
  int count = 0;
  int skipped = 0;
  Directory? _dir;

  String? text(String name) {
    final f = files[name];
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  Map<String, String> readRels(String name) {
    final xml = text(name);
    final out = <String, String>{};
    if (xml == null) return out;
    for (final r in _X.parse(xml).descendants('Relationship')) {
      final id = r.attrs['Id'];
      final target = r.attrs['Target'];
      if (id == null || target == null) continue;
      if ((r.attrs['TargetMode'] ?? '') == 'External') continue;
      out[id] = target;
    }
    return out;
  }

  String _resolve(String target) {
    if (target.startsWith('/')) return target.substring(1);
    final segs = <String>[
      ...base.split('/').where((s) => s.isNotEmpty),
    ];
    for (final s in target.split('/')) {
      if (s == '..') {
        if (segs.isNotEmpty) segs.removeLast();
      } else if (s != '.' && s.isNotEmpty) {
        segs.add(s);
      }
    }
    return segs.join('/');
  }

  Future<Directory> _folder() async {
    final d = _dir;
    if (d != null) return d;
    final docs = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final dir =
        Directory('${docs.path}${sep}СРС$sep' '_imports$sep$stamp');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<String?> image(String? rid) async {
    if (rid == null) return null;
    if (saved.containsKey(rid)) return saved[rid];
    String? path;
    final target = rels[rid];
    if (target != null) {
      final f = files[_resolve(target)];
      final dot = target.lastIndexOf('.');
      final ext = dot < 0 ? '' : target.substring(dot + 1).toLowerCase();
      if (f != null && DocImporter._imageExt.contains(ext)) {
        count++;
        final dir = await _folder();
        final file = File('${dir.path}${Platform.pathSeparator}img$count.$ext');
        await file.writeAsBytes(f.content as List<int>);
        path = file.path;
      } else {
        skipped++;
      }
    }
    saved[rid] = path;
    return path;
  }
}

/// Өтө жөнөкөй XML дарагы (Office файлдары үчүн жетиштүү).
class _X {
  final String name;
  final Map<String, String> attrs;
  final List<_X> kids = [];
  final String text;

  _X(this.name, {Map<String, String>? attrs, this.text = ''})
      : attrs = attrs ?? <String, String>{};

  bool get isText => name == '#text';

  _X? child(String n) {
    for (final k in kids) {
      if (k.name == n) return k;
    }
    return null;
  }

  Iterable<_X> children(String n) => kids.where((k) => k.name == n);

  Iterable<_X> descendants(String n) sync* {
    for (final k in kids) {
      if (k.name == n) yield k;
      yield* k.descendants(n);
    }
  }

  String get allText {
    final b = StringBuffer();
    void walk(_X x) {
      if (x.isText) {
        b.write(x.text);
      } else {
        for (final k in x.kids) {
          walk(k);
        }
      }
    }

    walk(this);
    return b.toString();
  }

  static final RegExp _tag = RegExp(
      r'<(/?)([A-Za-z_][\w:.\-]*)([^>]*?)(/?)>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+)');
  static final RegExp _attr = RegExp(r'([\w:.\-]+)\s*=\s*"([^"]*)"');

  static Map<String, String> _attrs(String s) {
    final out = <String, String>{};
    for (final m in _attr.allMatches(s)) {
      out[m.group(1)!] = _unesc(m.group(2)!);
    }
    return out;
  }

  static String _unesc(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAllMapped(RegExp(r'&#(\d+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static _X parse(String xml) {
    final root = _X('#root');
    final stack = <_X>[root];
    for (final m in _tag.allMatches(xml)) {
      final name = m.group(2);
      if (name != null) {
        if (m.group(1) == '/') {
          if (stack.length > 1) stack.removeLast();
        } else {
          final node = _X(name, attrs: _attrs(m.group(3) ?? ''));
          stack.last.kids.add(node);
          if (m.group(4) != '/') stack.add(node);
        }
      } else if (m.group(5) != null) {
        stack.last.kids.add(_X('#text', text: m.group(5)!));
      } else if (m.group(6) != null) {
        stack.last.kids.add(_X('#text', text: _unesc(m.group(6)!)));
      }
    }
    return root;
  }
}
