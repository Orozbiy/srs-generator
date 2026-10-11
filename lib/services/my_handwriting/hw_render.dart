import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'hw_profile.dart';

/// Бир сап текст: тунук фондогу PNG сүрөт жана анын PDF'теги өлчөмү (pt).
class HwLineImage {
  final Uint8List png;
  final double widthPt;
  final double heightPt;
  const HwLineImage(this.png, this.widthPt, this.heightPt);
}

/// Текстти колдонуучунун өз тамгалары менен жазат.
class HwRender {
  /// 1 pt = 4 пиксель (~288 dpi).
  static const int ppp = 4;

  // Сыянын түсү (көк): 0xFF1F2F7A менен бирдей.
  static const int _inkR = 0x1F;
  static const int _inkG = 0x2F;
  static const int _inkB = 0x7A;


  /// Үстүңкү/астыңкы индекстер: негизги тамганын кичирейтилген түрү.
  /// [ch] -> (негизги белги, масштаб, көтөрүү — xh үлүшү).
  static const Map<String, String> _supMap = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3',
    '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7',
    '⁸': '8', '⁹': '9', '⁺': '+', '⁻': '-',
    '⁽': '(', '⁾': ')', 'ⁿ': 'n', 'ⁱ': 'i',
  };
  static const Map<String, String> _subMap = {
    '₀': '0', '₁': '1', '₂': '2', '₃': '3',
    '₄': '4', '₅': '5', '₆': '6', '₇': '7',
    '₈': '8', '₉': '9', '₊': '+', '₋': '-',
    '₍': '(', '₎': ')',
  };
  static const double _idxScale = 0.62;

  /// Белгини чийүү үчүн глиф, масштаб көбөйткүч жана көтөрүү (xh үлүшү).
  static (HwGlyph?, double, double) _resolve(MyHandwriting hw, String ch) {
    final g = hw.glyphFor(ch);
    if (g != null) return (g, 1.0, 0.0);
    final up = _supMap[ch];
    if (up != null) {
      final b = hw.glyphFor(up);
      if (b != null) return (b, _idxScale, 0.55);
    }
    final dn = _subMap[ch];
    if (dn != null) {
      final b = hw.glyphFor(dn);
      if (b != null) return (b, _idxScale, -0.22);
    }
    return (null, 1.0, 0.0);
  }

  /// Тексттин бардык белгилерин бул кол жазма менен жазса болобу
  /// (бир тамга/цифра жок болсо — false).
  static bool canWrite(MyHandwriting hw, String text) {
    for (final ch in text.split('')) {
      if (ch.trim().isEmpty) continue;
      if (_resolve(hw, ch).$1 == null) return false;
    }
    return true;
  }

  static double _u(math.Random r, double a, double b) =>
      a + (b - a) * r.nextDouble();

  /// Бир сөздүн тамгаларын жайгаштырат. Мурунку тамганын чыгуу чекити менен
  /// кийинки тамганын кирүү чекити бири-бирине жакын турат, ошондуктан улоо
  /// сызыгы кыска жана жылмакай болот. [rnd] берилсе масштабга бир аз кокустук
  /// кошулат (өлчөө үчүн null).
  static (List<_Pl>, double) _layoutWord(
    MyHandwriting hw,
    String word,
    double f0,
    double xhT,
    double gap,
    bool connect,
    math.Random? rnd,
  ) {
    final out = <_Pl>[];
    final gxh = hw.xHeight; // глиф пикселдериндеги x-бийиктик
    final chars = word.split('');
    HwGlyph? pg;
    double pf = 1;
    double pLeft = 0;
    double pW = 0;
    String? pch;
    var cur = 0.0; // кийинки тамга үчүн кадимки (улоосуз) орун

    for (final ch in chars) {
      final r = _resolve(hw, ch);
      final g = r.$1;
      if (g == null) {
        out.add(_Pl(null, 1, 0, 1, cur, 0.5 * xhT, false));
        cur += 0.5 * xhT + gap;
        pg = null;
        pch = null;
        continue;
      }
      final f = f0 * r.$2 * (rnd == null ? 1.0 : _u(rnd, 0.985, 1.015));
      final nw = math.max(1, (g.w * f).ceil()).toDouble();
      var left = cur;
      var joined = false;
      if (connect &&
          pg != null &&
          pch != null &&
          _isLower(pch) &&
          _isLower(ch)) {
        final ex = pg.exitJoin(gxh);
        final en = g.entryJoin(gxh);
        if (ex != null && en != null) {
          final exAbs = pLeft + ex.x * pf;
          final enRel = en.x * f;
          var l = exAbs + 0.30 * xhT - enRel;
          final minLeft = pLeft + pW + 0.10 * xhT;
          if (l < minLeft) l = minLeft;
          final len = l + enRel - exAbs;
          if (len <= 1.0 * xhT) {
            left = l;
            joined = true;
          }
        }
      }
      out.add(_Pl(g, r.$2, r.$3, f, left, nw, joined));
      pg = g;
      pf = f;
      pLeft = left;
      pW = nw;
      pch = ch;
      cur = left + nw + gap;
    }
    return (out, cur);
  }

  /// [text] абзацын [availPt] туурасына сыйгыдай саптарга бөлүп сүрөткө айландырат.
  static List<HwLineImage> renderParagraph(
    MyHandwriting hw,
    String text, {
    required double sizePt,
    required double availPt,
    double lineHeight = 1.5,
    bool underline = false,
    bool connect = true,
    int seed = 1,
  }) {
    final xhT = sizePt * 0.46 * ppp; // максаттагы x-бийиктик (px)
    final f0 = xhT / hw.xHeight;
    final gap = connect ? 0.08 * xhT : 0.06 * xhT;
    final space = 0.85 * xhT;
    final availPx = availPt * ppp;
    if (availPx < 40) return const <HwLineImage>[];

    double wordWidth(String wd) {
      final lay = _layoutWord(hw, wd, f0, xhT, gap, connect, null);
      // кокус масштаб үчүн 2% запас
      return lay.$2 * 1.02;
    }

    // --- саптарга бөлүү (ач көз ыкма)
    final lines = <List<String>>[];
    for (final para in text.split('\n')) {
      final words = para.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) continue;
      var cur = <String>[];
      var cw = 0.0;
      for (final wd in words) {
        final ww = wordWidth(wd);
        if (cur.isNotEmpty && cw + space + ww > availPx) {
          lines.add(cur);
          cur = [wd];
          cw = ww;
        } else {
          cw = cw + (cur.isNotEmpty ? space : 0) + ww;
          cur.add(wd);
        }
      }
      if (cur.isNotEmpty) lines.add(cur);
    }

    final rnd = math.Random(seed);
    final lineH = (sizePt * lineHeight * ppp).round();
    final width = availPx.floor();
    final result = <HwLineImage>[];
    final gxh = hw.xHeight;

    for (final ws in lines) {
      final buf = Float32List(width * lineH);
      final base = (lineH * 0.70).round() + (_u(rnd, -0.015, 0.015) * xhT).round();
      var x = 0.0;
      for (var wi = 0; wi < ws.length; wi++) {
        if (wi > 0) x += space;
        final lay = _layoutWord(hw, ws[wi], f0, xhT, gap, connect, rnd);
        _Pl? prev;
        int prevTop = 0;
        int prevLeft = 0;
        for (final pl in lay.$1) {
          final g = pl.g;
          if (g == null) {
            prev = null;
            continue;
          }
          final top = (base -
                  g.baseOff * pl.f -
                  pl.lift * xhT +
                  _u(rnd, -0.012, 0.012) * xhT)
              .round();
          final left = (x + pl.left).round();
          if (pl.joined && prev != null) {
            final pg = prev.g!;
            final ex = pg.exitJoin(gxh);
            final en = g.entryJoin(gxh);
            if (ex != null && en != null) {
              _drawJoin(
                buf,
                width,
                lineH,
                prevLeft + ex.x * prev.f,
                prevTop + ex.y * prev.f,
                left + en.x * pl.f,
                top + en.y * pl.f,
                pg.strokeW * prev.f,
                g.strokeW * pl.f,
                xhT,
                ex.tx,
                ex.ty,
                en.tx,
                en.ty,
              );
            }
          }
          _drawGlyph(buf, width, lineH, g, pl.f, left, top);
          prev = pl;
          prevTop = top;
          prevLeft = left;
        }
        x += lay.$2;
      }

      if (underline) {
        final th = math.max(2, (0.09 * xhT).round());
        final y0 = base + (0.5 * xhT).round();
        final slope = _u(rnd, -0.002, 0.002);
        final xe = math.min(width, x.ceil());
        for (var xx = 0; xx < xe; xx++) {
          final yy = y0 + (slope * xx).round();
          for (var t = 0; t < th; t++) {
            final y = yy + t;
            if (y < 0 || y >= lineH) continue;
            final i = y * width + xx;
            buf[i] = 1 - (1 - buf[i]) * (1 - 0.85);
          }
        }
      }

      final usedW = math.max(4, math.min(width, x.ceil() + 4));
      final rgba = Uint8List(usedW * lineH * 4);
      for (var y = 0; y < lineH; y++) {
        for (var xx = 0; xx < usedW; xx++) {
          final a = buf[y * width + xx];
          final o = (y * usedW + xx) * 4;
          rgba[o] = _inkR;
          rgba[o + 1] = _inkG;
          rgba[o + 2] = _inkB;
          rgba[o + 3] = a <= 0 ? 0 : (a >= 1 ? 255 : (a * 255).round());
        }
      }
      result.add(HwLineImage(
          encodePng(usedW, lineH, rgba), usedW / ppp, lineH / ppp));
    }
    return result;
  }

  /// Кичине тамга (улана турган) белгиби.
  static bool _isLower(String ch) {
    if (!_joinable(ch)) return false;
    return ch == ch.toLowerCase() && ch != ch.toUpperCase();
  }

  /// Улоочу сызык тартылабы (тыныш белгилерине тартылбайт).
  static bool _joinable(String ch) {
    final c = ch.codeUnitAt(0);
    // Тамгалар гана уланат: кирилл, латын (цифра, белги, индекс уланбайт).
    return (c >= 0x0410 && c <= 0x044F) ||
        c == 0x0451 ||
        c == 0x0401 ||
        (c >= 0x04A2 && c <= 0x04AF) ||
        (c >= 0x04E8 && c <= 0x04E9) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A);
  }

  /// Эки тамганы кол менен жазгандай жылмакай (Безье) сызык менен улайт.
  /// (x0,y0) — мурунку тамганын чыгуу чекити, (x1,y1) — кийинкисинин кирүүчү
  /// чекити; th0/th1 — ошол жердеги сызыктын жоондугу.
  static void _drawJoin(Float32List buf, int bw, int bh, double x0, double y0,
      double x1, double y1, double th0, double th1, double xh,
      [double t0x = 1, double t0y = 0, double t1x = 1, double t1y = 0]) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.5) return;
    // Сызык тамгадан чыгып жаткан багытта чыгып, кийинки тамганын багыты
    // менен кирет — ошондуктан бурулуштары жылмакай (улана жазууга окшош).
    final c1x = x0 + t0x * len * 0.45;
    final c1y = y0 + t0y * len * 0.45;
    final c2x = x1 - t1x * len * 0.45;
    final c2y = y1 - t1y * len * 0.45;
    final n = math.max(8, (len * 2.5).ceil());
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final mt = 1 - t;
      final px = mt * mt * mt * x0 +
          3 * mt * mt * t * c1x +
          3 * mt * t * t * c2x +
          t * t * t * x1;
      final py = mt * mt * mt * y0 +
          3 * mt * mt * t * c1y +
          3 * mt * t * t * c2y +
          t * t * t * y1;
      // жоондук аздап ортосунда ичкерет
      var th = th0 + (th1 - th0) * t;
      th *= 1 - 0.14 * math.sin(math.pi * t);
      final r = math.max(0.7, th / 2);
      final xa = (px - r - 1).floor();
      final xb = (px + r + 1).ceil();
      final ya = (py - r - 1).floor();
      final yb = (py + r + 1).ceil();
      for (var yy = ya; yy <= yb; yy++) {
        if (yy < 0 || yy >= bh) continue;
        for (var xx = xa; xx <= xb; xx++) {
          if (xx < 0 || xx >= bw) continue;
          final ddx = xx + 0.5 - px;
          final ddy = yy + 0.5 - py;
          var v = r + 0.5 - math.sqrt(ddx * ddx + ddy * ddy);
          if (v <= 0) continue;
          if (v > 1) v = 1;
          final idx = yy * bw + xx;
          if (v > buf[idx]) buf[idx] = v;
        }
      }
    }
  }

  /// Бир тамганы текшерүү үчүн PNG кылып берет.
  static Uint8List glyphPng(HwGlyph g) {
    final rgba = Uint8List(g.w * g.h * 4);
    for (var i = 0; i < g.w * g.h; i++) {
      final o = i * 4;
      rgba[o] = _inkR;
      rgba[o + 1] = _inkG;
      rgba[o + 2] = _inkB;
      rgba[o + 3] = g.alpha[i];
    }
    return encodePng(g.w, g.h, rgba);
  }

  /// Глифти [f] масштабында чийет. Кайтарат: чийилген туурасы (px).
  static int _drawGlyph(Float32List buf, int bw, int bh, HwGlyph g, double f,
      int left, int top) {
    final nw = math.max(1, (g.w * f).ceil());
    final nh = math.max(1, (g.h * f).ceil());
    final ii = g.integral;
    final iw = g.w + 1;
    for (var y = 0; y < nh; y++) {
      final dy = top + y;
      if (dy < 0 || dy >= bh) continue;
      var sy0 = (y / f).floor();
      if (sy0 > g.h - 1) sy0 = g.h - 1;
      var sy1 = math.min(g.h, ((y + 1) / f).ceil());
      if (sy1 < sy0 + 1) sy1 = sy0 + 1;
      for (var x = 0; x < nw; x++) {
        final dx = left + x;
        if (dx < 0 || dx >= bw) continue;
        var sx0 = (x / f).floor();
        if (sx0 > g.w - 1) sx0 = g.w - 1;
        var sx1 = math.min(g.w, ((x + 1) / f).ceil());
        if (sx1 < sx0 + 1) sx1 = sx0 + 1;
        final s = ii[sy1 * iw + sx1] -
            ii[sy0 * iw + sx1] -
            ii[sy1 * iw + sx0] +
            ii[sy0 * iw + sx0];
        final v = s / ((sy1 - sy0) * (sx1 - sx0)) / 255.0;
        if (v <= 0) continue;
        final i = dy * bw + dx;
        buf[i] = 1 - (1 - buf[i]) * (1 - v);
      }
    }
    return nw;
  }

  // ------------------------------------------------------------ PNG (RGBA)
  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });

  static void _chunk(BytesBuilder b, String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    b.add(len.buffer.asUint8List());
    final typeBytes = type.codeUnits;
    b.add(typeBytes);
    b.add(data);
    var c = 0xFFFFFFFF;
    for (final x in typeBytes) {
      c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
    }
    for (final x in data) {
      c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
    }
    c = (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    final crc = ByteData(4)..setUint32(0, c);
    b.add(crc.buffer.asUint8List());
  }

  /// Минималдуу PNG коддогуч (RGBA, 8 бит). zlib dart:io'дон алынат.
  static Uint8List encodePng(int w, int h, Uint8List rgba) {
    final stride = w * 4;
    final raw = Uint8List((stride + 1) * h);
    for (var y = 0; y < h; y++) {
      final o = y * (stride + 1);
      raw[o] = 0; // filter: None
      raw.setRange(o + 1, o + 1 + stride, rgba, y * stride);
    }
    final comp = zlib.encode(raw);

    final ihdr = ByteData(13)
      ..setUint32(0, w)
      ..setUint32(4, h)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // RGBA
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);

    final b = BytesBuilder();
    b.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
    _chunk(b, 'IHDR', ihdr.buffer.asUint8List());
    _chunk(b, 'IDAT', comp);
    _chunk(b, 'IEND', const <int>[]);
    return b.toBytes();
  }
}

/// Сөздөгү бир тамганын орду.
class _Pl {
  final HwGlyph? g;
  final double scale;
  final double lift;
  final double f;
  final double left;
  final double w;
  final bool joined;
  const _Pl(this.g, this.scale, this.lift, this.f, this.left, this.w,
      this.joined);
}
