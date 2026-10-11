import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Документти окуп жатканда чыккан ката (колдонуучуга көрсөтүлөт).
class DocumentReadException implements Exception {
  final String message;
  const DocumentReadException(this.message);
  @override
  String toString() => message;
}

/// Каалаган документтен (PDF, DOCX, PPTX, XLSX, ODT, RTF, HTML, TXT ...)
/// таза текст алат. Алынган текст СРСти толуктоо үчүн AI'га берилет.
class DocumentReader {
  static const List<String> supportedExtensions = [
    'pdf', 'docx', 'pptx', 'xlsx', 'odt', 'odp', 'ods', 'rtf',
    'txt', 'md', 'csv', 'json', 'html', 'htm', 'xml', 'tex',
  ];

  /// Файлдын максималдуу өлчөмү.
  static const int maxBytes = 25 * 1024 * 1024;

  /// Сакталуучу тексттин максималдуу узундугу (символ).
  static const int maxChars = 60000;

  static Future<String> read(String fileName, Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const DocumentReadException('Файл бош экен.');
    }
    if (bytes.length > maxBytes) {
      throw const DocumentReadException('Файл өтө чоң (25 МБдан ашпасын).');
    }

    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();

    String text;
    try {
      switch (ext) {
        case 'pdf':
          text = _pdf(bytes);
          break;
        case 'docx':
          text = _docx(bytes);
          break;
        case 'pptx':
          text = _pptx(bytes);
          break;
        case 'xlsx':
          text = _xlsx(bytes);
          break;
        case 'odt':
        case 'odp':
        case 'ods':
          text = _odf(bytes);
          break;
        case 'rtf':
          text = _rtf(_decodeText(bytes));
          break;
        case 'html':
        case 'htm':
        case 'xml':
          text = _stripTags(_decodeText(bytes));
          break;
        case 'doc':
        case 'ppt':
        case 'xls':
          throw const DocumentReadException(
              'Эски форматты (.doc/.ppt/.xls) окуу мүмкүн эмес. '
              'Файлды .docx / .pptx / .xlsx же PDF катары сактап кайра жүктөңүз.');
        default:
          // txt, md, csv, json, tex ж.б. — текст катары окуйбуз.
          text = _decodeText(bytes);
      }
    } on DocumentReadException {
      rethrow;
    } catch (_) {
      throw DocumentReadException(
          '"$fileName" файлын окуу мүмкүн болгон жок. Файл бузулган же корголгон болушу мүмкүн.');
    }

    text = _normalize(text);
    if (text.isEmpty) {
      throw DocumentReadException(ext == 'pdf'
          ? 'PDFтен текст табылган жок (сканерленген сүрөт болушу мүмкүн).'
          : 'Документтен текст табылган жок.');
    }
    if (text.length > maxChars) {
      text = text.substring(0, maxChars);
    }
    return text;
  }

  // ------------------------------------------------------------------ PDF
  static String _pdf(Uint8List bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(doc).extractText();
    } finally {
      doc.dispose();
    }
  }

  // ----------------------------------------------------------- OOXML / ODF
  static Archive _zip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

  static String? _entry(Archive a, String name) {
    for (final f in a) {
      if (f.isFile && f.name == name) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  static List<ArchiveFile> _entries(Archive a, RegExp pattern) {
    final list = a.where((f) => f.isFile && pattern.hasMatch(f.name)).toList();
    list.sort((x, y) => _num(x.name).compareTo(_num(y.name)));
    return list;
  }

  static int _num(String s) {
    final m = RegExp(r'(\d+)\.xml$').firstMatch(s);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  static String _docx(Uint8List bytes) {
    final xml = _entry(_zip(bytes), 'word/document.xml');
    if (xml == null) throw const DocumentReadException('DOCX туура эмес.');
    return _xmlText(
      xml,
      breaks: RegExp(r'</w:p>|<w:br\s*/>|</w:tr>'),
      tabs: RegExp(r'<w:tab\s*/>|</w:tc>'),
    );
  }

  static String _pptx(Uint8List bytes) {
    final zip = _zip(bytes);
    final out = StringBuffer();
    var n = 0;
    for (final f in _entries(zip, RegExp(r'^ppt/slides/slide\d+\.xml$'))) {
      n++;
      final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
      out.writeln('--- Слайд $n ---');
      out.writeln(_xmlText(xml, breaks: RegExp(r'</a:p>')));
    }
    return out.toString();
  }

  static String _xlsx(Uint8List bytes) {
    final zip = _zip(bytes);

    final shared = <String>[];
    final ss = _entry(zip, 'xl/sharedStrings.xml');
    if (ss != null) {
      for (final m
          in RegExp(r'<si[ >].*?</si>', dotAll: true).allMatches(ss)) {
        final buf = StringBuffer();
        for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
            .allMatches(m.group(0)!)) {
          buf.write(t.group(1));
        }
        shared.add(_unescape(buf.toString()));
      }
    }

    final out = StringBuffer();
    var sheetNo = 0;
    for (final f in _entries(zip, RegExp(r'^xl/worksheets/sheet\d+\.xml$'))) {
      sheetNo++;
      out.writeln('--- Барак $sheetNo ---');
      final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
      var rows = 0;
      for (final row
          in RegExp(r'<row[ >].*?</row>', dotAll: true).allMatches(xml)) {
        if (++rows > 500) break;
        final cells = <String>[];
        for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
            .allMatches(row.group(0)!)) {
          final attrs = c.group(1) ?? '';
          final body = c.group(2) ?? '';
          final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body);
          String val = '';
          if (attrs.contains('t="s"') && v != null) {
            final i = int.tryParse(v.group(1)!.trim());
            if (i != null && i >= 0 && i < shared.length) val = shared[i];
          } else if (attrs.contains('t="inlineStr"')) {
            final t = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
                .firstMatch(body);
            val = _unescape(t?.group(1) ?? '');
          } else if (v != null) {
            val = _unescape(v.group(1)!);
          }
          if (val.trim().isNotEmpty) cells.add(val.trim());
        }
        if (cells.isNotEmpty) out.writeln(cells.join(' | '));
      }
    }
    return out.toString();
  }

  static String _odf(Uint8List bytes) {
    final xml = _entry(_zip(bytes), 'content.xml');
    if (xml == null) throw const DocumentReadException('Документ туура эмес.');
    return _xmlText(
      xml,
      breaks: RegExp(r'</text:p>|</text:h>|<text:line-break\s*/>|</table:table-row>'),
      tabs: RegExp(r'<text:tab\s*/>|</table:table-cell>'),
    );
  }

  // ------------------------------------------------------------------ RTF
  static String _rtf(String s) {
    final out = StringBuffer();
    var i = 0;
    var skipDepth = -1; // {\*\...} жана {\fonttbl ...} топторун өткөрүп жиберебиз
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '{') {
        depth++;
        if (i + 2 < s.length && s[i + 1] == '\\' && s[i + 2] == '*') {
          if (skipDepth < 0) skipDepth = depth;
        } else if (s.startsWith(r'{\fonttbl', i) ||
            s.startsWith(r'{\colortbl', i) ||
            s.startsWith(r'{\stylesheet', i) ||
            s.startsWith(r'{\info', i) ||
            s.startsWith(r'{\pict', i)) {
          if (skipDepth < 0) skipDepth = depth;
        }
        i++;
      } else if (c == '}') {
        if (depth == skipDepth) skipDepth = -1;
        depth--;
        i++;
      } else if (c == '\\') {
        i++;
        if (i >= s.length) break;
        final n = s[i];
        if (n == '\\' || n == '{' || n == '}') {
          if (skipDepth < 0) out.write(n);
          i++;
        } else if (n == "'") {
          final hex = i + 2 < s.length ? s.substring(i + 1, i + 3) : '';
          final code = int.tryParse(hex, radix: 16);
          if (code != null && skipDepth < 0) {
            // cp1251 кирилл тамгалары
            if (code >= 0xC0) {
              out.writeCharCode(0x410 + (code - 0xC0));
            } else if (code < 0x80) {
              out.writeCharCode(code);
            }
          }
          i += 3;
        } else {
          final m =
              RegExp(r'^([a-zA-Z]+)(-?\d+)?[ ]?').firstMatch(s.substring(i));
          if (m == null) {
            i++;
            continue;
          }
          final word = m.group(1)!;
          final arg = m.group(2);
          if (skipDepth < 0) {
            if (word == 'par' || word == 'line' || word == 'row') {
              out.write('\n');
            } else if (word == 'tab' || word == 'cell') {
              out.write('\t');
            } else if (word == 'u' && arg != null) {
              var u = int.parse(arg);
              if (u < 0) u += 65536;
              out.writeCharCode(u);
              // \u арты "?" — аны өткөрүп жиберебиз
              if (i + m.group(0)!.length < s.length &&
                  s[i + m.group(0)!.length] == '?') {
                i++;
              }
            }
          }
          i += m.group(0)!.length;
        }
      } else {
        if (skipDepth < 0 && c != '\r' && c != '\n') out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  // ----------------------------------------------------------- жардамчылар
  static String _decodeText(Uint8List bytes) {
    var data = bytes;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = Uint8List.sublistView(data, 3);
    }
    // UTF-16 BOM
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      final units = <int>[];
      for (var i = 2; i + 1 < data.length; i += 2) {
        units.add(data[i] | (data[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    final utf = utf8.decode(data, allowMalformed: true);
    final bad = '�'.allMatches(utf).length;
    if (bad > 3 && bad > utf.length ~/ 200) {
      // Кыязы Windows-1251 (кирилл)
      final b = StringBuffer();
      for (final x in data) {
        if (x < 0x80) {
          b.writeCharCode(x);
        } else if (x >= 0xC0) {
          b.writeCharCode(0x410 + (x - 0xC0));
        } else if (x == 0xA8) {
          b.writeCharCode(0x401);
        } else if (x == 0xB8) {
          b.writeCharCode(0x451);
        } else {
          b.write(' ');
        }
      }
      return b.toString();
    }
    return utf;
  }

  static String _xmlText(String xml, {required RegExp breaks, RegExp? tabs}) {
    var s = xml;
    s = s.replaceAll(breaks, '\n');
    if (tabs != null) s = s.replaceAll(tabs, '\t');
    return _stripTags(s, keepNewlines: true);
  }

  static String _stripTags(String s, {bool keepNewlines = false}) {
    var t = s
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<(br|/p|/div|/li|/tr|/h\d)\b[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return _unescape(t);
  }

  static String _unescape(String s) {
    return s
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAllMapped(RegExp(r'&#(\d+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  static String _normalize(String s) {
    final lines = s
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[  ]+'), ' ').trim());
    final out = <String>[];
    var blank = 0;
    for (final l in lines) {
      if (l.isEmpty) {
        if (++blank <= 1 && out.isNotEmpty) out.add('');
      } else {
        blank = 0;
        out.add(l);
      }
    }
    return out.join('\n').trim();
  }
}
