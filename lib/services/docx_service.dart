import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models/doc_block.dart';
import '../models/srs_config.dart';

/// Чыныгы OOXML (.docx) файлын тышкы кызматсыз, кол менен курат.
class DocxService {
  static const int _twipsPerCm = 567;
  static const int _emuPerCm = 360000;

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Future<Uint8List> build({
    required SrsConfig config,
    required List<DocBlock> blocks,
    required AuthorInfo author,
    Map<int, Uint8List> images = const {},
    DateTime? date,
  }) async {
    final dateStr = DateFormat('dd.MM.yyyy').format(date ?? DateTime.now());
    final body = StringBuffer();
    final media = <String, Uint8List>{};
    final rels = StringBuffer();
    var relId = 10;

    rels.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    rels.writeln(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    rels.writeln(
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');

    // ----------------------------------------------------------- титул бет
    body.write(_titlePage(config, author, dateStr));
    body.write(_pageBreak());

    // --------------------------------------------------------------- мазмун
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      switch (b.type) {
        case BlockType.h1:
          body.write(_para(b.text,
              bold: true, size: 32, before: 240, after: 120, outline: 1));
          break;
        case BlockType.h2:
          body.write(_para(b.text,
              bold: true, size: 28, before: 200, after: 100, outline: 2));
          break;
        case BlockType.h3:
          body.write(_para(b.text,
              bold: true, size: 25, before: 160, after: 80, outline: 3));
          break;
        case BlockType.paragraph:
          body.write(_para(b.text, justify: true, indentFirst: 709));
          break;
        case BlockType.bullet:
          body.write(_para('•  ${b.text}', indentLeft: 567));
          break;
        case BlockType.numbered:
          body.write(_para('${b.marker}  ${b.text}', indentLeft: 567));
          break;
        case BlockType.formula:
          body.write(_para(b.text,
              italic: true, center: true, before: 120, after: 120));
          break;
        case BlockType.spacer:
          break;
        case BlockType.table:
          body.write(_table(b.rows ?? const []));
          break;
        case BlockType.diagram:
          final png = images[i];
          if (png == null) break;
          final dim = _pngSize(png);
          if (dim == null) break;
          final name = 'image${media.length + 1}.png';
          media['word/media/$name'] = png;
          final id = 'rId$relId';
          relId++;
          rels.writeln(
              '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
          const widthCm = 14.0;
          final cx = (widthCm * _emuPerCm).round();
          final cy = (widthCm * dim.$2 / dim.$1 * _emuPerCm).round();
          body.write(_image(id, cx, cy, media.length));
          final caption = b.diagram?.caption ?? '';
          if (caption.isNotEmpty) {
            body.write(_para(caption,
                italic: true, center: true, size: 19, after: 160));
          }
          break;
      }
    }

    body.write(_sectPr());
    rels.writeln('</Relationships>');

    final document = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">')
      ..writeln('<w:body>')
      ..write(body)
      ..writeln('</w:body>')
      ..writeln('</w:document>');

    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels());
    add('word/document.xml', document.toString());
    add('word/_rels/document.xml.rels', rels.toString());
    add('word/styles.xml', _styles());
    media.forEach((path, bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    });

    final zip = ZipEncoder().encode(archive);
    return Uint8List.fromList(zip);
  }

  // ----------------------------------------------------------------- бөлүк
  static String _titlePage(
      SrsConfig config, AuthorInfo author, String dateStr) {
    final lang = config.language;
    String t(String ky, String ru, String en) {
      switch (lang) {
        case Language.kyrgyz:
          return ky;
        case Language.russian:
          return ru;
        case Language.english:
          return en;
      }
    }

    final sb = StringBuffer();
    sb.write(_para(
        t('КЫРГЫЗ РЕСПУБЛИКАСЫНЫН БИЛИМ БЕРҮҮ ЖАНА ИЛИМ МИНИСТРЛИГИ',
            'МИНИСТЕРСТВО ОБРАЗОВАНИЯ И НАУКИ КЫРГЫЗСКОЙ РЕСПУБЛИКИ',
            'MINISTRY OF EDUCATION AND SCIENCE OF THE KYRGYZ REPUBLIC'),
        bold: true, center: true, size: 22));
    for (final line in [
      if (author.university.isNotEmpty) author.university.toUpperCase(),
      if (author.faculty.isNotEmpty) author.faculty,
      if (author.department.isNotEmpty) author.department,
    ]) {
      sb.write(_para(line, bold: true, center: true, size: 24));
    }
    sb.write(_empty(6));
    sb.write(_para(
        t('СТУДЕНТТИН ӨЗ АЛДЫНЧА ИШИ', 'САМОСТОЯТЕЛЬНАЯ РАБОТА СТУДЕНТА',
            'INDEPENDENT STUDENT WORK'),
        bold: true, center: true, size: 34));
    sb.write(_para(lang == Language.english ? '(SRS)' : '(СРС)',
        italic: true, center: true, size: 24));
    sb.write(_empty(3));
    sb.write(_para(
        '${t('Предмет', 'Предмет', 'Subject')}: ${config.subjectName}',
        center: true,
        size: 26));
    sb.write(_para('${t('Тема', 'Тема', 'Topic')}: ${config.topic}',
        bold: true, center: true, size: 28));
    sb.write(_empty(6));
    sb.write(_para(
        '${t('Аткарган', 'Выполнил(а)', 'Prepared by')}: ${author.student}',
        right: true,
        size: 24));
    sb.write(_para('${t('Топ', 'Группа', 'Group')}: ${author.group}',
        right: true, size: 24));
    sb.write(_para(
        '${t('Текшерген', 'Проверил(а)', 'Checked by')}: ${author.teacher}',
        right: true,
        size: 24));
    sb.write(_empty(4));
    sb.write(_para(
        t('${dateStr.split('.').last} - жыл', '${dateStr.split('.').last} г.',
            dateStr.split('.').last),
        center: true,
        size: 24));
    return sb.toString();
  }

  static String _empty(int count) =>
      List.generate(count, (_) => _para('')).join();

  static String _para(
    String text, {
    bool bold = false,
    bool italic = false,
    bool center = false,
    bool right = false,
    bool justify = false,
    int size = 24, // half-points: 24 = 12pt
    int before = 0,
    int after = 60,
    int indentLeft = 0,
    int indentFirst = 0,
    int outline = 0,
  }) {
    final align = center
        ? '<w:jc w:val="center"/>'
        : right
            ? '<w:jc w:val="right"/>'
            : justify
                ? '<w:jc w:val="both"/>'
                : '';
    final ind = (indentLeft > 0 || indentFirst > 0)
        ? '<w:ind${indentLeft > 0 ? ' w:left="$indentLeft"' : ''}'
            '${indentFirst > 0 ? ' w:firstLine="$indentFirst"' : ''}/>'
        : '';
    final outlineXml =
        outline > 0 ? '<w:outlineLvl w:val="${outline - 1}"/>' : '';
    return '<w:p><w:pPr>$align$ind'
        '<w:spacing w:before="$before" w:after="$after" w:line="276" w:lineRule="auto"/>'
        '$outlineXml</w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
        '${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
        '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static String _pageBreak() =>
      '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';

  static String _table(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    const totalWidth = 9000;
    final cw = (totalWidth / cols).round();
    final sb = StringBuffer();
    sb.write('<w:tbl><w:tblPr>'
        '<w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="$totalWidth" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="6" w:color="808080"/>'
        '<w:left w:val="single" w:sz="6" w:color="808080"/>'
        '<w:bottom w:val="single" w:sz="6" w:color="808080"/>'
        '<w:right w:val="single" w:sz="6" w:color="808080"/>'
        '<w:insideH w:val="single" w:sz="6" w:color="808080"/>'
        '<w:insideV w:val="single" w:sz="6" w:color="808080"/>'
        '</w:tblBorders></w:tblPr>');
    sb.write('<w:tblGrid>');
    for (var i = 0; i < cols; i++) {
      sb.write('<w:gridCol w:w="$cw"/>');
    }
    sb.write('</w:tblGrid>');
    for (var r = 0; r < rows.length; r++) {
      sb.write('<w:tr>');
      for (var c = 0; c < cols; c++) {
        final value = c < rows[r].length ? rows[r][c] : '';
        sb.write('<w:tc><w:tcPr><w:tcW w:w="$cw" w:type="dxa"/>'
            '${r == 0 ? '<w:shd w:val="clear" w:fill="EFEFEF"/>' : ''}'
            '</w:tcPr>');
        sb.write(_para(value, bold: r == 0, size: 20, after: 0));
        sb.write('</w:tc>');
      }
      sb.write('</w:tr>');
    }
    sb.write('</w:tbl>');
    sb.write(_para(''));
    return sb.toString();
  }

  static String _image(String relId, int cx, int cy, int index) {
    return '<w:p><w:pPr><w:jc w:val="center"/>'
        '<w:spacing w:before="120" w:after="60"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$index" name="Picture $index"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$index" name="Picture $index"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic>'
        '</wp:inline></w:drawing></w:r></w:p>';
  }

  static String _sectPr() {
    const left = 25 * _twipsPerCm ~/ 10;
    const right = 15 * _twipsPerCm ~/ 10;
    const top = 20 * _twipsPerCm ~/ 10;
    const bottom = 20 * _twipsPerCm ~/ 10;
    return '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="$top" w:right="$right" w:bottom="$bottom" w:left="$left" '
        'w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr>';
  }

  static String _contentTypes() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static String _rootRels() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static String _styles() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
      '<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/></w:style>'
      '</w:styles>';

  /// PNG'дин туурасы/бийиктиги (IHDR).
  static (int, int)? _pngSize(Uint8List png) {
    if (png.length < 24) return null;
    final bd = ByteData.sublistView(png);
    final w = bd.getUint32(16);
    final h = bd.getUint32(20);
    if (w == 0 || h == 0) return null;
    return (w, h);
  }
}
