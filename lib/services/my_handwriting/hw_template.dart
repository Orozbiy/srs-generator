import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'hw_geom.dart';

/// Колдонуучу кол жазмасын жазуу үчүн бланк (шаблон) PDF жасайт.
class HwTemplate {
  static const double _mm = PdfPageFormat.mm;

  static Future<Uint8List> build() async {
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font));

    for (var page = 0; page < HwGeom.pageCount; page++) {
      final chars = HwGeom.pageChars(page);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.SizedBox(
            width: PdfPageFormat.a4.width,
            height: PdfPageFormat.a4.height,
            child: pw.Stack(children: _pageWidgets(page, chars)),
          ),
        ),
      );
    }
    return doc.save();
  }

  static List<pw.Widget> _pageWidgets(int page, String chars) {
    const grey = PdfColor.fromInt(0xFFBBBBBB);
    const lightGrey = PdfColor.fromInt(0xFFDDDDDD);
    const labelColor = PdfColor.fromInt(0xFF666666);
    final out = <pw.Widget>[];

    // Бурчтардагы маркерлер (сүрөттү түздөө үчүн). Сол-жогорку — чоң.
    for (final m in HwGeom.markers) {
      out.add(pw.Positioned(
        left: (m[0] - m[2] / 2) * _mm,
        top: (m[1] - m[2] / 2) * _mm,
        child: pw.Container(
            width: m[2] * _mm, height: m[2] * _mm, color: PdfColors.black),
      ));
    }

    out.add(pw.Positioned(
      left: 22 * _mm,
      top: 6 * _mm,
      child: pw.SizedBox(
        width: 170 * _mm,
        child: pw.Text(
          'Кол жазма шаблону — ${page + 1}/${HwGeom.pageCount}. '
          'Ар бир чиймеге тиешелүү тамганы адаттагыдай өлчөмдө, ичке '
          'сызыктын үстүнө жазыңыз. Четине жана маркерлерге тийбеңиз. '
          'Кара сыя же ручка колдонуңуз.',
          style: const pw.TextStyle(fontSize: 7.5, color: labelColor),
        ),
      ),
    ));

    for (var i = 0; i < HwGeom.perPage; i++) {
      final ox = HwGeom.cellX(i);
      final oy = HwGeom.cellY(i);

      out.add(pw.Positioned(
        left: ox * _mm,
        top: oy * _mm,
        child: pw.Container(
          width: HwGeom.cellW * _mm,
          height: HwGeom.cellH * _mm,
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: grey, width: 0.6)),
        ),
      ));
      out.add(pw.Positioned(
        left: ox * _mm,
        top: (oy + HwGeom.labelH) * _mm,
        child: pw.Container(
            width: HwGeom.cellW * _mm, height: 0.5, color: grey),
      ));

      final r = HwGeom.writeRect(i);
      out.add(pw.Positioned(
        left: r[0] * _mm,
        top: HwGeom.baselineY(i) * _mm,
        child: pw.Container(
            width: (r[2] - r[0]) * _mm, height: 0.5, color: lightGrey),
      ));

      if (i < chars.length) {
        out.add(pw.Positioned(
          left: (ox + 1.2) * _mm,
          top: (oy + 0.7) * _mm,
          child: pw.Text(
            chars[i],
            style: const pw.TextStyle(fontSize: 9, color: labelColor),
          ),
        ));
      }
    }
    return out;
  }
}
