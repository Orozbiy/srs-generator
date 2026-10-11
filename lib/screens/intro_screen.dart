import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Программа ачылганда 25 секунддук кириш анимациясы + «Баштоо» баскычы.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const double _total = 25;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 25),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1228),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final s = _c.value * _total;
          final btnOpacity = _seg(s, 1.2, 2.4);
          final pulse = s > 21 ? 1 + 0.035 * math.sin((s - 21) * 5) : 1.0;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _IntroPainter(s)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 36,
                child: Opacity(
                  opacity: btnOpacity,
                  child: Transform.scale(
                    scale: pulse,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF38BDF8)
                                  .withValues(alpha: s > 21 ? 0.55 : 0.25),
                              blurRadius: s > 21 ? 34 : 18,
                              spreadRadius: s > 21 ? 2 : 0,
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: _start,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1D4ED8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 34, vertical: 20),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32)),
                            textStyle: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('СРС жасоону баштаңыз'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

double _seg(double s, double a, double b) =>
    ((s - a) / (b - a)).clamp(0.0, 1.0).toDouble();
double _ease(double t) => Curves.easeInOutCubic.transform(t);
double _lerp(double a, double b, double t) => a + (b - a) * t;

class _IntroPainter extends CustomPainter {
  final double s;
  _IntroPainter(this.s);

  static final Map<String, TextPainter> _cache = {};
  static const _syms = [
    '∑', 'π', '∫', '√', 'Ω', 'E=mc²', 'U=IR', 'Δ', 'λ', 'H₂O', 'F=ma', 'x²',
    '∞', 'α', 'β', '%',
  ];
  static const _ink = Color(0xFF1F2F7A);

  @override
  bool shouldRepaint(covariant _IntroPainter old) => old.s != s;

  // ------------------------------------------------------------ жардамчылар
  void _text(Canvas c, String t, Offset center, double size, Color color,
      {FontWeight w = FontWeight.w600, double spacing = 0, double maxW = 900}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: w,
            letterSpacing: spacing,
            fontFamily: 'Segoe UI'),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxW);
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _icon(Canvas c, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
            fontSize: size,
            color: color,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _particle(Canvas c, String sym, double size, double alpha, Offset p) {
    final key = '$sym|$size|${(alpha * 100).round()}';
    final tp = _cache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: sym,
          style: TextStyle(
              fontSize: size,
              color: Colors.white.withValues(alpha: alpha),
              fontFamily: 'Segoe UI'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(c, p);
  }

  // ------------------------------------------------------------------ сызуу
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final full = Rect.fromLTWH(0, 0, w, h);

    // Фон
    final tBg = _seg(s, 0, 14);
    final top = Color.lerp(const Color(0xFF0B1228), const Color(0xFF0F2A6B), tBg)!;
    final bot =
        Color.lerp(const Color(0xFF1E3A8A), const Color(0xFF0EA5E9), _seg(s, 4, 22))!;
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.linear(
            Offset(w * 0.2, 0), Offset(w * 0.8, h), [top, bot]),
    );
    // Жарык тактары
    final gx = w * (0.5 + 0.3 * math.sin(s * 0.35));
    final gy = h * (0.45 + 0.2 * math.cos(s * 0.27));
    canvas.drawCircle(
      Offset(gx, gy),
      math.max(w, h) * 0.35,
      Paint()
        ..shader = ui.Gradient.radial(Offset(gx, gy), math.max(w, h) * 0.35, [
          const Color(0xFF38BDF8).withValues(alpha: 0.22),
          const Color(0xFF38BDF8).withValues(alpha: 0),
        ]),
    );

    // Учуп жүргөн формулалар
    final pIn = _seg(s, 0, 2);
    for (var i = 0; i < 26; i++) {
      final sym = _syms[i % _syms.length];
      final x = ((i * 0.6180339) % 1) * w;
      final speed = 0.012 + (i % 5) * 0.004;
      final yy = h * (1.1 - ((s * speed + i * 0.173) % 1) * 1.2);
      final alpha = (0.06 + 0.07 * (i % 3)) * pIn;
      _particle(canvas, sym, 16.0 + (i % 4) * 6, alpha, Offset(x, yy));
    }

    // Аймактар
    final areaTop = h * 0.2;
    final areaBot = h * 0.80;
    final areaH = areaBot - areaTop;
    final cx = w / 2;
    final cy = (areaTop + areaBot) / 2;

    _title(canvas, w, h);

    if (s >= 3.6 && s < 11.4) _paper(canvas, w, areaTop, areaH, cx, cy);
    if (s >= 11.0 && s < 17.2) _chips(canvas, w, areaH, cx, cy);
    if (s >= 16.6 && s < 22.2) _chart(canvas, w, areaH, cx, cy);
    if (s >= 21.6) _finale(canvas, w, areaH, cx, cy);
  }

  // ----------------------------------------------------------- 1) аталыш
  void _title(Canvas c, double w, double h) {
    final a = _seg(s, 0.3, 1.8);
    if (a <= 0) return;
    final mv = _ease(_seg(s, 3.2, 4.4));
    final y = _lerp(h * 0.40, h * 0.085, mv);
    final size = _lerp(46, 28, mv);
    final dy = (1 - _ease(a)) * 26;
    final cx = w / 2;

    // жаркыраган көлөкө
    c.save();
    c.translate(0, dy);
    _text(c, 'СРС ГЕНЕРАТОР', Offset(cx, y), size,
        Colors.white.withValues(alpha: a),
        w: FontWeight.w900, spacing: _lerp(6, 3, mv));
    final sub = _seg(s, 1.6, 2.7) * (1 - _seg(s, 3.0, 3.8));
    if (sub > 0) {
      _text(c, 'Студенттин өз алдынча иши — бир нече мүнөттө',
          Offset(cx, y + size * 1.15), 18,
          const Color(0xFFBAE6FD).withValues(alpha: sub),
          w: FontWeight.w500, maxW: w * 0.9);
      // сызык
      final lw = 160 * _ease(_seg(s, 2.0, 3.0));
      c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, y + size * 1.15 + 34),
                width: lw,
                height: 3),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFF38BDF8).withValues(alpha: sub),
      );
    }
    c.restore();
  }

  // ------------------------------------------------- 2) кагаз жана кол жазма
  void _paper(Canvas c, double w, double areaTop, double areaH, double cx,
      double cy) {
    final enter = _ease(_seg(s, 3.8, 5.4));
    final exit = _ease(_seg(s, 10.3, 11.3));
    final op = enter * (1 - exit);
    if (op <= 0) return;
    final pw = math.min(w * 0.8, 540.0);
    final ph = areaH * 0.98;
    final dy = (1 - enter) * areaH * 0.5;
    final sc = 1 - 0.12 * exit;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph);

    c.saveLayer(
        Rect.fromLTWH(-50, -50, w + 100, areaTop + areaH + 400),
        Paint()..color = Colors.white.withValues(alpha: op));
    c.translate(cx, cy + dy);
    c.scale(sc);
    c.translate(-cx, -cy);

    // көлөкө + барак
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    c.drawRRect(
        rr.shift(const Offset(0, 14)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    c.drawRRect(rr, Paint()..color = const Color(0xFFFFFEF8));

    c.save();
    c.clipRRect(rr);
    const nLines = 8;
    final gap = ph / (nLines + 1.6);
    final left = rect.left + pw * 0.14;
    // Торчо сызыктар
    for (var i = 0; i < nLines; i++) {
      final y = rect.top + gap * (i + 1.5);
      c.drawLine(
          Offset(rect.left, y),
          Offset(rect.right, y),
          Paint()
            ..color = const Color(0xFF93C5FD).withValues(alpha: 0.55)
            ..strokeWidth = 1);
    }
    // Талаа
    c.drawLine(
        Offset(rect.left + pw * 0.1, rect.top),
        Offset(rect.left + pw * 0.1, rect.bottom),
        Paint()
          ..color = const Color(0xFFFCA5A5).withValues(alpha: 0.8)
          ..strokeWidth = 1.5);

    // Жазуу сызыктары
    const lens = [0.62, 0.78, 0.7, 0.78, 0.6, 0.76, 0.5];
    Offset? pen;
    var penLine = -1;
    for (var i = 0; i < lens.length; i++) {
      final t0 = 5.6 + i * 0.66;
      final f = _seg(s, t0, t0 + 0.62);
      if (f <= 0) continue;
      final base = rect.top + gap * (i + 1.5) - 5;
      final totalLen = pw * lens[i];
      final path = Path();
      var first = true;
      for (double d = 0; d <= totalLen; d += 3) {
        final x = left + d + math.sin(d * 0.42 + i + 1.2) * 3.2;
        final y = base -
            (math.sin(d * 0.42 + i) * 4.2).abs() * (0.4 + 0.6 * math.sin(d * 0.07 + i).abs()) -
            math.sin(d * 0.11) * 1.2;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final m = metrics.first;
      final part = m.extractPath(0, m.length * f);
      c.drawPath(
          part,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == 0 ? 2.6 : 2.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      if (f < 1) {
        final tg = m.getTangentForOffset(m.length * f);
        if (tg != null) {
          pen = tg.position;
          penLine = i;
        }
      }
    }
    c.restore();

    // Калем
    if (pen != null && penLine >= 0) {
      final p = pen;
      c.drawLine(
          p,
          p + const Offset(20, -34),
          Paint()
            ..color = const Color(0xFF2563EB)
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round);
      c.drawLine(
          p,
          p + const Offset(4, -7),
          Paint()
            ..color = const Color(0xFF0F172A)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round);
    }

    // Формула штампы
    final fs = _ease(_seg(s, 9.2, 10.0));
    if (fs > 0) {
      c.save();
      c.translate(rect.right - pw * 0.2, rect.top + gap * 0.9);
      c.scale(0.7 + 0.3 * fs);
      _text(c, 'U = I · R', Offset.zero, 22,
          const Color(0xFF2563EB).withValues(alpha: fs),
          w: FontWeight.w800);
      c.restore();
    }
    c.restore();
  }

  // -------------------------------------------------------- 3) мүмкүнчүлүктөр
  void _chips(Canvas c, double w, double areaH, double cx, double cy) {
    final exit = _ease(_seg(s, 16.2, 17.0));
    const items = <List<Object>>[
      [Icons.functions, 'Формулалар', Color(0xFF6366F1)],
      [Icons.electrical_services, 'Электр схемалар', Color(0xFFF59E0B)],
      [Icons.bar_chart, 'Графиктер', Color(0xFF14B8A6)],
      [Icons.draw, 'Өз кол жазмаңыз', Color(0xFFEC4899)],
      [Icons.picture_as_pdf, 'PDF жана Word', Color(0xFFEF4444)],
      [Icons.school, '18 предмет', Color(0xFF22C55E)],
    ];
    final cw = math.min(w * 0.42, 290.0);
    const chH = 70.0;
    const gap = 18.0;
    final gridW = cw * 2 + gap;
    final gridH = chH * 3 + gap * 2;
    final x0 = cx - gridW / 2;
    final y0 = cy - gridH / 2;
    for (var i = 0; i < items.length; i++) {
      final t = _seg(s, 11.4 + i * 0.55, 12.2 + i * 0.55);
      if (t <= 0) continue;
      final k = Curves.easeOutBack.transform(t);
      final a = t * (1 - exit);
      if (a <= 0) continue;
      final col = i % 2, row = i ~/ 2;
      final center = Offset(
          x0 + col * (cw + gap) + cw / 2, y0 + row * (chH + gap) + chH / 2);
      c.save();
      c.translate(center.dx, center.dy);
      c.scale(0.6 + 0.4 * k);
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: cw, height: chH),
          const Radius.circular(18));
      c.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.13 * a));
      c.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white.withValues(alpha: 0.35 * a));
      final color = items[i][2] as Color;
      c.drawCircle(Offset(-cw / 2 + 38, 0), 22,
          Paint()..color = color.withValues(alpha: a));
      _icon(c, items[i][0] as IconData, Offset(-cw / 2 + 38, 0), 24,
          Colors.white.withValues(alpha: a));
      final tp = TextPainter(
        text: TextSpan(
            text: items[i][1] as String,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: a),
                fontFamily: 'Segoe UI')),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cw - 90);
      tp.paint(c, Offset(-cw / 2 + 74, -tp.height / 2));
      c.restore();
    }
    final cap = _seg(s, 12.0, 13.0) * (1 - exit);
    if (cap > 0) {
      _text(c, 'Баары бир жерде', Offset(cx, y0 - 34), 20,
          const Color(0xFFBAE6FD).withValues(alpha: cap),
          w: FontWeight.w600);
    }
  }

  // ------------------------------------------------------------ 4) график
  void _chart(Canvas c, double w, double areaH, double cx, double cy) {
    final enter = _ease(_seg(s, 16.8, 17.7));
    final exit = _ease(_seg(s, 21.4, 22.2));
    final op = enter * (1 - exit);
    if (op <= 0) return;
    final pw = math.min(w * 0.82, 580.0);
    final ph = areaH * 0.86;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    c.drawRRect(rr, Paint()..color = Colors.white.withValues(alpha: 0.10 * op));
    c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.3 * op));

    final ox = rect.left + 46, oy = rect.bottom - 64;
    final gw = pw - 92, gh = ph - 120;
    final ax = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * op)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final axT = _ease(_seg(s, 17.2, 17.9));
    c.drawLine(Offset(ox, oy), Offset(ox, oy - gh * axT), ax);
    c.drawLine(Offset(ox, oy), Offset(ox + gw * axT, oy), ax);
    // тор
    for (var i = 1; i <= 4; i++) {
      c.drawLine(
          Offset(ox, oy - gh * i / 4),
          Offset(ox + gw * axT, oy - gh * i / 4),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.12 * op)
            ..strokeWidth = 1);
    }
    // тилкелер
    for (var i = 0; i < 5; i++) {
      final t = _ease(_seg(s, 18.0 + i * 0.25, 19.2 + i * 0.25));
      final bw = gw / 9;
      final bx = ox + gw * 0.06 + i * (bw * 1.7);
      final bh = gh * (0.35 + 0.12 * ((i * 3) % 5)) * t;
      c.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(bx, oy - bh, bw, bh),
              topLeft: const Radius.circular(5),
              topRight: const Radius.circular(5)),
          Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.75 * op));
    }
    // ийри сызык
    final cp = Path();
    for (double d = 0; d <= 1.0001; d += 0.01) {
      final x = ox + gw * d;
      final y = oy - gh * (0.5 + 0.38 * math.sin(d * math.pi * 2.2 + 0.4));
      if (d == 0) {
        cp.moveTo(x, y);
      } else {
        cp.lineTo(x, y);
      }
    }
    final m = cp.computeMetrics().first;
    final f = _ease(_seg(s, 18.4, 21.0));
    c.drawPath(
        m.extractPath(0, m.length * f),
        Paint()
          ..color = const Color(0xFFFDE68A).withValues(alpha: op)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round);
    if (f > 0 && f < 1) {
      final tg = m.getTangentForOffset(m.length * f);
      if (tg != null) {
        c.drawCircle(tg.position, 7, Paint()..color = Colors.white);
      }
    }
    _text(c, 'Формула, схема жана графиктер өзү тартылат',
        Offset(cx, rect.top + 34), 18,
        Colors.white.withValues(alpha: op),
        w: FontWeight.w700, maxW: pw - 30);
  }

  // ---------------------------------------------------------------- 5) финал
  void _finale(Canvas c, double w, double areaH, double cx, double cy) {
    final t = _seg(s, 21.6, 23.0);
    final k = Curves.easeOutBack.transform(t);
    final r = 56 * k;
    for (var i = 0; i < 3; i++) {
      final f = ((s * 0.5) + i / 3) % 1;
      c.drawCircle(
          Offset(cx, cy - 20),
          56 + f * 110,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF7DD3FC)
                .withValues(alpha: (1 - f) * 0.35 * t));
    }
    c.drawCircle(
        Offset(cx, cy - 20),
        r,
        Paint()
          ..shader = ui.Gradient.linear(
              Offset(cx - r, cy - 20 - r),
              Offset(cx + r, cy - 20 + r),
              const [Color(0xFF38BDF8), Color(0xFF2563EB)]));
    _icon(c, Icons.check_rounded, Offset(cx, cy - 20), 62 * k,
        Colors.white.withValues(alpha: t));
    final a = _seg(s, 22.4, 23.6);
    _text(c, 'Баары даяр!', Offset(cx, cy + 74), 30,
        Colors.white.withValues(alpha: a),
        w: FontWeight.w900);
    _text(c, 'Төмөндөгү баскычты басып, СРСти жасап баштаңыз',
        Offset(cx, cy + 116), 17,
        const Color(0xFFBAE6FD).withValues(alpha: a),
        w: FontWeight.w500, maxW: w * 0.9);
  }
}
