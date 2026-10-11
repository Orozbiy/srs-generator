import 'dart:math' as math;
import 'dart:typed_data';

import 'hw_geom.dart';
import 'hw_profile.dart';
import 'hw_synth.dart';

class FreeResult {
  final List<HwGlyph> glyphs;
  final String? error;
  const FreeResult(this.glyphs, this.error);
}

class _Comp {
  final int id;
  final int x0, y0, x1, y1, area;
  /// Сыянын каралыгы: күчтүү кара пикселдердин үлүшү (0..1).
  final double sf;
  bool edge = false;
  double yp = 0, yp0 = 0, yp1 = 0;
  _Comp(this.id, this.x0, this.y0, this.x1, this.y1, this.area, this.sf);
  int get w => x1 - x0 + 1;
  int get h => y1 - y0 + 1;
}

/// Дептерге катар жазылган тамгалардан (шаблонсуз) глифтерди чыгарат.
class HwFreeform {
  static FreeResult extract(Uint8List gray, int gw, int gh, HwSet set) {
    final chars = set.chars;
    final n = chars.length;

    // ---------------------------------------------- 1) кагазды кесип алуу
    final box = _paperBox(gray, gw, gh);
    final bx0 = box[0], by0 = box[1];
    final w = box[2] - box[0], h = box[3] - box[1];
    if (w < 100 || h < 100) {
      return const FreeResult(
          [], 'Кагаз табылган жок. Сүрөттү жакшыраак тартыңыз.');
    }
    final g = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      final so = (y + by0) * gw + bx0;
      for (var x = 0; x < w; x++) {
        g[y * w + x] = gray[so + x].toDouble();
      }
    }
    final sc2 = (w / 715.0) * (w / 715.0);

    // ------------------------------------------- 2) фонду тегиздөө (ratio)
    final bg = _boxBlur(g, w, h, math.max(10, w ~/ 48));
    final ratio = Float64List(w * h);
    for (var i = 0; i < ratio.length; i++) {
      ratio[i] = g[i] / math.max(bg[i], 20.0);
    }

    // ------------------------------ 3) гистерезис + байланышкан бөлүктөр
    final lab = Int32List(w * h);
    final raw = <_Comp>[];
    final stack = Int32List(w * h);
    var nextId = 0;
    for (var s = 0; s < w * h; s++) {
      if (lab[s] != 0 || ratio[s] >= 0.905) continue;
      nextId++;
      var sp = 0;
      stack[sp++] = s;
      lab[s] = nextId;
      var minX = w, maxX = 0, minY = h, maxY = 0, area = 0;
      var strongN = 0;
      while (sp > 0) {
        final p = stack[--sp];
        final py = p ~/ w;
        final px = p - py * w;
        area++;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        if (ratio[p] < 0.84) strongN++;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (lab[q] != 0 || ratio[q] >= 0.905) continue;
            lab[q] = nextId;
            stack[sp++] = q;
          }
        }
      }
      if (strongN == 0) continue;
      final c = _Comp(
          nextId, minX, minY, maxX, maxY, area, strongN / math.max(area, 1));
      c.edge = minX <= 2 || minY <= 2 || maxX >= w - 3 || maxY >= h - 3;
      raw.add(c);
    }

    // ------------------------------------------- 4) өлчөм боюнча чыпкалоо
    final inner = raw.where((c) => !c.edge).toList();
    final mids =
        inner.where((c) => c.area >= 30 * sc2 && c.area <= 800 * sc2).toList();
    if (mids.length < 5) {
      return const FreeResult([],
          'Тамгалар табылган жок. Кара же көк сыя менен жазып, сүрөттү жарыкта тартыңыз.');
    }
    final h0 = _median(mids.map((c) => c.h.toDouble()).toList());
    final med = _median(mids.map((c) => c.area.toDouble()).toList());
    // Кагаздын четине тийип турса да, тамгага окшошторун калтырабыз
    final all = <_Comp>[...inner];
    for (final c in raw) {
      if (c.edge &&
          c.area >= 0.3 * med &&
          c.area <= 4 * med &&
          c.h <= 2.5 * h0 &&
          c.w <= 3 * h0) {
        all.add(c);
      }
    }
    all.sort((a, b) => a.id.compareTo(b.id));
    // Ачык (күңүрт) чийиндилер — кагаздагы так, сызык, көлөкө — сыя эмес.
    final cand = all.where((c) => c.area >= 0.3 * med && c.h <= 3 * h0).toList();
    if (cand.isNotEmpty) {
      final msf = _median(cand.map((c) => c.sf).toList());
      final sfThr = math.max(0.25, 0.45 * msf);
      all.removeWhere((c) => c.sf < sfThr);
      if (all.isEmpty) {
        return const FreeResult([],
            'Тамгалар табылган жок. Кара же көк ручка менен даана жазылган '
            'сүрөт керек.');
      }
    }
    var inkCount = 0;
    for (final c in all) {
      inkCount += c.area;
    }
    var comps = all
        .where((c) =>
            c.h <= 3 * h0 && c.w <= 4 * h0 && c.area >= 0.04 * med)
        .toList();
    final anchors = comps.where((c) => c.area >= 0.3 * med).toList();
    if (anchors.length < n ~/ 2) {
      return FreeResult([],
          'Тамгалар аз табылды (${anchors.length}). Керек: $n (${set.title}). '
          'Жарыгы тегиз, тамгалары даана сүрөт керек.');
    }
    final hh = _median(anchors.map((c) => c.h.toDouble()).toList());

    // --------------------------------------- 5) кыйшыктыкты (skew) баалоо
    final ix = Int32List(inkCount);
    final iy = Int32List(inkCount);
    {
      var p = 0;
      final ids = <int>{for (final c in all) c.id};
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (ids.contains(lab[y * w + x])) {
            ix[p] = x;
            iy[p] = y;
            p++;
            if (p >= inkCount) break;
          }
        }
        if (p >= inkCount) break;
      }
    }
    var tan = 0.0;
    {
      var bestScore = -1.0;
      final yv = Int32List(inkCount);
      for (var d = -8.0; d <= 8.001; d += 0.25) {
        final tt = math.tan(d * math.pi / 180);
        var mn = 1 << 30, mxv = -(1 << 30);
        for (var i = 0; i < inkCount; i++) {
          final v = (iy[i] - ix[i] * tt).round();
          yv[i] = v;
          if (v < mn) mn = v;
          if (v > mxv) mxv = v;
        }
        final hist = Int32List(mxv - mn + 1);
        for (var i = 0; i < inkCount; i++) {
          hist[yv[i] - mn]++;
        }
        var score = 0.0;
        for (final v in hist) {
          score += v.toDouble() * v;
        }
        if (score > bestScore) {
          bestScore = score;
          tan = tt;
        }
      }
    }

    // ----------------------- 6) саптарды тамгалардын аст сызыгы боюнча топтоо
    for (final c in comps) {
      final cx = (c.x0 + c.x1) / 2 * tan;
      c.yp = (c.y0 + c.y1) / 2 - cx;
      c.yp0 = c.y0 - cx;
      c.yp1 = c.y1 - cx;
    }
    // Жалгыз калган майда бөлүктөр (чекит, үтүр) — алынып салынат
    var bigs = comps.where((c) => c.area >= 0.3 * med).toList();
    comps = comps.where((c) {
      if (c.area >= 0.3 * med) return true;
      for (final d in bigs) {
        final ov = math.min(c.x1, d.x1) - math.max(c.x0, d.x0);
        if (ov >= -0.1 * hh && (c.yp - d.yp).abs() < 1.6 * hh) return true;
      }
      return false;
    }).toList();
    bigs = comps.where((c) => c.area >= 0.3 * med).toList();
    if (bigs.isEmpty) {
      return const FreeResult([], 'Жазуу саптары табылган жок.');
    }
    bigs.sort((a, b) => a.yp1.compareTo(b.yp1));
    final clus = <List<_Comp>>[
      [bigs.first]
    ];
    for (var i = 1; i < bigs.length; i++) {
      if (bigs[i].yp1 - clus.last.last.yp1 > 0.55 * hh) {
        clus.add([bigs[i]]);
      } else {
        clus.last.add(bigs[i]);
      }
    }
    var bands = <List<double>>[
      for (final cl in clus)
        [
          cl.map((c) => c.yp0).reduce(math.min),
          cl.map((c) => c.yp1).reduce(math.max)
        ]
    ];
    var sizes = [for (final cl in clus) cl.length];

    // Тексттин блогу: бири-бирине жакын турган саптар
    if (bands.length > 1) {
      final cen = [for (final b in bands) (b[0] + b[1]) / 2];
      final sp = [for (var i = 0; i + 1 < cen.length; i++) cen[i + 1] - cen[i]];
      final msp = _median(sp);
      final clusters = <List<int>>[
        [0]
      ];
      for (var i = 0; i < sp.length; i++) {
        if (sp[i] > 2.0 * msp) {
          clusters.add([i + 1]);
        } else {
          clusters.last.add(i + 1);
        }
      }
      var best = clusters.first;
      var bestW = -1;
      for (final cl in clusters) {
        var cnt = 0;
        for (final i in cl) {
          cnt += sizes[i];
        }
        if (cnt > bestW) {
          bestW = cnt;
          best = cl;
        }
      }
      bands = [for (final i in best) bands[i]];
      sizes = [for (final i in best) sizes[i]];
    }

    var rows = <List<_Comp>>[for (var i = 0; i < bands.length; i++) []];
    for (final c in comps) {
      var bi = 0;
      var bo = -1e18;
      for (var i = 0; i < bands.length; i++) {
        final ov = math.min(c.yp1, bands[i][1]) - math.max(c.yp0, bands[i][0]);
        if (ov > bo) {
          bo = ov;
          bi = i;
        }
      }
      if (bo <= -0.8 * hh) continue;
      rows[bi].add(c);
    }
    rows.removeWhere((r) => r.isEmpty);
    for (final r in rows) {
      r.sort((a, b) => a.x0.compareTo(b.x0));
    }
    var totalComps = 0;
    for (final r in rows) {
      totalComps += r.length;
    }
    if (rows.isEmpty || totalComps < n) {
      return FreeResult([],
          'Тамгалар толук табылган жок: $totalComps, керек: $n (${set.title}). '
          'Бардык тамгаларды жазгансызбы жана алар бири-бирине тийбейби?');
    }

    // --------------------- 7) ар бир сапты табигый боштуктар боюнча бөлүү
    List<List<_Comp>> splitRow(List<_Comp> r) {
      if (r.length == 1) {
        return [
          [r.first]
        ];
      }
      final gaps = <double>[];
      var mx = r.first.x1;
      for (var i = 1; i < r.length; i++) {
        gaps.add(math.max(0, r[i].x0 - mx).toDouble());
        if (r[i].x1 > mx) mx = r[i].x1;
      }
      final srt = List<double>.from(gaps)..sort((x, y) => y.compareTo(x));
      srt.add(0.15 * hh);
      var bestJ = -1;
      var bestR = 0.0;
      for (var j = 0; j + 1 < srt.length; j++) {
        if (srt[j] < 0.22 * hh) break;
        final rt = srt[j] / math.max(srt[j + 1], 1e-6);
        if (rt > bestR) {
          bestR = rt;
          bestJ = j;
        }
      }
      if (bestJ < 0) return [List<_Comp>.from(r)];
      final lim = srt[bestJ];
      final out = <List<_Comp>>[];
      var cur = <_Comp>[r.first];
      for (var i = 1; i < r.length; i++) {
        if (gaps[i - 1] >= lim) {
          out.add(cur);
          cur = [r[i]];
        } else {
          cur.add(r[i]);
        }
      }
      out.add(cur);
      return out;
    }

    var rowSplit = [for (final r in rows) splitRow(r)];
    var counts = [for (final rs in rowSplit) rs.length];
    var total = 0;
    for (final c in counts) {
      total += c;
    }

    // Кокустан кирген чийиндилер (кагаздын четиндеги майда белгилер) өзүнчө
    // «сап» болуп калышы мүмкүн — аларды алып салып көрөбүз.
    if (total != n && counts.length > 1) {
      final medC = _median([for (final c in counts) c.toDouble()]);
      final lim = math.max(4.0, 0.5 * medC);
      final dropIdx = [
        for (var i = 0; i < counts.length; i++)
          if (counts[i] <= lim) i
      ];
      final dn = math.min(dropIdx.length, 12);
      List<int>? bestDrop;
      var bestCnt = 1 << 30, bestRem = 1 << 30;
      for (var mask = 1; mask < (1 << dn); mask++) {
        var removed = 0, cnt = 0;
        for (var b = 0; b < dn; b++) {
          if ((mask >> b) & 1 == 1) {
            removed += counts[dropIdx[b]];
            cnt++;
          }
        }
        if (total - removed != n) continue;
        if (cnt < bestCnt || (cnt == bestCnt && removed < bestRem)) {
          bestCnt = cnt;
          bestRem = removed;
          bestDrop = [
            for (var b = 0; b < dn; b++)
              if ((mask >> b) & 1 == 1) dropIdx[b]
          ];
        }
      }
      if (bestDrop != null) {
        final kill = bestDrop.toSet();
        rows = [
          for (var i = 0; i < rows.length; i++)
            if (!kill.contains(i)) rows[i]
        ];
        rowSplit = [
          for (var i = 0; i < rowSplit.length; i++)
            if (!kill.contains(i)) rowSplit[i]
        ];
        counts = [
          for (var i = 0; i < counts.length; i++)
            if (!kill.contains(i)) counts[i]
        ];
        total = n;
      }
    }

    // Дал келбесе — эң ишенимдүү бөлүү чекиттерин DP менен тандайбыз
    // (ашыкча бөлүнгөн тамгаларды кошот, жабышканын ажыратат).
    if (total != n) {
      var comp = 0;
      for (final r in rows) {
        comp += r.length;
      }
      final gapsSorted = <List<double>>[];
      for (final r in rows) {
        final gg = <double>[];
        var mx = r.first.x1;
        for (var i = 1; i < r.length; i++) {
          gg.add(math.max(0, r[i].x0 - mx).toDouble());
          if (r[i].x1 > mx) mx = r[i].x1;
        }
        gg.sort((a, b) => b.compareTo(a));
        gapsSorted.add(gg);
      }
      const inf = 1e18;
      double cost(int i, int k) {
        if (k < 1 || k > rows[i].length) return inf;
        final gg = gapsSorted[i];
        if (k == 1) return gg.isEmpty ? 0.0 : (gg.first / hh) * 3.0;
        final nxt = k - 1 < gg.length ? gg[k - 1] : 0.0;
        return nxt / math.max(gg[k - 2], 1e-6);
      }

      final rN = rows.length;
      List<int>? ks;
      if (comp >= n && rN > 0) {
        final dp = List<List<double>>.generate(
            rN + 1, (_) => List<double>.filled(n + 1, inf));
        final pick = List<List<int>>.generate(
            rN + 1, (_) => List<int>.filled(n + 1, 0));
        dp[0][0] = 0;
        for (var i = 0; i < rN; i++) {
          for (var s2 = 0; s2 <= n; s2++) {
            if (dp[i][s2] >= inf) continue;
            final kMax = math.min(rows[i].length, n - s2);
            for (var k = 1; k <= kMax; k++) {
              final c2 = cost(i, k);
              if (c2 >= inf) continue;
              if (dp[i][s2] + c2 < dp[i + 1][s2 + k]) {
                dp[i + 1][s2 + k] = dp[i][s2] + c2;
                pick[i + 1][s2 + k] = k;
              }
            }
          }
        }
        if (dp[rN][n] < inf) {
          ks = List<int>.filled(rN, 0);
          var s2 = n;
          for (var i = rN; i > 0; i--) {
            ks[i - 1] = pick[i][s2];
            s2 -= pick[i][s2];
          }
        }
      }
      if (ks == null) {
        final per = [
          for (var i = 0; i < counts.length; i++) '${i + 1}-сап: ${counts[i]}'
        ].join(', ');
        return FreeResult([],
            'Тамгалардын саны дал келген жок.\n$per — баары $total, керек $n '
            '(${set.title}).\n'
            'Себеби: бир тамга жазылбай калган, же эки тамга бири-бирине '
            'тийип калган. Тартипти текшериңиз:\n'
            '${set.chars}');
      }
      rowSplit = [];
      for (var i = 0; i < rN; i++) {
        final r = rows[i];
        final gaps = <double>[];
        var mx = r.first.x1;
        for (var j = 1; j < r.length; j++) {
          gaps.add(math.max(0, r[j].x0 - mx).toDouble());
          if (r[j].x1 > mx) mx = r[j].x1;
        }
        final cut = <int>{};
        if (ks[i] > 1) {
          final lim = gapsSorted[i][ks[i] - 2];
          var made = 0;
          for (var j = 0; j < gaps.length && made < ks[i] - 1; j++) {
            if (gaps[j] >= lim) {
              cut.add(j);
              made++;
            }
          }
        }
        final out = <List<_Comp>>[];
        var cur = <_Comp>[r.first];
        for (var j = 1; j < r.length; j++) {
          if (cut.contains(j - 1)) {
            out.add(cur);
            cur = [r[j]];
          } else {
            cur.add(r[j]);
          }
        }
        out.add(cur);
        rowSplit.add(out);
      }
      counts = [for (final rs in rowSplit) rs.length];
      total = n;
    }

    // --------------------------------------------------------- 8) топтоо
    final groups = <List<_Comp>>[];
    final rowGroups = <List<int>>[];
    for (final rs in rowSplit) {
      final lg = <int>[];
      for (final gr in rs) {
        lg.add(groups.length);
        groups.add(gr);
      }
      rowGroups.add(lg);
    }

    // ---------------------------------------------- 9) глифтерди кесүү
    final alphas = List<Float64List?>.filled(n, null);
    final dims = List<List<int>>.filled(n, const [0, 0]);
    final baseR = List<double>.filled(n, 0);
    final topR = List<double>.filled(n, 0);
    for (final lg in rowGroups) {
      // Саптын жазуу сызыгы (кыйшыктыкты эске алып, четтегилерди алып салып)
      final cxs = <double>[
        for (final gi in lg)
          (groups[gi].map((c) => c.x0).reduce(math.min) +
                  groups[gi].map((c) => c.x1).reduce(math.max)) /
              2
      ];
      final res = <double>[
        for (var i = 0; i < lg.length; i++)
          groups[lg[i]].map((c) => c.y1).reduce(math.max) - cxs[i] * tan
      ];
      var b0 = _median(res);
      final inl = res.where((v) => (v - b0).abs() <= 0.35 * hh).toList();
      if (inl.length >= 3) b0 = _median(inl);
      for (var gidx = 0; gidx < lg.length; gidx++) {
        final gi = lg[gidx];
        final baseline = b0 + cxs[gidx] * tan;
        final gr = groups[gi];
        final ids = <int>{for (final c in gr) c.id};
        final mx0 = gr.map((c) => c.x0).reduce(math.min);
        final mx1 = gr.map((c) => c.x1).reduce(math.max);
        final my0 = gr.map((c) => c.y0).reduce(math.min);
        final my1 = gr.map((c) => c.y1).reduce(math.max);
        const pad = 2;
        final sx0 = math.max(0, mx0 - pad), sy0 = math.max(0, my0 - pad);
        final sx1 = math.min(w - 1, mx1 + pad), sy1 = math.min(h - 1, my1 + pad);
        final gw2 = sx1 - sx0 + 1, gh2 = sy1 - sy0 + 1;
        final m = Uint8List(gw2 * gh2);
        for (var y = 0; y < gh2; y++) {
          for (var x = 0; x < gw2; x++) {
            if (ids.contains(lab[(y + sy0) * w + x + sx0])) m[y * gw2 + x] = 1;
          }
        }
        final a = Float64List(gw2 * gh2);
        for (var y = 0; y < gh2; y++) {
          for (var x = 0; x < gw2; x++) {
            var on = false;
            for (var dy = -1; dy <= 1 && !on; dy++) {
              final ny = y + dy;
              if (ny < 0 || ny >= gh2) continue;
              for (var dx = -1; dx <= 1; dx++) {
                final nx = x + dx;
                if (nx < 0 || nx >= gw2) continue;
                if (m[ny * gw2 + nx] != 0) {
                  on = true;
                  break;
                }
              }
            }
            if (!on) continue;
            final rr = ratio[(y + sy0) * w + x + sx0];
            a[y * gw2 + x] =
                ((0.955 - rr) / 0.155).clamp(0.0, 1.0).toDouble();
          }
        }
        // Асты сызыкка жакын тамгаларды так сызыкка отургузабыз, ал эми
        // чыныгы куйруктуу тамгалар (д, у, р, ц, щ, ф, ң) ылдый калат.
        var d = my1 - baseline;
        if (d.abs() <= 0.28 * hh) d = 0;
        alphas[gi] = a;
        dims[gi] = [gw2, gh2];
        baseR[gi] = (my1 - sy0) - d;
        topR[gi] = (my0 - sy0).toDouble();
      }
    }

    // ------------------------------------------- 10) өлчөмгө келтирүү
    final measure = set.measure.isEmpty ? chars : set.measure;
    final heights = <double>[];
    for (final ch in measure.split('')) {
      final i = chars.indexOf(ch);
      if (i >= 0) heights.add(baseR[i] - topR[i]);
    }
    var xh = _median(heights);
    if (xh < 3) xh = hh;
    final k = (set.target / xh).clamp(1.0, 6.0).toDouble();

    final out = <HwGlyph>[];
    final codes = chars.codeUnits;
    for (var i = 0; i < n; i++) {
      final a = alphas[i]!;
      final ww = dims[i][0], hh2 = dims[i][1];
      final nw = math.max(1, (ww * k).round());
      final nh = math.max(1, (hh2 * k).round());
      var up = _resizeBilinear(a, ww, hh2, nw, nh);
      up = _gaussian(up, nw, nh, 0.2 * k);
      final bytes = Uint8List(nw * nh);
      for (var j = 0; j < bytes.length; j++) {
        final t = ((up[j] - 0.28) / 0.34).clamp(0.0, 1.0).toDouble();
        bytes[j] = (t * t * (3 - 2 * t) * 255).round();
      }
      out.add(HwGlyph(codes[i], nw, nh, (baseR[i] * k).round(), bytes));
    }

    if (set.id == 'lower') {
      final map = {for (final gl in out) gl.code: gl};
      HwSynth.fillMissing(map, set.target);
      return FreeResult(map.values.toList(), null);
    }
    return FreeResult(out, null);
  }

  // ----------------------------------------------------------- жардамчылар
  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List<double>.from(v)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static Float64List _boxBlur(Float64List a, int w, int h, int r) {
    final iw = w + 1;
    final ii = Float64List(iw * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      for (var x = 0; x < w; x++) {
        row += a[y * w + x];
        ii[(y + 1) * iw + x + 1] = ii[y * iw + x + 1] + row;
      }
    }
    final out = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final s = ii[y1 * iw + x1] -
            ii[y0 * iw + x1] -
            ii[y1 * iw + x0] +
            ii[y0 * iw + x0];
        out[y * w + x] = s / ((y1 - y0) * (x1 - x0));
      }
    }
    return out;
  }

  /// Кагаздын чеги [x0, y0, x1, y1] (үстөл кесилет).
  static List<int> _paperBox(Uint8List gray, int w, int h) {
    final f = Float64List(w * h);
    for (var i = 0; i < f.length; i++) {
      f[i] = gray[i].toDouble();
    }
    final b = _boxBlur(f, w, h, 12);
    final cv = <double>[];
    for (var y = h ~/ 4; y < 3 * h ~/ 4; y += 3) {
      for (var x = w ~/ 4; x < 3 * w ~/ 4; x += 3) {
        cv.add(b[y * w + x]);
      }
    }
    final ref = _median(cv);
    var bright = Uint8List(w * h);
    for (var i = 0; i < bright.length; i++) {
      bright[i] = b[i] > 0.72 * ref ? 1 : 0;
    }
    bright = _morph(bright, w, h, 3, true);
    bright = _morph(bright, w, h, 3, false);
    final lab = Int32List(w * h);
    final stack = Int32List(w * h);
    var bestId = 0, bestSize = 0, id = 0;
    var bx0 = 0, by0 = 0, bx1 = w, by1 = h;
    for (var s = 0; s < w * h; s++) {
      if (bright[s] == 0 || lab[s] != 0) continue;
      id++;
      var sp = 0;
      stack[sp++] = s;
      lab[s] = id;
      var size = 0, x0 = w, y0 = h, x1 = 0, y1 = 0;
      while (sp > 0) {
        final p = stack[--sp];
        final py = p ~/ w;
        final px = p - py * w;
        size++;
        if (px < x0) x0 = px;
        if (px > x1) x1 = px;
        if (py < y0) y0 = py;
        if (py > y1) y1 = py;
        if (px > 0 && bright[p - 1] != 0 && lab[p - 1] == 0) {
          lab[p - 1] = id;
          stack[sp++] = p - 1;
        }
        if (px < w - 1 && bright[p + 1] != 0 && lab[p + 1] == 0) {
          lab[p + 1] = id;
          stack[sp++] = p + 1;
        }
        if (py > 0 && bright[p - w] != 0 && lab[p - w] == 0) {
          lab[p - w] = id;
          stack[sp++] = p - w;
        }
        if (py < h - 1 && bright[p + w] != 0 && lab[p + w] == 0) {
          lab[p + w] = id;
          stack[sp++] = p + w;
        }
      }
      if (size > bestSize) {
        bestSize = size;
        bestId = id;
        bx0 = x0;
        by0 = y0;
        bx1 = x1;
        by1 = y1;
      }
    }
    if (bestId == 0) return [0, 0, w, h];
    final bw = bx1 - bx0 + 1, bh = by1 - by0 + 1;
    // Сүрөт толугу менен кагаз болсо, кесүүнүн кереги жок.
    if (bw * bh > 0.85 * w * h) return [0, 0, w, h];
    final mx = (0.015 * bw).toInt();
    final my = (0.015 * bh).toInt();
    return [bx0 + mx, by0 + my, bx1 - mx + 1, by1 - my + 1];
  }

  static Uint8List _morph(Uint8List a, int w, int h, int r, bool erode) {
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = erode ? 1 : 0;
        for (var d = -r; d <= r; d++) {
          final nx = x + d;
          final px = (nx < 0 || nx >= w) ? 0 : a[y * w + nx];
          if (erode) {
            if (px == 0) {
              v = 0;
              break;
            }
          } else if (px != 0) {
            v = 1;
            break;
          }
        }
        tmp[y * w + x] = v;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = erode ? 1 : 0;
        for (var d = -r; d <= r; d++) {
          final ny = y + d;
          final px = (ny < 0 || ny >= h) ? 0 : tmp[ny * w + x];
          if (erode) {
            if (px == 0) {
              v = 0;
              break;
            }
          } else if (px != 0) {
            v = 1;
            break;
          }
        }
        out[y * w + x] = v;
      }
    }
    return out;
  }

  static Float64List _resizeBilinear(
      Float64List a, int w, int h, int nw, int nh) {
    final out = Float64List(nw * nh);
    final sx = w / nw, sy = h / nh;
    for (var y = 0; y < nh; y++) {
      final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, h - 1.0).toDouble();
      final y0 = fy.floor();
      final y1 = math.min(h - 1, y0 + 1);
      final ty = fy - y0;
      for (var x = 0; x < nw; x++) {
        final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, w - 1.0).toDouble();
        final x0 = fx.floor();
        final x1 = math.min(w - 1, x0 + 1);
        final tx = fx - x0;
        final t = a[y0 * w + x0] * (1 - tx) + a[y0 * w + x1] * tx;
        final b = a[y1 * w + x0] * (1 - tx) + a[y1 * w + x1] * tx;
        out[y * nw + x] = t * (1 - ty) + b * ty;
      }
    }
    return out;
  }

  static Float64List _gaussian(Float64List a, int w, int h, double sigma) {
    if (sigma < 0.3) return a;
    final rad = math.max(1, (sigma * 3).ceil());
    final ker = List<double>.generate(2 * rad + 1, (i) {
      final d = (i - rad).toDouble();
      return math.exp(-d * d / (2 * sigma * sigma));
    });
    final sum = ker.reduce((x, y) => x + y);
    for (var i = 0; i < ker.length; i++) {
      ker[i] /= sum;
    }
    final tmp = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var d = -rad; d <= rad; d++) {
          final nx = (x + d).clamp(0, w - 1).toInt();
          s += a[y * w + nx] * ker[d + rad];
        }
        tmp[y * w + x] = s;
      }
    }
    final out = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var d = -rad; d <= rad; d++) {
          final ny = (y + d).clamp(0, h - 1).toInt();
          s += tmp[ny * w + x] * ker[d + rad];
        }
        out[y * w + x] = s;
      }
    }
    return out;
  }
}
