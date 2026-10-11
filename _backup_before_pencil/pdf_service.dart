import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/doc_block.dart';
import '../models/handwriting_style.dart';
import 'latex_text.dart';
import '../models/srs_config.dart';
import 'my_handwriting/hw_profile.dart';
import 'my_handwriting/hw_render.dart';

class PdfService {
  // pdf пакетинин стандарт Helvetica шрифти кириллицада FormatException
  // ыргытат, ошондуктан assets'тен Unicode TTF жүктөлөт.
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _italic;

  static final Map<HandwritingStyle, pw.Font> _hand = {};

  static Future<pw.Font> _handFont(HandwritingStyle st) async {
    final cached = _hand[st];
    if (cached != null) return cached;
    final f = pw.Font.ttf(await rootBundle.load(st.asset));
    _hand[st] = f;
    return f;
  }

  static Future<void> _ensureFonts() async {
    _regular ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    _italic ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans-Oblique.ttf'));
  }

  /// [images] — DocBlock индекси боюнча даяр PNG сүрөттөр.
  static Future<Uint8List> build({
    required SrsConfig config,
    required List<DocBlock> blocks,
    required AuthorInfo author,
    Map<int, Uint8List> images = const {},
    DateTime? date,
  }) async {
    await _ensureFonts();

    final regular = _regular!;
    final bold = _bold!;
    final italic = _italic!;
    final hwStyle = config.handwriting;
    _Hand? hw;
    if (hwStyle == HandwritingStyle.mine) {
      // Колдонуучунун өз кол жазмасы (сүрөттөн үйрөтүлгөн тамгалар).
      final mine = await MyHandwritingStore.load();
      if (mine != null && mine.usable) {
        hw = _Hand(regular, 1.0, regular, mine);
      }
    } else if (hwStyle != null) {
      hw = _Hand(await _handFont(hwStyle), hwStyle.scale, regular);
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: bold,
      ),
    );
    final dateStr = DateFormat('dd.MM.yyyy').format(date ?? DateTime.now());

    const pageFormat = PdfPageFormat.a4;
    const margin = pw.EdgeInsets.fromLTRB(
      25 * PdfPageFormat.mm,
      20 * PdfPageFormat.mm,
      15 * PdfPageFormat.mm,
      20 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: margin,
        build: (ctx) => _titlePage(
          config: config,
          author: author,
          dateStr: dateStr,
          bold: bold,
          regular: regular,
          italic: italic,
        ),
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: margin,
        maxPages: 500,
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            '${ctx.pageNumber}',
            style: pw.TextStyle(
                font: regular, fontSize: 10, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          for (var i = 0; i < blocks.length; i++)
            _block(blocks[i], images[i], bold, regular, italic, hw),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _titlePage({
    required SrsConfig config,
    required AuthorInfo author,
    required String dateStr,
    required pw.Font bold,
    required pw.Font regular,
    required pw.Font italic,
  }) {
    final lang = config.language;
    final isEn = lang == Language.english;

    String ministry() {
      switch (lang) {
        case Language.kyrgyz:
          return 'КЫРГЫЗ РЕСПУБЛИКАСЫНЫН БИЛИМ БЕРҮҮ ЖАНА ИЛИМ МИНИСТРЛИГИ';
        case Language.russian:
          return 'МИНИСТЕРСТВО ОБРАЗОВАНИЯ И НАУКИ КЫРГЫЗСКОЙ РЕСПУБЛИКИ';
        case Language.english:
          return 'MINISTRY OF EDUCATION AND SCIENCE OF THE KYRGYZ REPUBLIC';
      }
    }

    String heading() {
      switch (lang) {
        case Language.kyrgyz:
          return 'СТУДЕНТТИН ӨЗ АЛДЫНЧА ИШИ';
        case Language.russian:
          return 'САМОСТОЯТЕЛЬНАЯ РАБОТА СТУДЕНТА';
        case Language.english:
          return 'INDEPENDENT STUDENT WORK';
      }
    }

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

    final org = <String>[
      if (author.university.isNotEmpty) author.university.toUpperCase(),
      if (author.faculty.isNotEmpty) author.faculty,
      if (author.department.isNotEmpty) author.department,
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(
          ministry(),
          style: pw.TextStyle(font: bold, fontSize: 10),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 10),
        for (final line in org) ...[
          pw.Text(
            line,
            style: pw.TextStyle(font: bold, fontSize: 11),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
        ],
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 46),
        pw.Text(
          heading(),
          style: pw.TextStyle(font: bold, fontSize: 16),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          isEn ? '(SRS)' : '(СРС)',
          style: pw.TextStyle(font: italic, fontSize: 12),
        ),
        pw.SizedBox(height: 34),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _row(t('Предмет:', 'Предмет:', 'Subject:'), config.subjectName,
                  bold, regular),
              pw.SizedBox(height: 8),
              _row(t('Тема:', 'Тема:', 'Topic:'), config.topic, bold, regular),
              pw.SizedBox(height: 8),
              _row(
                t('Барак саны:', 'Количество страниц:', 'Pages:'),
                '${config.pageCount.value}',
                bold,
                regular,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 56),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 250,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _row(t('Аткарган:', 'Выполнил(а):', 'Prepared by:'),
                      author.student, bold, regular),
                  pw.SizedBox(height: 6),
                  _row(t('Топ:', 'Группа:', 'Group:'), author.group, bold,
                      regular),
                  pw.SizedBox(height: 6),
                  _row(t('Текшерген:', 'Проверил(а):', 'Checked by:'),
                      author.teacher, bold, regular),
                  pw.SizedBox(height: 6),
                  _row(t('Дата:', 'Дата:', 'Date:'), dateStr, bold, regular),
                ],
              ),
            ),
          ],
        ),
        pw.Spacer(),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 8),
        pw.Text(
          t('${dateStr.split('.').last} - жыл',
              '${dateStr.split('.').last} г.', dateStr.split('.').last),
          style: pw.TextStyle(font: regular, fontSize: 11),
        ),
      ],
    );
  }

  static pw.Widget _row(
      String label, String value, pw.Font bold, pw.Font regular) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(value.isEmpty ? '_______________' : value,
              style: pw.TextStyle(font: regular, fontSize: 11)),
        ),
      ],
    );
  }

  /// Кол жазма режиминде ТЕКСТ блоктору гана кол жазма менен жазылат.
  /// Формула, сүрөт/график жана бош орундар өзгөрүүсүз калат.
  static const _ink = PdfColor.fromInt(0xFF1F2F7A);

  /// A4 бетинин текст туурасы (мм): 210 - 25 - 15 = 170 мм.
  static const double _contentW = 170 * PdfPageFormat.mm;

  /// Өз кол жазма: текст сүрөт катары саптарга бөлүнүп чыгат.
  static pw.Widget _richMine(String text, _Hand hw, double size, double avail,
      double height, bool underline) {
    final clean = text
        .replaceAll(LatexText.markOpen, '')
        .replaceAll(LatexText.markClose, '');
    final lines = HwRender.renderParagraph(
      hw.mine!,
      clean,
      sizePt: size,
      availPt: avail,
      lineHeight: height,
      underline: underline,
      seed: clean.hashCode,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          pw.Image(pw.MemoryImage(l.png), width: l.widthPt, height: l.heightPt),
      ],
    );
  }

  static pw.Widget _rich(String text, _Hand hw, double size,
      {double height = 1.45,
      bool underline = false,
      double avail = _contentW,
      pw.TextAlign align = pw.TextAlign.left}) {
    if (hw.mine != null) {
      return _richMine(text, hw, size, avail, height, underline);
    }
    final spans = <pw.InlineSpan>[];
    final re = RegExp('${LatexText.markOpen}(.*?)${LatexText.markClose}',
        dotAll: true);
    var last = 0;
    final fs = size * hw.scale;
    pw.TextStyle handStyle() => pw.TextStyle(
          font: hw.font,
          fontFallback: [hw.fallback],
          fontSize: fs,
          height: height,
          color: _ink,
          decoration: underline ? pw.TextDecoration.underline : null,
        );
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(pw.TextSpan(
            text: text.substring(last, m.start), style: handStyle()));
      }
      // Формула да ошол эле кол жазма менен (басма шрифт колдонулбайт)
      spans.add(pw.TextSpan(
        text: m.group(1),
        style: pw.TextStyle(
          font: hw.font,
          fontFallback: [hw.fallback],
          fontSize: fs,
          height: height,
          color: _ink,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(pw.TextSpan(text: text.substring(last), style: handStyle()));
    }
    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: align,
    );
  }

  static pw.Widget _handBlock(DocBlock b, _Hand hw, pw.Font bold) {
    switch (b.type) {
      case BlockType.h1:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: _rich(b.text, hw, 17, underline: true),
        );
      case BlockType.h2:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: _rich(b.text, hw, 15, underline: true),
        );
      case BlockType.h3:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child: _rich(b.text, hw, 13),
        );
      case BlockType.bullet:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 14, child: _rich('•', hw, 12)),
              pw.Expanded(
                  child: _rich(b.text, hw, 12.5, avail: _contentW - 30 - 16)),
            ],
          ),
        );
      case BlockType.numbered:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                  width: 24,
                  child: _rich(b.marker, hw, 12.5, avail: 24)),
              pw.Expanded(
                  child: _rich(b.text, hw, 12.5, avail: _contentW - 40 - 16)),
            ],
          ),
        );
      case BlockType.formula:
        // Формула да кол менен, рамкасыз, ортодо жазылат
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 7),
          child: pw.Center(
            child: _rich(b.text, hw, 13.5,
                height: 1.3, avail: _contentW - 40, align: pw.TextAlign.center),
          ),
        );
      case BlockType.table:
        final rows = b.rows ?? const <List<String>>[];
        if (rows.isEmpty) return pw.SizedBox();
        final cols = rows.map((r) => r.length).reduce((a, x) => a > x ? a : x);
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Table(
            // сызгыч менен сызылгандай: ошол эле сыянын түсү, жука сызык
            border: pw.TableBorder.all(color: _ink, width: 0.7),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              for (var r = 0; r < rows.length; r++)
                pw.TableRow(
                  children: [
                    for (var cc = 0; cc < cols; cc++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        child: _rich(
                            cc < rows[r].length ? rows[r][cc] : '', hw, 10.5,
                            height: 1.25,
                            underline: false,
                            avail: _contentW / cols - 12),
                      ),
                  ],
                ),
            ],
          ),
        );
      default: // paragraph
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: _rich(b.text, hw, 12.5, height: 1.55),
        );
    }
  }

  static pw.Widget _block(DocBlock b, Uint8List? image, pw.Font bold,
      pw.Font regular, pw.Font italic, [_Hand? hw]) {
    if (hw != null) {
      switch (b.type) {
        case BlockType.diagram:
        case BlockType.spacer:
          break; // сүрөт/бош орун өзгөрүүсүз
        default:
          return _handBlock(b, hw, bold);
      }
    }
    switch (b.type) {
      case BlockType.h1:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child:
              pw.Text(b.text, style: pw.TextStyle(font: bold, fontSize: 15)),
        );
      case BlockType.h2:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child:
              pw.Text(b.text, style: pw.TextStyle(font: bold, fontSize: 13)),
        );
      case BlockType.h3:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child:
              pw.Text(b.text, style: pw.TextStyle(font: bold, fontSize: 11.5)),
        );
      case BlockType.formula:
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.symmetric(vertical: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border(
                left: pw.BorderSide(color: PdfColors.blue400, width: 3)),
          ),
          child: pw.Text(b.text,
              style: pw.TextStyle(font: italic, fontSize: 11)),
        );
      case BlockType.bullet:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: pw.TextStyle(font: bold, fontSize: 11)),
              pw.Expanded(
                child: pw.Text(b.text,
                    style:
                        pw.TextStyle(font: regular, fontSize: 11, height: 1.4)),
              ),
            ],
          ),
        );
      case BlockType.numbered:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 22,
                child: pw.Text(b.marker,
                    style: pw.TextStyle(font: bold, fontSize: 11)),
              ),
              pw.Expanded(
                child: pw.Text(b.text,
                    style:
                        pw.TextStyle(font: regular, fontSize: 11, height: 1.4)),
              ),
            ],
          ),
        );
      case BlockType.table:
        final rows = b.rows ?? const <List<String>>[];
        if (rows.isEmpty) return pw.SizedBox();
        final cols = rows.map((r) => r.length).reduce((a, x) => a > x ? a : x);
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
            children: [
              for (var r = 0; r < rows.length; r++)
                pw.TableRow(
                  decoration: r == 0
                      ? const pw.BoxDecoration(color: PdfColors.grey200)
                      : null,
                  children: [
                    for (var cc = 0; cc < cols; cc++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        child: pw.Text(
                          cc < rows[r].length ? rows[r][cc] : '',
                          style: pw.TextStyle(
                            font: r == 0 ? bold : regular,
                            fontSize: 9.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      case BlockType.diagram:
        if (image == null) return pw.SizedBox();
        final caption = b.diagram?.caption ?? '';
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
          child: pw.Column(
            children: [
              pw.Center(
                child: pw.Image(pw.MemoryImage(image), width: 400),
              ),
              if (caption.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                // Кол жазма режиминде сүрөттүн жазуусу да кол менен
                if (hw != null)
                  pw.Center(
                    child: _rich(caption, hw, 10.5,
                        height: 1.25,
                        avail: 380,
                        align: pw.TextAlign.center),
                  )
                else
                  pw.Text(caption,
                      style: pw.TextStyle(
                          font: italic, fontSize: 9.5, color: PdfColors.grey700),
                      textAlign: pw.TextAlign.center),
              ],
            ],
          ),
        );
      case BlockType.spacer:
        return pw.SizedBox(height: 6);
      case BlockType.paragraph:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            b.text,
            textAlign: pw.TextAlign.justify,
            style: pw.TextStyle(font: regular, fontSize: 11, height: 1.5),
          ),
        );
    }
  }
}

class _Hand {
  final pw.Font font;
  final double scale;
  final pw.Font fallback;

  /// null емес болсо — колдонуучунун өз кол жазмасы колдонулат.
  final MyHandwriting? mine;
  const _Hand(this.font, this.scale, this.fallback, [this.mine]);
}
