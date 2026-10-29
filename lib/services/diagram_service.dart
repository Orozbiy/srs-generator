import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/diagram_spec.dart';
import '../models/handwriting_style.dart';
import 'my_handwriting/hw_profile.dart';
import 'my_handwriting/hw_render.dart';
import 'pencil.dart';

/// Диаграммаларды PNG сүрөткө айлантат. Ошол эле PNG PDFке да, Wordго да кирет.
/// Бардык сызыктар кара карандаш менен кол менен сызгандай чийилет
/// (жеңил толкундоо, басымдын өзгөрүшү, эки жолу сызылган изи, штрих).
class DiagramService {

  // Карандашта түс жок, ошондуктан сериялар сызыктын түрү менен айырмаланат.
  static const List<List<double>> _dashes = [
    [], // үзгүлтүксүз
    [9, 5],
    [2, 5],
    [10, 4, 2, 4],
  ];

  /// Учурдагы жазуучу (render учурунда гана коюлат).
  static _Writer _w = _Writer(null, null);

  /// Көрсөтүлгөн спецификация боюнча PNG жасайт. Жасай албаса null.
  /// [hand] берилсе, графиктеги бардык жазуулар жана сандар ошол кол
  /// жазма менен жазылат («Менин кол жазмам» болсо — өз тамгаларыңыз менен).
  static Future<Uint8List?> render(DiagramSpec spec,
      {double scale = 3, HandwritingStyle? hand, String? handProfile}) async {
    final size = _sizeFor(spec);
    if (size == null) return null;

    MyHandwriting? mine;
    if (hand == HandwritingStyle.mine) {
      try {
        final prof = await MyHandwritingStore.load(
            profile: handProfile ?? MyHandwritingStore.defaultId);
        if (prof != null && prof.usable) mine = prof;
      } catch (_) {}
    }
    final writer = _Writer(hand, mine);
    _w = writer;
    try {
      if (mine != null) {
        // 1-өтүш: кайсы жазуулар керек экенин чогултуп, аларды кол жазма
        // менен сүрөткө айландырабыз (бул асинхрондуу иш).
        writer.collecting = true;
        final rec0 = ui.PictureRecorder();
        _drawAll(Canvas(rec0), size, spec);
        rec0.endRecording().dispose();
        await writer.decodeAll();
        writer.collecting = false;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);
      _drawAll(canvas, size, spec);

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (size.width * scale).round(),
        (size.height * scale).round(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      image.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      writer.dispose();
      _w = _Writer(null, null);
    }
  }

  static void _drawAll(Canvas canvas, Size size, DiagramSpec spec) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );
    final seed = spec.title.hashCode ^ (spec.kind.index * 7919) ^ 0x5A17;
    final p = _Pc(canvas, seed);
    switch (spec.kind) {
      case DiagramKind.chart:
        _drawChart(p, size, spec);
        break;
      case DiagramKind.circuit:
        _drawCircuit(p, size, spec);
        break;
      case DiagramKind.block:
        _drawBlocks(p, size, spec);
        break;
      case DiagramKind.image:
        break; // даяр сүрөт — бул жерде чийилбейт
    }
  }

  static Size? _sizeFor(DiagramSpec spec) {
    switch (spec.kind) {
      case DiagramKind.chart:
        if (spec.series.isEmpty) return null;
        return const Size(540, 340);
      case DiagramKind.circuit:
        if (spec.elements.isEmpty) return null;
        final n = spec.elements.length;
        final parallel = spec.circuitLayout.startsWith('par');
        final extra = spec.title.isNotEmpty ? 26.0 : 0.0;
        if (parallel) {
          // Ар бир бутакка label + символ батчу бийиктик.
          return Size(540, 120.0 + extra + n * 62);
        }
        // Сериялык: элемент көбөйсө туурасын кеңейтебиз, болбосо
        // символдор менен label бири-бирине жабышат.
        final width = math.max(540.0, 120.0 + n * 92.0);
        return Size(width, 210.0 + extra);
      case DiagramKind.block:
        final n = spec.nodes.length;
        if (n == 0) return null;
        // Эң узун node текстине жараша кенендикти тандайбыз.
        var maxLen = 0;
        for (final t in spec.nodes) {
          if (t.length > maxLen) maxLen = t.length;
        }
        final width = maxLen > 36 ? 580.0 : 520.0;
        // Аталыш узун болсо эки сапка чыгат — бийиктикке кошумча орун.
        final titleExtra = spec.title.length > 40 ? 20.0 : 0.0;
        return Size(width, 54.0 + titleExtra + n * 64);
      case DiagramKind.image:
        return null;
    }
  }

  // ------------------------------------------------------------------ текст
  static _Txt _painter(
    String text, {
    double size = 11,
    double maxWidth = 400,
    TextAlign align = TextAlign.left,
  }) =>
      _w.layout(text, size, maxWidth, align);

  static void _text(
    Canvas c,
    String text,
    Offset at, {
    double size = 11,
    bool centerX = false,
    bool centerY = false,
    double maxWidth = 400,
    TextAlign align = TextAlign.left,
  }) {
    if (text.isEmpty) return;
    final tp = _painter(text, size: size, maxWidth: maxWidth, align: align);
    tp.paint(
      c,
      Offset(
        centerX ? at.dx - tp.width / 2 : at.dx,
        centerY ? at.dy - tp.height / 2 : at.dy,
      ),
    );
  }

  static void _rotatedText(Canvas c, String text, Offset at,
      {double size = 11}) {
    if (text.isEmpty) return;
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(-math.pi / 2);
    final tp = _painter(text, size: size, maxWidth: 260);
    tp.paint(c, Offset(-tp.width / 2, 0));
    c.restore();
  }

  /// Аталыш: текст жана анын астына карандаш сызыгы.
  static void _title(_Pc p, Size size, String title) {
    if (title.isEmpty) return;
    final tp = _painter(title,
        size: 13.5, maxWidth: size.width - 20, align: TextAlign.center);
    final x = size.width / 2 - tp.width / 2;
    tp.paint(p.c, Offset(x, 6));
    final y = 6 + tp.height + 1;
    p.line(Offset(x + 2, y), Offset(x + tp.width - 2, y + 0.6), w: 0.9);
  }

  // ----------------------------------------------------------------- график
  static void _marker(_Pc p, int si, Offset o) {
    switch (si % 4) {
      case 0:
        p.dot(o, 2.4);
        break;
      case 1:
        p.rect(Rect.fromCenter(center: o, width: 5.5, height: 5.5), w: 0.8);
        break;
      case 2:
        p.poly([
          Offset(o.dx, o.dy - 3.4),
          Offset(o.dx + 3.2, o.dy + 2.6),
          Offset(o.dx - 3.2, o.dy + 2.6),
        ], closed: true, w: 0.8);
        break;
      default:
        p.poly([
          Offset(o.dx, o.dy - 3.6),
          Offset(o.dx + 3.4, o.dy),
          Offset(o.dx, o.dy + 3.6),
          Offset(o.dx - 3.4, o.dy),
        ], closed: true, w: 0.8);
    }
  }

  static void _hatchBar(_Pc p, int si, Rect r) {
    final rr = r.deflate(0.8);
    if (rr.width < 2 || rr.height < 2) return;
    switch (si % 4) {
      case 0:
        p.hatchRect(rr, spacing: 3.2, angle: math.pi / 4);
        break;
      case 1:
        p.hatchRect(rr, spacing: 3.2, angle: -math.pi / 4);
        break;
      case 2:
        p.hatchRect(rr, spacing: 4.2, angle: math.pi / 4);
        p.hatchRect(rr, spacing: 4.2, angle: -math.pi / 4);
        break;
      default:
        p.hatchRect(rr, spacing: 3.0, angle: 0);
    }
  }

  static void _drawChart(_Pc p, Size size, DiagramSpec spec) {
    final c = p.c;
    final series = spec.series;
    // Y огунун жазуусу сандар менен кабышпасын деп сол жээкти кеңейтебиз
    final left = spec.yLabel.isNotEmpty ? 84.0 : 58.0;
    const right = 16.0;
    // Аталыш 2 сапка чыгып калса, график төмөн жылат
    final titleH = spec.title.isEmpty
        ? 0.0
        : _painter(spec.title,
                size: 13.5, maxWidth: size.width - 20, align: TextAlign.center)
            .height;
    final top = math.max(34.0, 6 + titleH + 12);
    const bottom = 52.0;

    final plot = Rect.fromLTRB(
        left, top, size.width - right, size.height - bottom);

    _title(p, size, spec.title);

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final s in series) {
      for (final pt in s.points) {
        minX = math.min(minX, pt.x);
        maxX = math.max(maxX, pt.x);
        minY = math.min(minY, pt.y);
        maxY = math.max(maxY, pt.y);
      }
    }
    if (!minX.isFinite || !minY.isFinite) return;

    final isBar = spec.chartType == 'bar';

    if (minX == maxX) {
      minX -= 1;
      maxX += 1;
    }
    if (minY == maxY) {
      final d = minY.abs() < 1e-9 ? 1.0 : minY.abs() * 0.1;
      minY -= d;
      maxY += d;
    }

    // Y огу: мамычалуу график ар дайым нөлдөн башталат. Сызыктуу графикте
    // нөл маалыматка жакын турганда гана кошулат — болбосо жылдык көлөм
    // (мисалы 3.6·10⁹) сыяктуу чоң сандар бурчка кысылып, график окулбай
    // калат (мурдагы ката ушул болчу).
    if (isBar) {
      if (minY > 0) minY = 0;
      if (maxY < 0) maxY = 0;
    } else if (minY > 0 && minY <= (maxY - minY) * 0.45) {
      minY = 0;
    }

    final yAxis = _axis(minY, maxY, 5);
    minY = yAxis.$1;
    maxY = yAxis.$2;
    final yTicks = _ticks(yAxis.$1, yAxis.$2, yAxis.$3);

    // X огу эч качан нөлгө мажбурланбайт: жылдар (2000...2025) өз
    // диапазонунда чийилиши керек.
    final List<double> xTicks;
    if (isBar) {
      final xs = <double>{
        for (final s in series)
          for (final pt in s.points) pt.x
      }.toList()
        ..sort();
      final gap =
          xs.length > 1 ? (xs.last - xs.first) / (xs.length - 1) : 1.0;
      minX = xs.first - gap * 0.7;
      maxX = xs.last + gap * 0.7;
      xTicks = xs.length <= 10 ? xs : _ticks(minX, maxX, (maxX - minX) / 5);
    } else {
      final xAxis = _axis(minX, maxX, 5);
      minX = xAxis.$1;
      maxX = xAxis.$2;
      xTicks = _ticks(xAxis.$1, xAxis.$2, xAxis.$3);
    }

    double px(double x) =>
        plot.left + (x - minX) / (maxX - minX) * plot.width;
    double py(double y) =>
        plot.bottom - (y - minY) / (maxY - minY) * plot.height;

    for (final value in yTicks) {
      final y = py(value);
      p.line(Offset(plot.left, y), Offset(plot.right, y), fade: 0.72, w: 0.55);
      final tp = _painter(_fmt(value),
          size: 9, maxWidth: 52, align: TextAlign.right);
      tp.paint(c, Offset(plot.left - 8 - tp.width, y - tp.height / 2));
    }
    for (final value in xTicks) {
      final x = px(value);
      p.line(Offset(x, plot.top), Offset(x, plot.bottom), fade: 0.72, w: 0.55);
      _text(c, _fmt(value), Offset(x, plot.bottom + 5),
          size: 9, centerX: true, maxWidth: 70, align: TextAlign.center);
    }

    // окторду арматура менен (басым күчтүү)
    p.line(Offset(plot.left, plot.top - 8), Offset(plot.left, plot.bottom),
        w: 1.35);
    p.line(Offset(plot.left, plot.bottom), Offset(plot.right + 8, plot.bottom),
        w: 1.35);
    _arrow(p, Offset(plot.left, plot.top - 8), -math.pi / 2);
    _arrow(p, Offset(plot.right + 8, plot.bottom), 0);

    if (spec.xLabel.isNotEmpty) {
      _text(c, spec.xLabel,
          Offset(plot.left + plot.width / 2, plot.bottom + 22),
          size: 10,
          centerX: true,
          maxWidth: plot.width,
          align: TextAlign.center);
    }
    if (spec.yLabel.isNotEmpty) {
      _rotatedText(c, spec.yLabel, Offset(8, plot.top + plot.height / 2),
          size: 10);
    }

    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      final pts = [...s.points]..sort((a, b) => a.x.compareTo(b.x));

      if (isBar) {
        final bw = plot.width / (pts.length * series.length + 1) * 0.8;
        for (var i = 0; i < pts.length; i++) {
          final x = px(pts[i].x) + (si - (series.length - 1) / 2) * bw;
          final r = Rect.fromPoints(
              Offset(x - bw / 2, py(pts[i].y)),
              Offset(x + bw / 2, py(math.max(0, minY))));
          _hatchBar(p, si, r);
          p.rect(r, w: 1.1);
        }
      } else {
        final line = <Offset>[
          for (final pt in pts) Offset(px(pt.x), py(pt.y)),
        ];
        if (spec.chartType != 'scatter' && line.length >= 2) {
          final pat = _dashes[si % _dashes.length];
          if (pat.isEmpty) {
            p.poly(line, w: 1.45);
          } else {
            p.dashed(line, pat, w: 1.35);
          }
        }
        if (pts.length <= 30) {
          for (final o in line) {
            _marker(p, si, o);
          }
        }
      }
    }

    // легенда
    final named = series.where((s) => s.name.isNotEmpty).toList();
    if (named.isNotEmpty) {
      var x = plot.left + 4;
      final y = size.height - 16;
      for (var i = 0; i < named.length; i++) {
        final si = series.indexOf(named[i]);
        if (isBar) {
          final r = Rect.fromLTWH(x, y - 1, 15, 9);
          _hatchBar(p, si, r);
          p.rect(r, w: 0.9);
        } else {
          final pat = _dashes[si % _dashes.length];
          final a = Offset(x, y + 4);
          final b = Offset(x + 16, y + 4);
          if (pat.isEmpty) {
            p.line(a, b, w: 1.3);
          } else {
            p.dashed([a, b], pat, w: 1.2);
          }
          _marker(p, si, Offset(x + 8, y + 4));
        }
        final tp = _painter(named[i].name, size: 9.5);
        tp.paint(c, Offset(x + 21, y - 3));
        x += 21 + tp.width + 16;
        if (x > size.width - 40) break;
      }
    }
  }

  /// Октун чектерин «жумшак» сандарга тегеректейт: кадам 1, 2, 2.5 же 5
  /// × 10ⁿ болот, ошондо белгилер 2000, 2005, 2010 ... болуп окулат.
  /// Кайтарары: (башы, аягы, кадам).
  static (double, double, double) _axis(double min, double max, int divs) {
    if (!(max > min)) return (min, min + 1.0, 1.0);
    final raw = (max - min) / divs;
    final exp = (math.log(raw) / math.ln10).floor();
    final mag = math.pow(10, exp).toDouble();
    final norm = raw / mag;
    final double mult;
    if (norm <= 1) {
      mult = 1.0;
    } else if (norm <= 2) {
      mult = 2.0;
    } else if (norm <= 2.5) {
      mult = 2.5;
    } else if (norm <= 5) {
      mult = 5.0;
    } else {
      mult = 10.0;
    }
    final step = mult * mag;
    final lo = (min / step).floor() * step;
    var hi = (max / step).ceil() * step;
    if (hi <= lo) hi = lo + step;
    return (lo, hi, step);
  }

  static List<double> _ticks(double lo, double hi, double step) {
    if (step <= 0 || !step.isFinite) return [lo, hi];
    final n = ((hi - lo) / step).round().clamp(1, 12);
    return [for (var i = 0; i <= n; i++) lo + step * i];
  }

  static const List<String> _supDigits = [
    '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹',
  ];

  static String _sup(int n) {
    final sign = n < 0 ? '⁻' : '';
    final digits = n.abs().toString();
    final buf = StringBuffer(sign);
    for (final ch in digits.split('')) {
      final i = int.tryParse(ch);
      buf.write(i == null ? ch : _supDigits[i]);
    }
    return buf.toString();
  }

  static String _fmt(double v) {
    if (!v.isFinite) return '';
    if (v == 0) return '0';
    final a = v.abs();
    if (a >= 1e5 || a < 1e-3) {
      final exp = (math.log(a) / math.ln10).floor();
      final mant = v / math.pow(10, exp);
      final ms = mant.abs() >= 9.995
          ? mant.toStringAsFixed(0)
          : mant.toStringAsFixed(1);
      return '$ms·10${_sup(exp)}';
    }
    if (v == v.roundToDouble()) return v.toInt().toString();
    if (a >= 100) return v.toStringAsFixed(0);
    if (a >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  static void _arrow(_Pc p, Offset tip, double angle) {
    const len = 7.0;
    const spread = 0.42;
    for (final s in [-spread, spread]) {
      final a = angle + math.pi + s;
      p.line(tip, tip + Offset(math.cos(a) * len, math.sin(a) * len), w: 1.1);
    }
  }

  // ---------------------------------------------------------- электр схема
  static void _drawCircuit(_Pc p, Size size, DiagramSpec spec) {
    final c = p.c;
    _title(p, size, spec.title);

    final parallel = spec.circuitLayout.startsWith('par');
    final elements = spec.elements;
    final top = spec.title.isNotEmpty ? 72.0 : 46.0;
    final rect = Rect.fromLTRB(60, top, size.width - 40, size.height - 34);

    // булак (сол тарапта)
    _battery(p, Offset(rect.left, rect.center.dy));
    if (spec.sourceLabel.isNotEmpty) {
      _text(c, spec.sourceLabel, Offset(rect.left - 8, rect.center.dy + 22),
          size: 10, centerX: true, maxWidth: 110, align: TextAlign.center);
    }

    if (!parallel) {
      // сериялык: жогорку сапта бардык элементтер
      p.line(Offset(rect.left, rect.center.dy - 14),
          Offset(rect.left, rect.top));
      p.line(Offset(rect.left, rect.center.dy + 14),
          Offset(rect.left, rect.bottom));
      p.line(Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom));
      p.line(Offset(rect.right, rect.bottom), Offset(rect.right, rect.top));

      final span = rect.width / elements.length;
      var x = rect.left;
      for (var i = 0; i < elements.length; i++) {
        final centre = x + span / 2;
        p.line(Offset(x, rect.top), Offset(centre - 21, rect.top));
        _element(p, elements[i], Offset(centre, rect.top),
            maxLabelWidth: span - 8);
        p.line(Offset(centre + 21, rect.top), Offset(x + span, rect.top));
        x += span;
      }
    } else {
      // параллель: ар бир элемент өзүнчө бутакта
      p.line(Offset(rect.left, rect.center.dy - 14),
          Offset(rect.left, rect.top));
      p.line(Offset(rect.left, rect.center.dy + 14),
          Offset(rect.left, rect.bottom));
      p.line(Offset(rect.left, rect.top), Offset(rect.left + 40, rect.top));
      p.line(Offset(rect.left, rect.bottom),
          Offset(rect.left + 40, rect.bottom));

      final branchLeft = rect.left + 40;
      final branchRight = rect.right - 40;
      p.line(Offset(branchLeft, rect.top), Offset(branchLeft, rect.bottom));
      p.line(Offset(branchRight, rect.top), Offset(branchRight, rect.bottom));
      p.line(Offset(branchRight, rect.top), Offset(rect.right, rect.top));
      p.line(Offset(rect.right, rect.top), Offset(rect.right, rect.bottom));
      p.line(Offset(rect.right, rect.bottom), Offset(branchRight, rect.bottom));

      final step = rect.height / elements.length;
      for (var i = 0; i < elements.length; i++) {
        final y = rect.top + step * (i + 0.5);
        final centre = (branchLeft + branchRight) / 2;
        p.line(Offset(branchLeft, y), Offset(centre - 21, y));
        _element(p, elements[i], Offset(centre, y),
            maxLabelWidth: branchRight - branchLeft - 8);
        p.line(Offset(centre + 21, y), Offset(branchRight, y));
      }
    }
  }

  static void _battery(_Pc p, Offset at) {
    // узун сызык = плюс, кыска = минус
    p.line(at + const Offset(-11, -14), at + const Offset(11, -14), w: 1.25);
    p.line(at + const Offset(-6, -6), at + const Offset(6, -6), w: 1.25);
    p.line(at + const Offset(-11, 2), at + const Offset(11, 2), w: 1.25);
    p.line(at + const Offset(-6, 10), at + const Offset(6, 10), w: 1.25);
    p.line(at + const Offset(0, -20), at + const Offset(0, -14));
    p.line(at + const Offset(0, 10), at + const Offset(0, 16));
  }

  static void _element(_Pc p, CircuitElement el, Offset centre,
      {double maxLabelWidth = 110}) {
    final kind = el.kind.isEmpty ? 'R' : el.kind[0].toUpperCase();
    switch (kind) {
      case 'C': // конденсатор
        p.line(centre + const Offset(-21, 0), centre + const Offset(-4, 0));
        p.line(centre + const Offset(-4, -11), centre + const Offset(-4, 11),
            w: 1.25);
        p.line(centre + const Offset(4, -11), centre + const Offset(4, 11),
            w: 1.25);
        p.line(centre + const Offset(4, 0), centre + const Offset(21, 0));
        break;
      case 'L': // катушка
        p.line(centre + const Offset(-21, 0), centre + const Offset(-15, 0));
        for (var i = 0; i < 4; i++) {
          p.arc(
            Rect.fromCircle(
                center: centre + Offset(-11 + i * 7.5, 0), radius: 3.9),
            math.pi,
            math.pi,
          );
        }
        p.line(centre + const Offset(18, 0), centre + const Offset(21, 0));
        break;
      case 'D': // диод
        final tri = [
          Offset(centre.dx - 8, centre.dy - 8),
          Offset(centre.dx + 6, centre.dy),
          Offset(centre.dx - 8, centre.dy + 8),
        ];
        p.hatchPoly(tri, spacing: 2.2, angle: math.pi / 4, fade: 0.05);
        p.poly(tri, closed: true);
        p.line(centre + const Offset(6, -9), centre + const Offset(6, 9),
            w: 1.25);
        p.line(centre + const Offset(-21, 0), centre + const Offset(-8, 0));
        p.line(centre + const Offset(6, 0), centre + const Offset(21, 0));
        break;
      case 'S': // ачкыч
        p.line(centre + const Offset(-21, 0), centre + const Offset(-9, 0));
        p.line(centre + const Offset(-9, 0), centre + const Offset(7, -10));
        p.line(centre + const Offset(9, 0), centre + const Offset(21, 0));
        p.dot(centre + const Offset(-9, 0), 2);
        p.dot(centre + const Offset(9, 0), 2);
        break;
      case 'M': // мотор / жүктөм
        p.circle(centre, 12);
        _text(p.c, 'M', centre,
            size: 11,
            centerX: true,
            centerY: true,
            maxWidth: 24,
            align: TextAlign.center);
        p.line(centre + const Offset(-21, 0), centre + const Offset(-12, 0));
        p.line(centre + const Offset(12, 0), centre + const Offset(21, 0));
        break;
      default: // резистор
        p.line(centre + const Offset(-21, 0), centre + const Offset(-15, 0));
        p.rect(Rect.fromCenter(center: centre, width: 30, height: 13));
        p.line(centre + const Offset(15, 0), centre + const Offset(21, 0));
    }

    if (el.label.isNotEmpty) {
      _text(p.c, el.label, centre + const Offset(0, -27),
          size: 10,
          centerX: true,
          maxWidth: math.max(60, maxLabelWidth),
          align: TextAlign.center);
    }
  }

  // ------------------------------------------------------------ блок-схема
  static void _drawBlocks(_Pc p, Size size, DiagramSpec spec) {
    final nodes = spec.nodes;
    final shapes = spec.nodeShapes;

    _title(p, size, spec.title);

    final boxW = size.width - 120;
    const boxH = 42.0;
    const stepY = 64.0;
    // Аталыш эки сапка чыкса, биринчи кутуча анын үстүнө кирип калбасын деп
    // аталыштын чыныгы бийиктигине жараша баштайбыз.
    final startY = spec.title.isEmpty
        ? 10.0
        : 6 +
            _painter(spec.title,
                    size: 13.5,
                    maxWidth: size.width - 20,
                    align: TextAlign.center)
                .height +
            14;

    for (var i = 0; i < nodes.length; i++) {
      final cy = startY + i * stepY + boxH / 2;
      final rect = Rect.fromCenter(
          center: Offset(size.width / 2, cy), width: boxW, height: boxH);
      final shape = i < shapes.length ? shapes[i] : '';
      final isTerminal = shape.startsWith('start') ||
          shape.startsWith('end') ||
          shape.startsWith('term') ||
          i == 0 ||
          i == nodes.length - 1;
      final isDecision = shape.startsWith('dec') || shape.startsWith('if');

      // Ромб текстти толук камтышы үчүн кадимкиден кенен жана бийик болот.
      final dw = isDecision ? rect.width / 2 + 24 : 0.0;
      final dh = isDecision ? rect.height / 2 + 10 : 0.0;
      if (isDecision) {
        p.poly([
          Offset(rect.center.dx, rect.center.dy - dh),
          Offset(rect.center.dx + dw, rect.center.dy),
          Offset(rect.center.dx, rect.center.dy + dh),
          Offset(rect.center.dx - dw, rect.center.dy),
        ], closed: true, w: 1.2);
      } else if (isTerminal) {
        p.rrect(rect, boxH / 2, w: 1.2);
      } else {
        p.rect(rect, w: 1.2);
      }

      _text(p.c, nodes[i], rect.center,
          size: 10.5,
          centerX: true,
          centerY: true,
          maxWidth: isDecision ? rect.width - 48 : boxW - 26,
          align: TextAlign.center);

      if (i < nodes.length - 1) {
        final from = Offset(
            size.width / 2, isDecision ? rect.center.dy + dh : rect.bottom);
        final to = Offset(size.width / 2, rect.bottom + (stepY - boxH));
        p.line(from, to, w: 1.2);
        _arrow(p, to, math.pi / 2);
      }
    }
  }
}

/// Canvas'ка карандаш менен чийүүчү кичине жардамчы.
class _Pc {
  final Canvas c;
  final Pencil pen;

  _Pc(this.c, int seed)
      : pen = Pencil(seed, amp: 0.55, width: 1.1, step: 1.6, chunk: 4);

  void _draw(List<PencilStroke> strokes) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      final q = s.pts;
      if (q.length < 4) continue;
      final path = Path()..moveTo(q[0], q[1]);
      for (var i = 2; i + 1 < q.length; i += 2) {
        path.lineTo(q[i], q[i + 1]);
      }
      paint
        ..strokeWidth = s.width
        ..color = Color.fromARGB(255, s.gray, s.gray, s.gray);
      c.drawPath(path, paint);
    }
  }

  void line(Offset a, Offset b, {double fade = 0, double w = 1}) =>
      _draw(pen.line(a.dx, a.dy, b.dx, b.dy, fade: fade, wScale: w));

  void rect(Rect r, {double w = 1}) =>
      _draw(pen.rect(r.left, r.top, r.right, r.bottom, wScale: w));

  void rrect(Rect r, double rad, {double w = 1}) =>
      _draw(pen.rrect(r.left, r.top, r.right, r.bottom, rad, wScale: w));

  void circle(Offset ctr, double rad, {double w = 1}) =>
      _draw(pen.ellipse(ctr.dx, ctr.dy, rad, rad, wScale: w));

  void arc(Rect r, double start, double sweep, {double w = 1}) => _draw(
      pen.ellipse(r.center.dx, r.center.dy, r.width / 2, r.height / 2,
          start: start, sweep: sweep, wScale: w));

  List<double> _flat(List<Offset> pts) =>
      [for (final o in pts) ...[o.dx, o.dy]];

  void poly(List<Offset> pts, {bool closed = false, double w = 1}) {
    final f = _flat(pts);
    _draw(closed ? pen.closed(f, wScale: w) : pen.polyline(f, wScale: w));
  }

  void dashed(List<Offset> pts, List<double> pattern, {double w = 1}) =>
      _draw(pen.dashed(_flat(pts), pattern, wScale: w));

  void hatchRect(Rect r,
          {double spacing = 3.5, double angle = math.pi / 4, double fade = 0.35}) =>
      _draw(pen.hatchRect(r.left, r.top, r.right, r.bottom,
          spacing: spacing, angle: angle, fade: fade));

  void hatchPoly(List<Offset> pts,
          {double spacing = 3.5, double angle = math.pi / 4, double fade = 0.35}) =>
      _draw(pen.hatchPoly(_flat(pts),
          spacing: spacing, angle: angle, fade: fade));

  /// Карандаш менен кичине толтурулган чекит.
  void dot(Offset o, double r) {
    c.drawCircle(o, r * 0.85, Paint()..color = const Color(0xFF3A3A3A));
    _draw(pen.ellipse(o.dx, o.dy, r, r, wScale: 0.8));
  }
}

/// Бир жазуунун даяр макети: өлчөмү жана чийүү.
abstract class _Txt {
  double get width;
  double get height;
  void paint(Canvas c, Offset at);
}

class _FontTxt implements _Txt {
  final TextPainter tp;
  _FontTxt(this.tp);
  @override
  double get width => tp.width;
  @override
  double get height => tp.height;
  @override
  void paint(Canvas c, Offset at) => tp.paint(c, at);
}

class _Line {
  final ui.Image? image;
  final double w;
  final double h;
  _Line(this.image, this.w, this.h);
}

/// Колдонуучунун өз кол жазмасы менен жазылган жазуу (саптар сүрөт түрүндө).
class _HandTxt implements _Txt {
  final List<_Line> lines;
  final TextAlign align;
  _HandTxt(this.lines, this.align);
  @override
  double get width => lines.fold(0.0, (m, l) => math.max(m, l.w));
  @override
  double get height => lines.fold(0.0, (s, l) => s + l.h);
  @override
  void paint(Canvas c, Offset at) {
    final full = width;
    var y = at.dy;
    final paint = Paint()..filterQuality = FilterQuality.high;
    for (final l in lines) {
      final img = l.image;
      if (img != null) {
        final dx = align == TextAlign.center
            ? (full - l.w) / 2
            : align == TextAlign.right
                ? full - l.w
                : 0.0;
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(at.dx + dx, y, l.w, l.h),
          paint,
        );
      }
      y += l.h;
    }
  }
}

/// Аралаш жазуунун бир кесими: кол жазма сап (сүрөт) же шрифт.
class _MixPiece {
  final _Line? hand;
  final TextPainter? font;
  final double w;
  final double h;

  /// Жогорудан жазуу сызыгына чейинки аралык.
  final double base;

  /// Индекс үчүн жылдыруу (+ ылдый, − өйдө).
  final double dy;
  _MixPiece(this.hand, this.font, this.w, this.h, this.base, this.dy);
}

class _MixPlaced {
  final _MixPiece piece;
  final double x;
  final double top;
  _MixPlaced(this.piece, this.x, this.top);
}

class _MixLine {
  final List<_MixPlaced> items;
  final double width;
  final double height;
  _MixLine(this.items, this.width, this.height);
}

/// Бир сапта кол жазма жана шрифт кесимдери аралаш жазылган жазуу.
class _MixTxt implements _Txt {
  final List<_MixLine> lines;
  final TextAlign align;
  _MixTxt(this.lines, this.align);
  @override
  double get width => lines.fold(0.0, (m, l) => math.max(m, l.width));
  @override
  double get height => lines.fold(0.0, (s, l) => s + l.height);
  @override
  void paint(Canvas c, Offset at) {
    final full = width;
    var y = at.dy;
    final paint = Paint()..filterQuality = FilterQuality.high;
    for (final l in lines) {
      final dx = align == TextAlign.center
          ? (full - l.width) / 2
          : align == TextAlign.right
              ? full - l.width
              : 0.0;
      for (final it in l.items) {
        final pc = it.piece;
        final ox = at.dx + dx + it.x;
        final oy = y + it.top;
        final img = pc.hand?.image;
        final tp = pc.font;
        if (img != null) {
          c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(ox, oy, pc.w, pc.h),
            paint,
          );
        } else if (tp != null) {
          tp.paint(c, Offset(ox, oy));
        }
      }
      y += l.height;
    }
  }
}

/// Диаграммадагы жазууларды кайсы кол жазма менен жазууну чечет.
///  - кол жазма жок: карандаш менен жазгандай шрифт (графит түс);
///  - даяр кол жазма шрифти: ошол шрифт, ручканын көк сыясы;
///  - «Менин кол жазмам»: колдонуучунун өз тамгалары (сүрөттөр).
class _Writer {
  final HandwritingStyle? style;
  final MyHandwriting? mine;
  bool collecting = false;

  /// Кол жазма сүрөттөрү: ачкыч -> саптар.
  final Map<String, List<HwLineImage>> _pending = {};
  final Map<String, List<_Line>> _ready = {};

  _Writer(this.style, this.mine);

  static const Color _penInk = Color(0xFF1F2F7A);
  static const Color _lead = Color(0xFF2B2B2B);

  _Txt _font(String text, double size, double maxWidth, TextAlign align) {
    final st = style;
    final font = (st != null && st.asset.isNotEmpty) ? st : null;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: st == null ? _lead : _penInk,
          fontFamily: font != null ? font.family : 'hw_pangolin',
          fontSize: size * (font != null ? font.scale * 1.12 : 1.08),
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return _FontTxt(tp);
  }

  _Txt layout(String text, double size, double maxWidth, TextAlign align) {
    final hw = mine;
    if (hw == null || text.trim().isEmpty) {
      return _font(text, size, maxWidth, align);
    }
    // Кол жазмада жок белги (_, *, π, ħ ...) бар болсо, бүт жазууну шрифтке
    // которбойбуз: жок белгини гана шрифт менен, калганын өз кол жазма менен
    // жазабыз. `_n` — астыңкы, `^2` — үстүңкү индекс.
    if (!HwRender.canWrite(hw, text)) {
      return _mix(hw, text, size, maxWidth, align);
    }
    final key = '${size.toStringAsFixed(2)}|${maxWidth.round()}|$text';
    if (collecting) {
      final lines = _pending[key] ??= HwRender.renderParagraph(
        hw,
        text,
        sizePt: size * 1.2,
        availPt: maxWidth,
        lineHeight: 1.3,
        seed: text.hashCode,
      );
      return _HandTxt(
          [for (final l in lines) _Line(null, l.widthPt, l.heightPt)], align);
    }
    final ready = _ready[key];
    if (ready == null) return _font(text, size, maxWidth, align);
    return _HandTxt(ready, align);
  }

  static const double _subMul = 0.62;

  /// Текстти (текст, масштаб, жылдыруу) бөлүктөрүнө бөлөт.
  /// `_x`, `_{..}` — астыңкы индекс; `^x`, `^{..}` — үстүңкү индекс.
  /// Боштук `null` текст менен белгиленет.
  List<(String?, double, double)> _atoms(String text) {
    final cs = text.runes.map(String.fromCharCode).toList();
    final out = <(String?, double, double)>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        out.add((buf.toString(), 1.0, 0.0));
        buf.clear();
      }
    }

    var i = 0;
    while (i < cs.length) {
      final ch = cs[i];
      if (ch.trim().isEmpty) {
        flush();
        if (out.isNotEmpty && out.last.$1 != null) out.add((null, 1.0, 0.0));
        i++;
        continue;
      }
      if ((ch == '_' || ch == '^') &&
          i > 0 &&
          cs[i - 1].trim().isNotEmpty &&
          i + 1 < cs.length &&
          cs[i + 1].trim().isNotEmpty) {
        flush();
        final up = ch == '^';
        var j = i + 1;
        String sub;
        if (cs[j] == '{') {
          final end = cs.indexOf('}', j);
          if (end > j + 1) {
            sub = cs.sublist(j + 1, end).join();
            j = end + 1;
          } else {
            sub = cs[j];
            j++;
          }
        } else {
          sub = cs[j];
          j++;
        }
        out.add((sub, _subMul, up ? -0.42 : 0.20));
        i = j;
        continue;
      }
      buf.write(ch);
      i++;
    }
    flush();
    return out;
  }

  /// Бир бөлүктү өз кол жазма менен жазат (сап сүрөтү). Болбосо null.
  _MixPiece? _handPiece(MyHandwriting hw, String run, double size, double dy) {
    final key = 'm|${size.toStringAsFixed(2)}|$run';
    List<_Line>? ready;
    if (collecting) {
      final lines = _pending[key] ??= HwRender.renderParagraph(
        hw,
        run,
        sizePt: size * 1.2,
        availPt: run.length * size * 1.3 + 40,
        lineHeight: 1.3,
        seed: run.hashCode,
      );
      if (lines.isEmpty) return null;
      final l = lines.first;
      ready = [_Line(null, l.widthPt, l.heightPt)];
    } else {
      ready = _ready[key];
    }
    if (ready == null || ready.isEmpty) return null;
    final l = ready.first;
    return _MixPiece(l, null, l.w, l.h, l.h * 0.70, dy);
  }

  /// Кол жазмада жок белги үчүн: кол жазма шрифти, ошол эле көк сыя.
  _MixPiece _fontPiece(String run, double size, double dy) {
    const st = HandwritingStyle.marckKg;
    final tp = TextPainter(
      text: TextSpan(
        text: run,
        style: TextStyle(
          color: _penInk,
          fontFamily: st.family,
          fontSize: size * st.scale * 1.12,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    return _MixPiece(null, tp, tp.width, tp.height, base, dy);
  }

  /// Аралаш жазуу: жазылса боло турган бөлүк — өз кол жазма, жок белгилер —
  /// шрифт. Сөздөр орун жетпесе кийинки сапка өтөт.
  _Txt _mix(MyHandwriting hw, String text, double size, double maxWidth,
      TextAlign align) {
    final words = <List<_MixPiece>>[];
    var cur = <_MixPiece>[];
    for (final a in _atoms(text)) {
      final t = a.$1;
      if (t == null) {
        if (cur.isNotEmpty) {
          words.add(cur);
          cur = <_MixPiece>[];
        }
        continue;
      }
      final sz = size * a.$2;
      final dy = a.$3 * size;
      final runs = <(String, bool)>[];
      for (final ch in t.runes.map(String.fromCharCode)) {
        final ok = ch.trim().isEmpty || HwRender.canWrite(hw, ch);
        if (runs.isNotEmpty && runs.last.$2 == ok) {
          runs[runs.length - 1] = (runs.last.$1 + ch, ok);
        } else {
          runs.add((ch, ok));
        }
      }
      for (final r in runs) {
        _MixPiece? piece;
        if (r.$2) piece = _handPiece(hw, r.$1, sz, dy);
        cur.add(piece ?? _fontPiece(r.$1, sz, dy));
      }
    }
    if (cur.isNotEmpty) words.add(cur);

    final space = size * 0.47;
    final lines = <_MixLine>[];
    var items = <(_MixPiece, double)>[];
    var x = 0.0;
    void endLine() {
      if (items.isEmpty) return;
      var base = 0.0;
      for (final it in items) {
        base = math.max(base, it.$1.base - it.$1.dy);
      }
      var h = 0.0;
      final placed = <_MixPlaced>[];
      for (final it in items) {
        final top = base - it.$1.base + it.$1.dy;
        placed.add(_MixPlaced(it.$1, it.$2, top));
        h = math.max(h, top + it.$1.h);
      }
      lines.add(_MixLine(placed, x, h));
      items = <(_MixPiece, double)>[];
      x = 0.0;
    }

    for (final w in words) {
      final ww = w.fold(0.0, (s, pc) => s + pc.w);
      if (items.isNotEmpty && x + space + ww > maxWidth) endLine();
      if (items.isNotEmpty) x += space;
      for (final pc in w) {
        items.add((pc, x));
        x += pc.w;
      }
    }
    endLine();
    if (lines.isEmpty) return _font(text, size, maxWidth, align);
    return _MixTxt(lines, align);
  }

  /// Чогултулган кол жазма саптарын ui.Image'ге айландырат.
  Future<void> decodeAll() async {
    for (final e in _pending.entries) {
      final out = <_Line>[];
      for (final l in e.value) {
        final codec = await ui.instantiateImageCodec(l.png);
        final frame = await codec.getNextFrame();
        codec.dispose();
        out.add(_Line(frame.image, l.widthPt, l.heightPt));
      }
      _ready[e.key] = out;
    }
    _pending.clear();
  }

  void dispose() {
    for (final ls in _ready.values) {
      for (final l in ls) {
        l.image?.dispose();
      }
    }
    _ready.clear();
  }
}
