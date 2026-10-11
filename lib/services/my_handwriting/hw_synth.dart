import 'dart:math' as math;
import 'dart:typed_data';

import 'hw_profile.dart';

class _S {
  /// Чекиттер: [x0, y0, x1, y1, ...] (бирдик = x-бийиктик, y жогору карай).
  final List<double> pts;

  /// Сызыктын жоондугу (бирдик).
  final double w;
  const _S(this.pts, this.w);
}

/// Дептерге жазылбаган тыныш белгилерин (чекит, үтүр, ...) жөнөкөй сызыктар
/// менен өзү чийет, ошондуктан текстте алар түшүп калбайт.
class HwSynth {
  static const double _t = 0.09; // кадимки сызык
  static const double _d = 0.22; // чекиттин диаметри

  static final Map<int, List<_S>> _shapes = {
    '.'.codeUnitAt(0): [
      _S([0.1, 0.1, 0.1, 0.1], _d)
    ],
    ','.codeUnitAt(0): [
      _S([0.12, 0.1, 0.12, 0.1], _d),
      _S([0.12, 0.05, 0.05, -0.25], _t * 1.3),
    ],
    ':'.codeUnitAt(0): [
      _S([0.1, 0.1, 0.1, 0.1], _d),
      _S([0.1, 0.65, 0.1, 0.65], _d),
    ],
    ';'.codeUnitAt(0): [
      _S([0.12, 0.65, 0.12, 0.65], _d),
      _S([0.12, 0.1, 0.12, 0.1], _d),
      _S([0.12, 0.05, 0.05, -0.25], _t * 1.3),
    ],
    '!'.codeUnitAt(0): [
      _S([0.1, 1.5, 0.1, 0.4], _t * 1.3),
      _S([0.1, 0.1, 0.1, 0.1], _d),
    ],
    '?'.codeUnitAt(0): [
      _S([0.0, 1.2, 0.15, 1.5, 0.45, 1.58, 0.68, 1.38, 0.6, 1.08, 0.32, 0.85,
          0.27, 0.5], _t),
      _S([0.27, 0.1, 0.27, 0.1], _d),
    ],
    '-'.codeUnitAt(0): [
      _S([0.0, 0.45, 0.5, 0.5], _t)
    ],
    0x2013: [
      _S([0.0, 0.45, 0.85, 0.5], _t)
    ],
    '('.codeUnitAt(0): [
      _S([0.32, 1.5, 0.12, 1.1, 0.04, 0.6, 0.1, 0.1, 0.3, -0.3], _t)
    ],
    ')'.codeUnitAt(0): [
      _S([0.0, 1.5, 0.2, 1.1, 0.28, 0.6, 0.22, 0.1, 0.02, -0.3], _t)
    ],
    '+'.codeUnitAt(0): [
      _S([0.0, 0.6, 0.62, 0.6], _t),
      _S([0.31, 0.3, 0.31, 0.9], _t),
    ],
    '='.codeUnitAt(0): [
      _S([0.0, 0.4, 0.62, 0.42], _t),
      _S([0.0, 0.8, 0.62, 0.82], _t),
    ],
    '/'.codeUnitAt(0): [
      _S([0.0, -0.1, 0.48, 1.5], _t)
    ],
    '"'.codeUnitAt(0): [
      _S([0.08, 1.55, 0.02, 1.15], _t * 1.2),
      _S([0.34, 1.55, 0.28, 1.15], _t * 1.2),
    ],
    "'".codeUnitAt(0): [
      _S([0.08, 1.55, 0.02, 1.15], _t * 1.2)
    ],
    0x2022: [
      _S([0.2, 0.5, 0.2, 0.5], 0.3)
    ],
    0x00D7: [
      _S([0.0, 0.2, 0.5, 0.8], _t),
      _S([0.0, 0.8, 0.5, 0.2], _t),
    ],
    // ---- математика жана грек белгилери (жөнөкөй сызыктар менен)
    0x2212: [_S([0.0, 0.45, 0.6, 0.46], _t)], // −
    0x00B1: [
      _S([0.0, 0.2, 0.62, 0.21], _t),
      _S([0.0, 0.75, 0.62, 0.76], _t),
      _S([0.31, 0.45, 0.31, 1.05], _t),
    ],
    0x00F7: [
      _S([0.05, 0.5, 0.57, 0.5], _t),
      _S([0.31, 0.85, 0.31, 0.85], _d),
      _S([0.31, 0.15, 0.31, 0.15], _d),
    ],
    0x00B7: [_S([0.12, 0.45, 0.12, 0.45], _d)], // ·
    0x221A: [_S([0.0, 0.6, 0.14, 0.38, 0.34, 1.55, 0.95, 1.55], _t)], // √
    0x221E: [
      _S([0.2, 0.45, 0.05, 0.7, 0.2, 0.95, 0.42, 0.7, 0.62, 0.95, 0.8, 0.7,
          0.62, 0.45, 0.42, 0.7, 0.2, 0.45], _t),
    ],
    0x2248: [
      _S([0.0, 0.3, 0.16, 0.45, 0.34, 0.2, 0.55, 0.36], _t),
      _S([0.0, 0.75, 0.16, 0.9, 0.34, 0.65, 0.55, 0.81], _t),
    ],
    0x2260: [
      _S([0.0, 0.4, 0.62, 0.42], _t),
      _S([0.0, 0.8, 0.62, 0.82], _t),
      _S([0.46, 0.15, 0.18, 1.05], _t),
    ],
    0x2264: [
      _S([0.6, 1.0, 0.0, 0.6, 0.6, 0.2], _t),
      _S([0.0, 0.0, 0.6, 0.02], _t),
    ],
    0x2265: [
      _S([0.0, 1.0, 0.6, 0.6, 0.0, 0.2], _t),
      _S([0.0, 0.0, 0.6, 0.02], _t),
    ],
    0x221D: [
      _S([0.08, 0.2, 0.0, 0.5, 0.18, 0.75, 0.38, 0.5, 0.18, 0.2, 0.0, 0.5,
          0.18, 0.75, 0.5, 0.75], _t),
    ],
    0x222B: [
      _S([0.08, -0.35, 0.02, -0.1, 0.18, 0.5, 0.3, 1.2, 0.26, 1.6, 0.1, 1.6],
          _t),
    ],
    0x03A3: [_S([0.62, 1.4, 0.0, 1.4, 0.36, 0.7, 0.0, 0.0, 0.62, 0.0], _t)],
    0x0394: [_S([0.0, 0.0, 0.36, 1.4, 0.72, 0.0, 0.0, 0.0], _t)],
    0x2207: [_S([0.0, 1.4, 0.72, 1.4, 0.36, 0.0, 0.0, 1.4], _t)],
    0x03A9: [
      _S([0.0, 0.0, 0.22, 0.0, 0.08, 0.35, 0.05, 0.75, 0.3, 1.05, 0.58, 0.75,
          0.55, 0.35, 0.42, 0.0, 0.64, 0.0], _t),
    ],
    0x03C0: [
      _S([0.0, 0.95, 0.7, 0.95], _t),
      _S([0.18, 0.95, 0.14, 0.0], _t),
      _S([0.52, 0.95, 0.56, 0.0], _t),
    ],
    0x03B1: [
      _S([0.52, 0.95, 0.24, 0.98, 0.04, 0.6, 0.12, 0.15, 0.38, 0.12, 0.5, 0.5,
          0.5, 0.95, 0.58, 0.0], _t),
    ],
    0x03B2: [
      _S([0.06, -0.35, 0.1, 0.6, 0.14, 1.3, 0.4, 1.45, 0.52, 1.1, 0.3, 0.75,
          0.52, 0.55, 0.42, 0.1, 0.1, 0.18], _t),
    ],
    0x03B3: [
      _S([0.0, 0.95, 0.2, 0.5, 0.3, 0.0, 0.42, -0.35], _t),
      _S([0.6, 0.95, 0.3, 0.0], _t),
    ],
    0x03B8: [
      _S([0.28, 1.45, 0.06, 1.05, 0.05, 0.45, 0.26, 0.05, 0.46, 0.45, 0.46,
          1.05, 0.28, 1.45], _t),
      _S([0.06, 0.72, 0.46, 0.72], _t),
    ],
    0x03BB: [
      _S([0.0, 1.45, 0.2, 1.4, 0.56, 0.0], _t),
      _S([0.34, 0.75, 0.0, 0.0], _t),
    ],
    0x03BC: [
      _S([0.06, 0.95, 0.02, 0.0, 0.1, -0.35], _t),
      _S([0.06, 0.6, 0.1, 0.12, 0.34, 0.08, 0.5, 0.45, 0.5, 0.95], _t),
    ],
    0x03C6: [
      _S([0.3, 1.45, 0.3, -0.35], _t),
      _S([0.3, 0.9, 0.05, 0.72, 0.08, 0.25, 0.3, 0.12, 0.52, 0.25, 0.55, 0.72,
          0.3, 0.9], _t),
    ],
    0x03C9: [
      _S([0.02, 0.95, 0.0, 0.3, 0.16, 0.08, 0.3, 0.45, 0.44, 0.08, 0.6, 0.3,
          0.58, 0.95], _t),
    ],
    0x03C1: [
      _S([0.06, -0.35, 0.1, 0.5, 0.14, 0.9], _t),
      _S([0.1, 0.5, 0.3, 0.95, 0.52, 0.7, 0.5, 0.25, 0.26, 0.08, 0.1, 0.3], _t),
    ],
    0x03B5: [
      _S([0.46, 0.9, 0.18, 0.98, 0.08, 0.72, 0.34, 0.55], _t),
      _S([0.34, 0.55, 0.06, 0.4, 0.14, 0.05, 0.46, 0.12], _t),
    ],
    0x2192: [
      _S([0.0, 0.5, 0.8, 0.5], _t),
      _S([0.56, 0.72, 0.8, 0.5, 0.56, 0.28], _t),
    ],
    0x2190: [
      _S([0.0, 0.5, 0.8, 0.5], _t),
      _S([0.24, 0.72, 0.0, 0.5, 0.24, 0.28], _t),
    ],
    0x21D2: [
      _S([0.0, 0.62, 0.78, 0.62], _t),
      _S([0.0, 0.38, 0.78, 0.38], _t),
      _S([0.56, 0.84, 0.86, 0.5, 0.56, 0.16], _t),
    ],
    0x2208: [
      _S([0.5, 1.0, 0.18, 0.95, 0.06, 0.5, 0.18, 0.05, 0.5, 0.0], _t),
      _S([0.1, 0.5, 0.45, 0.5], _t),
    ],
    0x2202: [
      _S([0.14, 1.2, 0.38, 1.4, 0.5, 1.1, 0.2, 0.75, 0.06, 0.4, 0.22, 0.08,
          0.46, 0.25, 0.5, 0.6, 0.4, 0.95], _t),
    ],
    0x00B0: [
      _S([0.15, 1.45, 0.25, 1.4, 0.3, 1.3, 0.25, 1.2, 0.15, 1.15, 0.05, 1.2,
          0.0, 1.3, 0.05, 1.4, 0.15, 1.45], _t),
    ],
  };

  /// [glyphs] ичинде жок белгилерди [xh] (x-бийиктик, px) боюнча чийип кошот.
  static void fillMissing(Map<int, HwGlyph> glyphs, double xh) {
    _shapes.forEach((code, strokes) {
      if (!glyphs.containsKey(code)) {
        glyphs[code] = _render(code, strokes, xh);
      }
    });
  }

  static double _segDist(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 0) {
      t = ((px - ax) * dx + (py - ay) * dy) / len2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
    }
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final ex = px - cx;
    final ey = py - cy;
    return math.sqrt(ex * ex + ey * ey);
  }

  static HwGlyph _render(int code, List<_S> strokes, double xh) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final s in strokes) {
      for (var i = 0; i < s.pts.length; i += 2) {
        minX = math.min(minX, s.pts[i] - s.w / 2);
        maxX = math.max(maxX, s.pts[i] + s.w / 2);
        minY = math.min(minY, s.pts[i + 1] - s.w / 2);
        maxY = math.max(maxY, s.pts[i + 1] + s.w / 2);
      }
    }
    const pad = 2;
    final w = ((maxX - minX) * xh).ceil() + 2 * pad;
    final h = ((maxY - minY) * xh).ceil() + 2 * pad;
    final a = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final ux = (x + 0.5 - pad) / xh + minX;
        final uy = maxY - (y + 0.5 - pad) / xh;
        var best = 0.0;
        for (final s in strokes) {
          final halfPx = s.w * xh / 2;
          if (s.pts.length == 4 &&
              s.pts[0] == s.pts[2] &&
              s.pts[1] == s.pts[3]) {
            final d = _segDist(ux, uy, s.pts[0], s.pts[1], s.pts[2], s.pts[3]) * xh;
            final c = halfPx + 0.5 - d;
            if (c > best) best = c;
            continue;
          }
          for (var i = 0; i + 3 < s.pts.length; i += 2) {
            final d = _segDist(ux, uy, s.pts[i], s.pts[i + 1], s.pts[i + 2],
                    s.pts[i + 3]) *
                xh;
            final c = halfPx + 0.5 - d;
            if (c > best) best = c;
          }
        }
        if (best <= 0) continue;
        if (best > 1) best = 1;
        a[y * w + x] = (best * 255).round();
      }
    }
    final baseOff = (maxY * xh).round() + pad;
    return HwGlyph(code, w, h, baseOff, a);
  }

  // ------------------------------------------------ ё, й (Ё, Й)
  /// ё, й, Ё, Й тамгаларын колдонуучунун е, и, Е, И тамгаларынан жасайт:
  /// үстүнө ручка менен коюлгандай эки чекит же кашка (бреве) кошулат.
  /// Колдонуучу өзү жазган ё/й болсо да, ушул жасалганы колдонулат.
  static void composeDiacritics(Map<int, HwGlyph> glyphs) {
    void make(String target, String base, bool breve, bool upper) {
      final g = glyphs[base.codeUnitAt(0)];
      if (g == null) return;
      final code = target.codeUnitAt(0);
      glyphs[code] = _withMark(g, code, breve, upper);
    }

    make('ё', 'е', false, false);
    make('й', 'и', true, false);
    make('Ё', 'Е', false, true);
    make('Й', 'И', true, true);
  }

  static void _stamp(Float64List buf, int bw, int bh, double px, double py,
      double r) {
    final xa = (px - r - 1).floor(), xb = (px + r + 1).ceil();
    final ya = (py - r - 1).floor(), yb = (py + r + 1).ceil();
    for (var y = ya; y <= yb; y++) {
      if (y < 0 || y >= bh) continue;
      for (var x = xa; x <= xb; x++) {
        if (x < 0 || x >= bw) continue;
        final dx = x + 0.5 - px, dy = y + 0.5 - py;
        var v = r + 0.5 - math.sqrt(dx * dx + dy * dy);
        if (v <= 0) continue;
        if (v > 1) v = 1;
        final i = y * bw + x;
        if (v > buf[i]) buf[i] = v;
      }
    }
  }

  static HwGlyph _withMark(HwGlyph g, int code, bool breve, bool upper) {
    final w0 = g.w, h0 = g.h, a0 = g.alpha;
    // сыянын эң үстүңкү сабы
    var inkTop = -1;
    for (var y = 0; y < h0 && inkTop < 0; y++) {
      for (var x = 0; x < w0; x++) {
        if (a0[y * w0 + x] >= 128) {
          inkTop = y;
          break;
        }
      }
    }
    if (inkTop < 0) inkTop = 0;
    final body = math.max(8.0, (g.baseOff - inkTop).toDouble());
    final ref = body * (upper ? 0.72 : 1.0);
    final sw = g.strokeW;

    // Тамганын үстүңкү жана астыңкы бөлүгүнүн борбору — кыйшыктыкты табуу үчүн
    double centreX(int y0, int y1) {
      var s = 0.0;
      var n = 0;
      for (var y = math.max(0, y0); y <= y1 && y < h0; y++) {
        for (var x = 0; x < w0; x++) {
          if (a0[y * w0 + x] >= 128) {
            s += x + 0.5;
            n++;
          }
        }
      }
      return n == 0 ? w0 / 2 : s / n;
    }

    final band = math.max(2, (0.3 * body).round());
    final topX = centreX(inkTop, inkTop + band);
    final botX = centreX(g.baseOff - band, g.baseOff);
    // кыйшыктык: бийиктиктин бирдигине канча пиксель оңго жылат
    final slope = ((topX - botX) / math.max(1.0, body - band))
        .clamp(-0.6, 0.6)
        .toDouble();

    final gapAbove = 0.22 * ref;
    final markH = breve ? 0.20 * ref : 1.5 * sw;
    final extra = (gapAbove + markH + sw + 3).ceil();
    // белгинин борбору (жаңы координаттарда, тамга [extra] ылдый жылат)
    final cy = extra + inkTop - gapAbove - markH / 2;
    final rise = inkTop + extra - cy; // тамганын үстүнөн канча өйдө
    final halfW = breve ? 0.27 * ref : 0.21 * ref + sw;
    var cx = topX + slope * rise;
    final padL = math.max(0, (halfW + sw + 1 - cx).ceil());
    final padR = math.max(0, (cx + halfW + sw + 1 - w0).ceil());
    cx += padL;
    final nw = w0 + padL + padR;
    final nh = h0 + extra;

    final buf = Float64List(nw * nh);
    for (var y = 0; y < h0; y++) {
      for (var x = 0; x < w0; x++) {
        buf[(y + extra) * nw + x + padL] = a0[y * w0 + x] / 255.0;
      }
    }

    final rnd = math.Random(code * 31 + w0);
    double jit(double a) => (rnd.nextDouble() * 2 - 1) * a;

    if (!breve) {
      // эки чекит: ар бири кыска, бир аз кыйшык ручка тийгизүү
      final gapX = 0.19 * ref;
      for (final s in [-1.0, 1.0]) {
        final px = cx + s * gapX + jit(0.04 * ref);
        final py = cy + jit(0.03 * ref);
        final r = math.max(1.4, 0.72 * sw);
        final len = 0.35 * sw + jit(0.1 * sw);
        final ang = -0.5 + jit(0.3);
        final dx = math.cos(ang) * len, dy = math.sin(ang) * len;
        final n = math.max(3, (len * 3).ceil());
        for (var i = 0; i <= n; i++) {
          final t = i / n - 0.5;
          _stamp(buf, nw, nh, px + dx * t, py + dy * t, r);
        }
      }
    } else {
      // кашка (∪): ортосу калың, учтары ичкерет — ручка менен жазгандай
      final bw = 2 * halfW;
      final tilt = jit(0.04 * ref);
      final len = bw * 1.3;
      final n = math.max(20, (len * 2.5).ceil());
      for (var i = 0; i <= n; i++) {
        final t = i / n;
        final u = 2 * t - 1;
        final y = cy - markH / 2 + markH * (1 - u * u) + tilt * u;
        final x = cx - bw / 2 + bw * t - slope * (y - cy);
        final r = math.max(0.8, sw / 2 * (0.5 + 0.5 * math.sin(math.pi * t)));
        _stamp(buf, nw, nh, x, y, r);
      }
    }

    final out = Uint8List(nw * nh);
    for (var i = 0; i < out.length; i++) {
      final v = buf[i];
      out[i] = v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).round());
    }
    return HwGlyph(code, nw, nh, g.baseOff + extra, out);
  }
}
