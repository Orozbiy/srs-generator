import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/doc_block.dart';
import '../models/handwriting_style.dart';
import 'latex_text.dart';
import 'pencil.dart';
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
      final mine =
          await MyHandwritingStore.load(
          profile: config.handProfile ?? MyHandwritingStore.defaultId);
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

    if (config.withTitlePage) {
      // Шрифттик кол жазмада титул барак да ошол кол жазма менен чыгат
      final hf = (hw != null && hw.mine == null) ? hw.font : null;
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: margin,
          build: (ctx) {
            final page = _titlePage(
              config: config,
              author: author,
              dateStr: dateStr,
              bold: hf ?? bold,
              regular: hf ?? regular,
              italic: hf ?? italic,
            );
            if (hf == null) return page;
            return pw.DefaultTextStyle(
              style: pw.TextStyle(color: _ink, fontFallback: [regular]),
              child: page,
            );
          },
        ),
      );
    }

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
    final year = dateStr.split('.').last;

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

    String v(String s) => s.trim().isEmpty ? '_______________' : s.trim();

    final ministry = t(
        'КЫРГЫЗ РЕСПУБЛИКАСЫНЫН ИЛИМ, ЖОГОРКУ БИЛИМ БЕРҮҮ ЖАНА ИННОВАЦИЯЛАР МИНИСТРЛИГИ',
        'МИНИСТЕРСТВО НАУКИ, ВЫСШЕГО ОБРАЗОВАНИЯ И ИННОВАЦИЙ КЫРГЫЗСКОЙ РЕСПУБЛИКИ',
        'MINISTRY OF SCIENCE, HIGHER EDUCATION AND INNOVATION OF THE KYRGYZ REPUBLIC');
    final uni = author.universityFor(lang);
    final fac = author.facultyFor(lang);
    final dep = author.departmentLine(lang);

    final done = t('Аткарган', author.studentFemale ? 'Выполнила' : 'Выполнил',
        'Prepared by');
    final checked = t('Текшерген',
        author.teacherFemale ? 'Проверила' : 'Проверил', 'Checked by');
    final group = v(author.group);
    final groupLabel = t('Топ', 'Группа', 'Group');
    final subjectLine = t('«${config.subjectName}» дисциплинасы боюнча',
        'по дисциплине «${config.subjectName}»',
        'in the discipline "${config.subjectName}"');
    final dateLine = t('«____» ______________ $year-ж.',
        '«____» ______________ $year г.', '____ / ____ / $year');

    pw.Widget c(String s, pw.Font f, double size, {double after = 4}) =>
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: after),
          child: pw.Text(s,
              style: pw.TextStyle(font: f, fontSize: size),
              textAlign: pw.TextAlign.center),
        );

    pw.Widget r(String s, pw.Font f, {double after = 3}) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: after),
          child: pw.Text(s,
              style: pw.TextStyle(font: f, fontSize: 11),
              textAlign: pw.TextAlign.right),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 6),
        c(ministry, regular, 10.5, after: 4),
        if (uni.isNotEmpty) c(uni.toUpperCase(), regular, 10.5, after: 14),
        if (author.fullTitle && fac.isNotEmpty)
          c(fac.toUpperCase(), bold, 11, after: 4),
        if (author.fullTitle && dep.isNotEmpty) c(dep, italic, 9.5, after: 0),
        pw.Spacer(flex: 3),
        pw.Text(
          lang == Language.english ? 'SRS' : 'СРС',
          style: pw.TextStyle(font: bold, fontSize: 60),
        ),
        pw.SizedBox(height: 14),
        c(subjectLine, bold, 11.5, after: 6),
        pw.SizedBox(height: 22),
        c('${t('Тема', 'Тема', 'Topic')}: ${config.topic}', bold, 11,
            after: 0),
        pw.Spacer(flex: 3),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 270,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                r('$done: ${v(author.student)}', regular),
                r('$groupLabel: $group', regular, after: 8),
                r('$checked: ${v(author.teacher)}', regular, after: 8),
                r('${t('Баасы', 'Оценка', 'Grade')}: ____________________',
                    regular),
                r(dateLine, regular, after: 0),
              ],
            ),
          ),
        ),
        pw.Spacer(flex: 2),
        c('${t('Бишкек', 'Бишкек', 'Bishkek')} $year', bold, 10.5, after: 0),
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

  /// Таблицанын бир уячасы: тегерегин кара карандаш менен чийет.
  /// Ар бир уяча өзүнүн жогорку жана сол сызыгын чийет, акыркы мамыча/катар
  /// оң жана төмөнкү сызыкты кошот — ошондо сызыктар эки жолу чийилбейт.
  static pw.Widget _pencilCell({
    required pw.Widget child,
    required int row,
    required int col,
    required bool lastRow,
    required bool lastCol,
    required int seed,
  }) {
    return pw.CustomPaint(
      painter: (PdfGraphics g, PdfPoint size) {
        final pen = Pencil(
          seed ^ (row * 7919) ^ (col * 104729),
          amp: 0.32,
          width: 0.6,
          step: 1.2,
          chunk: 3.5,
        );
        final w = size.x;
        final h = size.y;
        _paintPencil(g, [
          ...pen.line(0, h, w, h),
          ...pen.line(0, 0, 0, h),
          if (lastCol) ...pen.line(w, 0, w, h),
          if (lastRow) ...pen.line(0, 0, w, 0),
        ]);
      },
      child: child,
    );
  }

  /// Карандаш сызыктарын PDF'ке чийет (басымга жараша боз түс жана жоондук).
  static void _paintPencil(PdfGraphics g, List<PencilStroke> strokes) {
    g.setLineCap(PdfLineCap.round);
    g.setLineJoin(PdfLineJoin.round);
    for (final s in strokes) {
      final q = s.pts;
      if (q.length < 4) continue;
      final v = s.gray;
      g.setStrokeColor(PdfColor.fromInt(0xFF000000 | (v << 16) | (v << 8) | v));
      g.setLineWidth(s.width);
      g.moveTo(q[0], q[1]);
      for (var i = 2; i + 1 < q.length; i += 2) {
        g.lineTo(q[i], q[i + 1]);
      }
      g.strokePath();
    }
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
        final tseed = rows.length * 7919 +
            cols * 104729 +
            (rows.first.isEmpty ? 0 : rows.first.first.hashCode);
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Table(
            // Сызыктарды ар бир уячанын өзү кара карандаш менен чийет
            // (эч кандай даяр рамка жок).
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
            children: [
              for (var r = 0; r < rows.length; r++)
                pw.TableRow(
                  children: [
                    for (var cc = 0; cc < cols; cc++)
                      _pencilCell(
                        row: r,
                        col: cc,
                        lastRow: r == rows.length - 1,
                        lastCol: cc == cols - 1,
                        seed: tseed,
                        child: pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 3),
                          child: _rich(
                              cc < rows[r].length ? rows[r][cc] : '', hw, 10.5,
                              height: 1.25,
                              underline: false,
                              avail: _contentW / cols - 12),
                        ),
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

  /// Сүрөттүн туурасы: тик сүрөттөр бетке бийиктикке батышы үчүн тарыраак.
  static double _imgWidth(Uint8List png) {
    if (png.length < 24) return 400;
    final bd = ByteData.sublistView(png);
    final w = bd.getUint32(16);
    final h = bd.getUint32(20);
    if (w == 0 || h == 0) return 400;
    return (270.0 * w / h).clamp(120.0, 400.0).toDouble();
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
                child: pw.Image(pw.MemoryImage(image), width: _imgWidth(image)),
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
