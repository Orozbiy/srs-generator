import 'dart:math' as math;
import 'dart:typed_data';

import 'hw_geom.dart';
import 'hw_profile.dart';

class _Marker {
  final double x;
  final double y;
  final int area;
  const _Marker(this.x, this.y, this.area);
}

/// Телефон сүрөтүнөн тамгаларды кесип алуу (таза Dart, UI'га көз каранды эмес).
class HwVision {
  /// Жарыктын тегиз эместигин жок кылат: фон ~200 болот, сыя/маркер караңгы.
  static Uint8List normalize(Uint8List gray, int w, int h) {
    final r = math.max(8, w ~/ 16);
    final iw = w + 1;
    final ii = Int64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        rowSum += gray[y * w + x];
        ii[(y + 1) * iw + (x + 1)] = ii[y * iw + (x + 1)] + rowSum;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r);
      final y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r);
        final x1 = math.min(w, x + r + 1);
        final s = ii[y1 * iw + x1] -
            ii[y0 * iw + x1] -
            ii[y1 * iw + x0] +
            ii[y0 * iw + x0];
        final area = (y1 - y0) * (x1 - x0);
        var bg = s / area;
        if (bg < 20) bg = 20;
        final v = gray[y * w + x] / bg * 200.0;
        out[y * w + x] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
      }
    }
    return out;
  }

  /// Төрт бурчтан кара квадрат маркерлерди табат.
  /// Кайтарат (сол-жогору, оң-жогору, сол-төмөн, оң-төмөн) же null.
  static List<List<double>>? findMarkers(Uint8List n, int w, int h) {
    final qw = (w * 0.38).toInt();
    final qh = (h * 0.38).toInt();
    final qxs = [0, w - qw, 0, w - qw];
    final qys = [0, 0, h - qh, h - qh];
    final cxs = [0.0, w.toDouble(), 0.0, w.toDouble()];
    final cys = [0.0, 0.0, h.toDouble(), h.toDouble()];

    final found = <_Marker>[];
    final stack = Int32List(qw * qh);

    for (var k = 0; k < 4; k++) {
      final qx = qxs[k];
      final qy = qys[k];
      final seen = Uint8List(qw * qh);
      _Marker? best;
      var bestDist = double.infinity;

      for (var y0 = 0; y0 < qh; y0++) {
        for (var x0 = 0; x0 < qw; x0++) {
          final idx0 = y0 * qw + x0;
          if (seen[idx0] != 0) continue;
          if (n[(qy + y0) * w + qx + x0] >= 70) continue;

          var sp = 0;
          stack[sp++] = idx0;
          seen[idx0] = 1;
          var count = 0;
          var minX = x0, maxX = x0, minY = y0, maxY = y0;
          var sumX = 0.0, sumY = 0.0;

          while (sp > 0) {
            final p = stack[--sp];
            final y = p ~/ qw;
            final x = p - y * qw;
            count++;
            sumX += x;
            sumY += y;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;

            if (x > 0) {
              final q = p - 1;
              if (seen[q] == 0 && n[(qy + y) * w + qx + x - 1] < 70) {
                seen[q] = 1;
                stack[sp++] = q;
              }
            }
            if (x < qw - 1) {
              final q = p + 1;
              if (seen[q] == 0 && n[(qy + y) * w + qx + x + 1] < 70) {
                seen[q] = 1;
                stack[sp++] = q;
              }
            }
            if (y > 0) {
              final q = p - qw;
              if (seen[q] == 0 && n[(qy + y - 1) * w + qx + x] < 70) {
                seen[q] = 1;
                stack[sp++] = q;
              }
            }
            if (y < qh - 1) {
              final q = p + qw;
              if (seen[q] == 0 && n[(qy + y + 1) * w + qx + x] < 70) {
                seen[q] = 1;
                stack[sp++] = q;
              }
            }
          }

          if (count < 200) continue;
          final bw = maxX - minX + 1;
          final bh = maxY - minY + 1;
          if (!(bw > 0.012 * w && bw < 0.09 * w)) continue;
          if (!(bh > 0.012 * w && bh < 0.09 * w)) continue;
          final aspect = bw / bh;
          if (aspect < 0.6 || aspect > 1.6) continue;
          if (count / (bw * bh) < 0.72) continue;

          final mx = sumX / count + qx;
          final my = sumY / count + qy;
          final dist = math.sqrt(
              (mx - cxs[k]) * (mx - cxs[k]) + (my - cys[k]) * (my - cys[k]));
          if (dist < bestDist) {
            bestDist = dist;
            best = _Marker(mx, my, count);
          }
        }
      }
      if (best == null) return null;
      found.add(best);
    }
    return _order(found);
  }

  /// Эң чоң маркер = сол-жогорку. Калгандары саат жебеси боюнча: TR, BR, BL.
  static List<List<double>> _order(List<_Marker> m) {
    var tl = 0;
    for (var i = 1; i < 4; i++) {
      if (m[i].area > m[tl].area) tl = i;
    }
    var cx = 0.0, cy = 0.0;
    for (final p in m) {
      cx += p.x / 4;
      cy += p.y / 4;
    }
    double ang(_Marker p) => math.atan2(p.y - cy, p.x - cx);
    final a0 = ang(m[tl]);
    double rel(_Marker p) {
      var d = ang(p) - a0;
      const twoPi = 2 * math.pi;
      while (d < 0) {
        d += twoPi;
      }
      while (d >= twoPi) {
        d -= twoPi;
      }
      return d;
    }

    final others = <int>[
      for (var i = 0; i < 4; i++)
        if (i != tl) i
    ];
    others.sort((a, b) => rel(m[a]).compareTo(rel(m[b])));
    final tr = m[others[0]];
    final br = m[others[1]];
    final bl = m[others[2]];
    return [
      [m[tl].x, m[tl].y],
      [tr.x, tr.y],
      [bl.x, bl.y],
      [br.x, br.y],
    ];
  }

  /// dst(u,v) -> src(x,y) гомографиясы (h33 = 1), 4 чекит боюнча.
  static List<double>? solveHomography(
      List<List<double>> src, List<List<double>> dst) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final u = dst[i][0], v = dst[i][1];
      final x = src[i][0], y = src[i][1];
      a[2 * i] = [u, v, 1, 0, 0, 0, -u * x, -v * x, x];
      a[2 * i + 1] = [0, 0, 0, u, v, 1, -u * y, -v * y, y];
    }
    for (var c = 0; c < 8; c++) {
      var piv = c;
      for (var r = c + 1; r < 8; r++) {
        if (a[r][c].abs() > a[piv][c].abs()) piv = r;
      }
      if (a[piv][c].abs() < 1e-12) return null;
      final tmp = a[c];
      a[c] = a[piv];
      a[piv] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final f = a[r][c] / a[c][c];
        if (f == 0) continue;
        for (var k = c; k < 9; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];
  }

  static Uint8List warp(
      Uint8List n, int w, int h, List<double> hc, int outW, int outH) {
    final out = Uint8List(outW * outH);
    for (var v = 0; v < outH; v++) {
      for (var u = 0; u < outW; u++) {
        final den = hc[6] * u + hc[7] * v + 1;
        final x = (hc[0] * u + hc[1] * v + hc[2]) / den;
        final y = (hc[3] * u + hc[4] * v + hc[5]) / den;
        var x0 = x.floor();
        var y0 = y.floor();
        final fx = x - x0;
        final fy = y - y0;
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x0 > w - 2) x0 = w - 2;
        if (y0 > h - 2) y0 = h - 2;
        final i00 = y0 * w + x0;
        final val = n[i00] * (1 - fx) * (1 - fy) +
            n[i00 + 1] * fx * (1 - fy) +
            n[i00 + w] * (1 - fx) * fy +
            n[i00 + w + 1] * fx * fy;
        out[v * outW + u] = val < 0 ? 0 : (val > 255 ? 255 : val.round());
      }
    }
    return out;
  }

  /// Бардык иштетүү: боз сүрөт -> түздөлгөн барак. Ийгиликсиз болсо null.
  static Uint8List? rectify(Uint8List gray, int w, int h) {
    if (w < 200 || h < 200) return null;
    final n = normalize(gray, w, h);
    final m = findMarkers(n, w, h);
    if (m == null) return null;
    final dst = <List<double>>[
      for (final mk in HwGeom.markers)
        [mk[0] * HwGeom.scale, mk[1] * HwGeom.scale],
    ];
    final hc = solveHomography(m, dst);
    if (hc == null) return null;
    return warp(n, w, h, hc, (HwGeom.pageW * HwGeom.scale).round(),
        (HwGeom.pageH * HwGeom.scale).round());
  }

  static const int _inkLo = 70;
  static const int _inkHi = 150;

  /// Түздөлгөн баракчадан [page] беттеги тамгаларды кесип алат.
  static List<HwGlyph> extract(Uint8List canvas, int page) {
    final cw = (HwGeom.pageW * HwGeom.scale).round();
    final ch = (HwGeom.pageH * HwGeom.scale).round();
    final chars = HwGeom.pageChars(page);
    final out = <HwGlyph>[];

    for (var i = 0; i < chars.length; i++) {
      final r = HwGeom.writeRect(i);
      final x0 = (r[0] * HwGeom.scale).round();
      final y0 = (r[1] * HwGeom.scale).round();
      final x1 = math.min((r[2] * HwGeom.scale).round(), cw);
      final y1 = math.min((r[3] * HwGeom.scale).round(), ch);
      final w = x1 - x0;
      final h = y1 - y0;
      if (w <= 0 || h <= 0) continue;
      final by = HwGeom.baselineY(i) * HwGeom.scale;

      final a = Uint8List(w * h);
      final rows = Int32List(h);
      final cols = Int32List(w);
      var strong = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = canvas[(y0 + y) * cw + x0 + x].toDouble();
          var al = (_inkHi - v) / (_inkHi - _inkLo);
          if (al < 0) al = 0;
          if (al > 1) al = 1;
          if (al < 0.12) al = 0;
          a[y * w + x] = (al * 255).round();
          if (al > 0.5) {
            strong++;
            rows[y]++;
            cols[x]++;
          }
        }
      }
      if (strong < 20) continue;

      var top = -1, bot = -1, lef = -1, rig = -1;
      for (var y = 0; y < h; y++) {
        if (rows[y] >= 2) {
          if (top < 0) top = y;
          bot = y;
        }
      }
      for (var x = 0; x < w; x++) {
        if (cols[x] >= 2) {
          if (lef < 0) lef = x;
          rig = x;
        }
      }
      if (top < 0 || lef < 0) continue;
      const pad = 2;
      top = math.max(0, top - pad);
      lef = math.max(0, lef - pad);
      bot = math.min(h - 1, bot + pad);
      rig = math.min(w - 1, rig + pad);

      final gw = rig - lef + 1;
      final gh = bot - top + 1;
      final g = Uint8List(gw * gh);
      for (var y = 0; y < gh; y++) {
        for (var x = 0; x < gw; x++) {
          g[y * gw + x] = a[(top + y) * w + lef + x];
        }
      }
      final baseOff = ((by - y0) - top).round();
      out.add(HwGlyph(chars.codeUnitAt(i), gw, gh, baseOff, g));
    }
    return out;
  }
}
