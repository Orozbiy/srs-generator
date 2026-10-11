import 'dart:math' as math;

/// Бир кесим карандаш сызыгы: чекиттер [x0, y0, x1, y1, ...], жоондук жана
/// боз түс (0 — кара, 255 — ак). Сызык кыска бөлүктөргө бөлүнгөн, ошондуктан
/// ар бир бөлүктүн басымы (түсү жана жоондугу) аздап өзгөрүп турат.
class PencilStroke {
  final List<double> pts;
  final double width;
  final int gray;
  const PencilStroke(this.pts, this.width, this.gray);
}

/// Кара карандаш менен кол менен сызгандай геометрия. Таза Dart: Canvas'ка
/// да (диаграммалар), PDF'ке да (таблицалар) бирдей колдонулат.
///
/// Бирдик — чийилүүчү беттин бирдиги (Canvas'та логикалык пиксель,
/// PDF'те pt). Ар бир сызык аз-аздап толкундап, эки жолу сызылат: негизги
/// (караңгы) жана жука-ачык кайталоо — чыныгы карандаштай.
class Pencil {
  final math.Random _r;

  /// Сызыктын толкундоо амплитудасы.
  final double amp;

  /// Негизги сызыктын жоондугу.
  final double width;

  /// Чекиттердин ортосундагы аралык.
  final double step;

  /// Бир басым бөлүгүнүн узундугу.
  final double chunk;

  /// Эң караңгы боз деңгээл (басым максимум болгондо).
  final int dark;

  Pencil(
    int seed, {
    this.amp = 0.5,
    this.width = 1.0,
    this.step = 1.5,
    this.chunk = 4.0,
    this.dark = 0x26,
  }) : _r = math.Random(seed);

  double _u(double a, double b) => a + (b - a) * _r.nextDouble();

  int _gray(double intensity) {
    final i = intensity.clamp(0.0, 1.0).toDouble();
    return (0xDD + (dark - 0xDD) * i).round();
  }

  static List<double> _resample(List<double> p, double step) {
    final out = <double>[];
    if (p.length < 2) return out;
    out.add(p[0]);
    out.add(p[1]);
    for (var i = 2; i + 1 < p.length; i += 2) {
      final x0 = p[i - 2], y0 = p[i - 1], x1 = p[i], y1 = p[i + 1];
      final dx = x1 - x0, dy = y1 - y0;
      final len = math.sqrt(dx * dx + dy * dy);
      final n = math.max(1, (len / step).ceil());
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        out.add(x0 + dx * t);
        out.add(y0 + dy * t);
      }
    }
    return out;
  }

  static List<double> _extend(List<double> p, double a, double b) {
    final q = List<double>.of(p);
    var dx = p[2] - p[0], dy = p[3] - p[1];
    var l = math.sqrt(dx * dx + dy * dy);
    if (l > 0) {
      q[0] = p[0] - dx / l * a;
      q[1] = p[1] - dy / l * a;
    }
    final m = p.length;
    dx = p[m - 2] - p[m - 4];
    dy = p[m - 1] - p[m - 3];
    l = math.sqrt(dx * dx + dy * dy);
    if (l > 0) {
      q[m - 2] = p[m - 2] + dx / l * b;
      q[m - 1] = p[m - 1] + dy / l * b;
    }
    return q;
  }

  /// Бир өтүш: чекиттерди перпендикулярдык багытта жылмакай толкундатат,
  /// анан басымы (түсү/жоондугу) өзгөрүүчү кыска бөлүктөргө бөлөт.
  List<PencilStroke> _pass(List<double> d, double w, double ampK,
      double intensity, double trimStart, double trimEnd) {
    final n = d.length ~/ 2;
    if (n < 2) return const <PencilStroke>[];
    final s = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final dx = d[2 * i] - d[2 * i - 2];
      final dy = d[2 * i + 1] - d[2 * i - 1];
      s[i] = s[i - 1] + math.sqrt(dx * dx + dy * dy);
    }
    final total = s[n - 1];
    if (total < 0.3) {
      return [
        PencilStroke([d[0], d[1], d[0] + 0.05, d[1]], w * 1.2,
            _gray(intensity))
      ];
    }
    const tau = 2 * math.pi;
    final l1 = _u(35, 70), l2 = _u(10, 22);
    final p1 = _u(0, tau), p2 = _u(0, tau);
    final lp = _u(25, 60), pp = _u(0, tau);

    final xs = <double>[], ys = <double>[], ps = <double>[];
    for (var i = 0; i < n; i++) {
      final si = s[i];
      if (si < trimStart || si > total - trimEnd) continue;
      final a = math.max(0, i - 1), b = math.min(n - 1, i + 1);
      var tx = d[2 * b] - d[2 * a], ty = d[2 * b + 1] - d[2 * a + 1];
      final tl = math.sqrt(tx * tx + ty * ty);
      if (tl > 0) {
        tx /= tl;
        ty /= tl;
      }
      final nx = -ty, ny = tx;
      final off = amp *
          ampK *
          (0.65 * math.sin(tau * si / l1 + p1) +
              0.35 * math.sin(tau * si / l2 + p2));
      xs.add(d[2 * i] + nx * off);
      ys.add(d[2 * i + 1] + ny * off);
      // чети жеңилирээк (карандаш көтөрүлгөндөй)
      final edge = math.min(1.0, math.min(si, total - si) / 6.0);
      var pr = 0.5 + 0.5 * math.sin(tau * si / lp + pp);
      pr *= 0.55 + 0.45 * edge;
      ps.add(pr);
    }
    if (xs.length < 2) return const <PencilStroke>[];

    final out = <PencilStroke>[];
    var cur = <double>[xs[0], ys[0]];
    var acc = 0.0;
    var prSum = 0.0;
    var cnt = 0;
    for (var i = 1; i < xs.length; i++) {
      final dx = xs[i] - xs[i - 1], dy = ys[i] - ys[i - 1];
      acc += math.sqrt(dx * dx + dy * dy);
      cur.add(xs[i]);
      cur.add(ys[i]);
      prSum += ps[i];
      cnt++;
      if (acc >= chunk || i == xs.length - 1) {
        final pr = prSum / cnt;
        out.add(PencilStroke(
            cur, w * (0.85 + 0.3 * pr), _gray(intensity * (0.6 + 0.4 * pr))));
        cur = <double>[xs[i], ys[i]];
        acc = 0;
        prSum = 0;
        cnt = 0;
      }
    }
    return out;
  }

  List<PencilStroke> _twoPasses(List<double> d, double wScale, double ampScale,
      double fade, bool trim) {
    final inten = 1 - fade;
    final w = width * wScale;
    return [
      ..._pass(d, w, ampScale, inten, 0, 0),
      ..._pass(d, w * 0.65, ampScale * 1.2, inten * 0.62,
          trim ? _u(0, 1.8) : 0, trim ? _u(0, 1.8) : 0),
    ];
  }

  /// Ачык сызык (сынык сызык). [overshoot] — учтары бир аз өтүп кетет,
  /// кол менен сызгандай.
  List<PencilStroke> polyline(
    List<double> pts, {
    bool overshoot = false,
    double fade = 0,
    double wScale = 1,
    double ampScale = 1,
  }) {
    if (pts.length < 4) return const <PencilStroke>[];
    var p = List<double>.of(pts);
    if (overshoot) p = _extend(p, _u(0.5, 1.4), _u(0.5, 1.4));
    return _twoPasses(_resample(p, step), wScale, ampScale, fade, true);
  }

  /// Түз сызык.
  List<PencilStroke> line(double x0, double y0, double x1, double y1,
          {double fade = 0, double wScale = 1, double ampScale = 1}) =>
      polyline([x0, y0, x1, y1],
          overshoot: true, fade: fade, wScale: wScale, ampScale: ampScale);

  /// Туюк контур: башталышы аягы менен бир аз өтүп кесилишет.
  List<PencilStroke> closed(
    List<double> pts, {
    double fade = 0,
    double wScale = 1,
    double ampScale = 1,
  }) {
    if (pts.length < 6) return const <PencilStroke>[];
    final p = List<double>.of(pts)..add(pts[0])..add(pts[1]);
    final dx = pts[2] - pts[0], dy = pts[3] - pts[1];
    final l = math.sqrt(dx * dx + dy * dy);
    if (l > 0) {
      final e = math.min(_u(2.0, 3.5), l);
      p.add(pts[0] + dx / l * e);
      p.add(pts[1] + dy / l * e);
    }
    return _twoPasses(_resample(p, step), wScale, ampScale, fade, false);
  }

  /// Тик бурчтук: төрт өзүнчө сызык, бурчтарда бир аз кесилишет.
  List<PencilStroke> rect(double l, double t, double r, double b,
      {double fade = 0, double wScale = 1}) {
    return [
      ...line(l, t, r, t, fade: fade, wScale: wScale),
      ...line(r, t, r, b, fade: fade, wScale: wScale),
      ...line(r, b, l, b, fade: fade, wScale: wScale),
      ...line(l, b, l, t, fade: fade, wScale: wScale),
    ];
  }

  /// Тегеректелген бурчтуктун контуру (y ылдый багытта).
  static List<double> rrectPoints(
      double l, double t, double r, double b, double rad,
      {int segs = 6}) {
    final rr = math.min(rad, math.min((r - l) / 2, (b - t) / 2));
    final pts = <double>[];
    void arc(double cx, double cy, double a0) {
      for (var i = 0; i <= segs; i++) {
        final a = a0 + (math.pi / 2) * i / segs;
        pts.add(cx + rr * math.cos(a));
        pts.add(cy + rr * math.sin(a));
      }
    }

    arc(l + rr, t + rr, math.pi);
    arc(r - rr, t + rr, 1.5 * math.pi);
    arc(r - rr, b - rr, 0);
    arc(l + rr, b - rr, 0.5 * math.pi);
    return pts;
  }

  List<PencilStroke> rrect(double l, double t, double r, double b, double rad,
          {double fade = 0, double wScale = 1}) =>
      closed(rrectPoints(l, t, r, b, rad), fade: fade, wScale: wScale);

  /// Эллипс/айлана же жаасы. [sweep] берилбесе толук айлана (аягы бир аз өтөт).
  List<PencilStroke> ellipse(
    double cx,
    double cy,
    double rx,
    double ry, {
    double? start,
    double? sweep,
    double fade = 0,
    double wScale = 1,
  }) {
    final full = sweep == null;
    final a0 = start ?? _u(0, 2 * math.pi);
    final sw = sweep ?? (2 * math.pi + _u(0.12, 0.35));
    final per = sw * math.sqrt((rx * rx + ry * ry) / 2);
    final n = math.max(10, (per / (step * 2)).ceil());
    final pts = <double>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final ang = a0 + sw * t;
      var k = 1.0;
      if (full) {
        final over = ang - a0 - 2 * math.pi;
        if (over > 0) k = 1 - 0.03 * math.min(1.0, over / 0.35);
      }
      pts.add(cx + rx * k * math.cos(ang));
      pts.add(cy + ry * k * math.sin(ang));
    }
    return polyline(pts, fade: fade, wScale: wScale);
  }

  /// Дөңгөлөк штрих менен толтуруу үчүн жалпак (дөңгөл) көпбурчтук.
  /// [poly] — дөңгөл (convex) көпбурчтук [x0, y0, x1, y1, ...].
  List<PencilStroke> hatchPoly(
    List<double> poly, {
    double spacing = 3.5,
    double angle = math.pi / 4,
    double fade = 0.35,
    double wScale = 0.55,
  }) {
    final out = <PencilStroke>[];
    final m = poly.length ~/ 2;
    if (m < 3) return out;
    final a = angle + _u(-0.04, 0.04);
    final dx = math.cos(a), dy = math.sin(a);
    final nx = -dy, ny = dx;
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < m; i++) {
      final v = poly[2 * i] * nx + poly[2 * i + 1] * ny;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    var k = lo + spacing * _u(0.3, 0.8);
    while (k < hi - 0.2) {
      var tmin = double.infinity, tmax = -double.infinity;
      var cnt = 0;
      for (var i = 0; i < m; i++) {
        final ax = poly[2 * i], ay = poly[2 * i + 1];
        final j = (i + 1) % m;
        final bx = poly[2 * j], by = poly[2 * j + 1];
        final da = ax * nx + ay * ny - k;
        final db = bx * nx + by * ny - k;
        if ((da < 0 && db < 0) || (da > 0 && db > 0) || da == db) continue;
        final t = da / (da - db);
        final px = ax + (bx - ax) * t, py = ay + (by - ay) * t;
        final u = px * dx + py * dy;
        tmin = math.min(tmin, u);
        tmax = math.max(tmax, u);
        cnt++;
      }
      if (cnt >= 2 && tmax - tmin > 2.5) {
        final ta = tmin + _u(0.5, 1.6);
        final tb = tmax - _u(0.5, 1.6);
        if (tb > ta) {
          out.addAll(polyline(
            [nx * k + dx * ta, ny * k + dy * ta, nx * k + dx * tb, ny * k + dy * tb],
            fade: fade,
            wScale: wScale,
            ampScale: 0.5,
          ));
        }
      }
      k += spacing * _u(0.85, 1.15);
    }
    return out;
  }

  /// Тик бурчтукту штрих менен толтурат.
  List<PencilStroke> hatchRect(
    double l,
    double t,
    double r,
    double b, {
    double spacing = 3.5,
    double angle = math.pi / 4,
    double fade = 0.35,
  }) =>
      hatchPoly([l, t, r, t, r, b, l, b],
          spacing: spacing, angle: angle, fade: fade);

  /// Сызыкты [pattern] ([сызык, боштук, сызык, боштук, ...] — жуп сандагы
  /// узундуктар) боюнча үзүк-үзүк сызат.
  List<PencilStroke> dashed(
    List<double> pts,
    List<double> pattern, {
    double wScale = 1,
    double fade = 0,
  }) {
    final out = <PencilStroke>[];
    if (pts.length < 4 || pattern.length < 2) return out;
    var pi = 0;
    var on = true;
    var remain = pattern[0];
    var cur = <double>[pts[0], pts[1]];
    for (var i = 2; i + 1 < pts.length; i += 2) {
      var x0 = pts[i - 2], y0 = pts[i - 1];
      final x1 = pts[i], y1 = pts[i + 1];
      var segLen = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      if (segLen < 1e-9) continue;
      final dx = (x1 - x0) / segLen, dy = (y1 - y0) / segLen;
      while (segLen > 1e-9) {
        final use = math.min(segLen, remain);
        x0 += dx * use;
        y0 += dy * use;
        if (on) {
          cur.add(x0);
          cur.add(y0);
        }
        segLen -= use;
        remain -= use;
        if (remain <= 1e-9) {
          if (on && cur.length >= 4) {
            out.addAll(polyline(cur, wScale: wScale, fade: fade));
          }
          on = !on;
          pi = (pi + 1) % pattern.length;
          remain = pattern[pi];
          cur = on ? <double>[x0, y0] : <double>[];
        }
      }
    }
    if (on && cur.length >= 4) {
      out.addAll(polyline(cur, wScale: wScale, fade: fade));
    }
    return out;
  }
}
