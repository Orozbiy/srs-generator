import 'dart:convert';

enum DiagramKind { chart, circuit, block }

/// AI кайтарган ```chart / ```circuit / ```block блогунун мазмуну.
class DiagramSpec {
  final DiagramKind kind;
  final String title;
  final String caption;
  final Map<String, dynamic> data;

  const DiagramSpec({
    required this.kind,
    required this.title,
    required this.caption,
    required this.data,
  });

  static DiagramKind? kindOf(String fence) {
    switch (fence.trim().toLowerCase()) {
      case 'chart':
      case 'graph':
      case 'plot':
        return DiagramKind.chart;
      case 'circuit':
      case 'schema':
      case 'scheme':
        return DiagramKind.circuit;
      case 'block':
      case 'blockdiagram':
      case 'flowchart':
        return DiagramKind.block;
      default:
        return null;
    }
  }

  /// JSON бузук болсо null кайтарат — ошондо блок жөн эле таштап коюлат.
  static DiagramSpec? tryParse(DiagramKind kind, String body) {
    try {
      final decoded = jsonDecode(body.trim());
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return DiagramSpec(
        kind: kind,
        title: (map['title'] ?? '').toString(),
        caption: (map['caption'] ?? '').toString(),
        data: map,
      );
    } catch (_) {
      return null;
    }
  }

  // ---- chart ----
  String get chartType => (data['type'] ?? 'line').toString().toLowerCase();
  String get xLabel => (data['x'] ?? data['xlabel'] ?? '').toString();
  String get yLabel => (data['y'] ?? data['ylabel'] ?? '').toString();

  List<ChartSeries> get series {
    final raw = data['series'];
    if (raw is! List) return const [];
    final out = <ChartSeries>[];
    for (final s in raw) {
      if (s is! Map) continue;
      final pts = <ChartPoint>[];
      final rawPts = s['points'];
      if (rawPts is List) {
        for (final p in rawPts) {
          if (p is List && p.length >= 2) {
            final x = _num(p[0]);
            final y = _num(p[1]);
            if (x != null && y != null) pts.add(ChartPoint(x, y));
          } else if (p is Map) {
            final x = _num(p['x']);
            final y = _num(p['y']);
            if (x != null && y != null) pts.add(ChartPoint(x, y));
          }
        }
      }
      if (pts.isNotEmpty) {
        out.add(ChartSeries((s['name'] ?? '').toString(), pts));
      }
    }
    return out;
  }

  // ---- circuit ----
  String get circuitLayout =>
      (data['layout'] ?? data['connection'] ?? 'series').toString().toLowerCase();

  String get sourceLabel => (data['source'] ?? '').toString();

  List<CircuitElement> get elements {
    final raw = data['elements'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          CircuitElement(
            (e['kind'] ?? e['type'] ?? 'R').toString().toUpperCase(),
            (e['label'] ?? '').toString(),
          ),
    ];
  }

  // ---- block ----
  List<String> get nodes {
    final raw = data['nodes'] ?? data['steps'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  List<String> get nodeShapes {
    final raw = data['shapes'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().toLowerCase()).toList();
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }
}

class ChartPoint {
  final double x;
  final double y;
  const ChartPoint(this.x, this.y);
}

class ChartSeries {
  final String name;
  final List<ChartPoint> points;
  const ChartSeries(this.name, this.points);
}

class CircuitElement {
  /// R — резистор, C — конденсатор, L — катушка, D — диод, S — ачкыч, M — мотор
  final String kind;
  final String label;
  const CircuitElement(this.kind, this.label);
}
