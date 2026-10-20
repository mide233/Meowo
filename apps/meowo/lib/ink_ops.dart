import 'dart:math' as math;
import 'dart:ui';

/// Default pressure response. Control points are normalized to [0, 1].
const List<Offset> kDefaultPressureCurve = <Offset>[
  Offset(0.0, 0.0),
  Offset(0.25, 0.25),
  Offset(0.5, 0.5),
  Offset(0.75, 0.75),
  Offset(1.0, 1.0),
];

/// Logical bounds for an infinite canvas (Q-038: about +/-100,000 pt).
///
/// The document origin remains `(0, 0)`; content may be placed on either side
/// of it. Panning is clamped so that the viewport stays inside these bounds.
const Rect kInfiniteCanvasBounds = Rect.fromLTRB(
  -100000,
  -100000,
  100000,
  100000,
);

/// Fallback export region for an empty infinite canvas.
const Rect kInfiniteEmptyExportBounds = Rect.fromLTWH(0, 0, 1000, 700);

/// Whether an infinite page has visible content that can be fitted/exported.
///
/// Infinite documents render text boxes only; legacy `page_body` data is kept
/// for compatibility but is neither rendered nor counted as content. This
/// keeps a new infinite document at the origin instead of zooming into a large
/// invisible text box.
bool hasInfiniteContent(Map<String, dynamic> page) {
  for (final value in page['layers'] as List? ?? const []) {
    final layer = value as Map;
    if (layer['visible'] == false) continue;
    if ((layer['elements'] as List? ?? const []).isNotEmpty) return true;
  }
  return false;
}

/// Content bounds for an infinite canvas export.
///
/// Only visible layer elements are included. Legacy `page_body` data is
/// intentionally ignored because infinite documents no longer render body
/// text. The returned rect is inflated by [padding]; an empty canvas falls
/// back to [kInfiniteEmptyExportBounds], which is documented in the report.
/// Content is intentionally not intersected with [kInfiniteCanvasBounds] so
/// legacy out-of-bounds data is not silently cropped.
Rect infiniteContentBounds(Map<String, dynamic> page, {double padding = 32}) {
  Rect? result;

  void include(Rect bounds) {
    result = result == null ? bounds : result!.expandToInclude(bounds);
  }

  for (final value in page['layers'] as List? ?? const []) {
    final layer = value as Map;
    if (layer['visible'] == false) continue;
    for (final elementValue in layer['elements'] as List? ?? const []) {
      if (elementValue is! Map) continue;
      final element = Map<String, dynamic>.from(elementValue);
      var bounds = elementBounds(element);
      if (element['type'] == 'image') {
        final rotation = ((element['rotation'] as num?)?.toDouble() ?? 0) % 360;
        // Rotated image content can extend outside its stored frame. Use the
        // conservative diagonal box so export never crops a rotated image.
        if (rotation.abs() > 0.01 && (rotation - 180).abs() > 0.01) {
          final halfDiagonal =
              math.sqrt(
                bounds.width * bounds.width + bounds.height * bounds.height,
              ) /
              2;
          bounds = Rect.fromCenter(
            center: bounds.center,
            width: halfDiagonal * 2,
            height: halfDiagonal * 2,
          );
        }
      }
      include(bounds);
    }
  }

  if (result == null) return kInfiniteEmptyExportBounds;
  return result!.inflate(padding);
}

List<Offset> normalizePressureCurve(Iterable<Offset> input) {
  final points =
      input
          .map(
            (p) => Offset(
              p.dx.clamp(0.0, 1.0).toDouble(),
              p.dy.clamp(0.0, 1.0).toDouble(),
            ),
          )
          .toList()
        ..sort((a, b) => a.dx.compareTo(b.dx));
  if (points.length < 2) return List<Offset>.from(kDefaultPressureCurve);
  points[0] = Offset(0, points.first.dy);
  points[points.length - 1] = Offset(1, points.last.dy);
  return points;
}

List<Offset> pressureCurveFromJson(dynamic raw) {
  if (raw is! List) return List<Offset>.from(kDefaultPressureCurve);
  final points = <Offset>[];
  for (final value in raw) {
    if (value is List && value.length >= 2) {
      final x = (value[0] as num?)?.toDouble();
      final y = (value[1] as num?)?.toDouble();
      if (x != null && y != null) points.add(Offset(x, y));
    }
  }
  return normalizePressureCurve(points);
}

List<List<double>> pressureCurveToJson(List<Offset> curve) {
  return [
    for (final point in normalizePressureCurve(curve)) [point.dx, point.dy],
  ];
}

List<Offset> pressureCurveFor(Map<String, dynamic> document, bool highlighter) {
  final settings = document['brushSettings'];
  if (settings is Map) {
    final brush = settings[highlighter ? 'highlighter' : 'pen'];
    if (brush is Map) {
      return pressureCurveFromJson(brush['curve']);
    }
  }
  return List<Offset>.from(kDefaultPressureCurve);
}

double applyPressureCurve(double pressure, List<Offset> curve) {
  final points = normalizePressureCurve(curve);
  final value = pressure.clamp(0.0, 1.0).toDouble();
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    if (value <= b.dx) {
      final span = b.dx - a.dx;
      if (span.abs() < 0.000001) return b.dy;
      final t = (value - a.dx) / span;
      return (a.dy + (b.dy - a.dy) * t).clamp(0.0, 1.0);
    }
  }
  return points.last.dy.clamp(0.0, 1.0);
}

Rect elementBounds(Map<String, dynamic> element) {
  if (element['type'] == 'stroke') {
    final raw = element['points'] as List? ?? const [];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final value in raw) {
      if (value is! List || value.length < 2) continue;
      final x = (value[0] as num?)?.toDouble();
      final y = (value[1] as num?)?.toDouble();
      if (x == null || y == null) continue;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    if (!minX.isFinite) return Rect.zero;
    final padding = ((element['width'] as num?)?.toDouble() ?? 2.0) * 0.5 + 3.0;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(padding);
  }
  final x = (element['x'] as num?)?.toDouble() ?? 0;
  final y = (element['y'] as num?)?.toDouble() ?? 0;
  final w = (element['w'] as num?)?.toDouble() ?? 100;
  final h = (element['h'] as num?)?.toDouble() ?? 60;
  return Rect.fromLTWH(x, y, w, h);
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared < 0.000001) return (point - a).distance;
  final t = (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / lengthSquared)
      .clamp(0.0, 1.0);
  final projection = Offset(a.dx + dx * t, a.dy + dy * t);
  return (point - projection).distance;
}

bool strokeTouches(Map<String, dynamic> stroke, Offset point, double radius) {
  final raw = stroke['points'] as List? ?? const [];
  if (raw.isEmpty) return false;
  if (raw.length == 1) {
    return (_pointOf(raw.first as List) - point).distance <= radius;
  }
  for (var i = 1; i < raw.length; i++) {
    final a = _pointOf(raw[i - 1] as List);
    final b = _pointOf(raw[i] as List);
    if (_distanceToSegment(point, a, b) <= radius) return true;
  }
  return false;
}

Rect boundsOfPoints(Iterable<Offset> points) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in points) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  if (!minX.isFinite) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

bool pointInPolygon(Offset point, List<Offset> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    final intersects =
        ((a.dy > point.dy) != (b.dy > point.dy)) &&
        (point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
    if (intersects) inside = !inside;
  }
  return inside;
}

bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset p, Offset q, Offset r) =>
      (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
  final d1 = cross(a, b, c);
  final d2 = cross(a, b, d);
  final d3 = cross(c, d, a);
  final d4 = cross(c, d, b);
  return ((d1 >= 0 && d2 <= 0) || (d1 <= 0 && d2 >= 0)) &&
      ((d3 >= 0 && d4 <= 0) || (d3 <= 0 && d4 >= 0));
}

bool rectIntersectsPolygon(Rect rect, List<Offset> polygon) {
  if (polygon.isEmpty) return false;
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  for (final point in polygon) {
    if (rect.contains(point)) return true;
  }
  for (final corner in corners) {
    if (pointInPolygon(corner, polygon)) return true;
  }
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    for (var j = 0; j < 4; j++) {
      if (_segmentsIntersect(a, b, corners[j], corners[(j + 1) % 4])) {
        return true;
      }
    }
  }
  return false;
}

Offset _pointOf(List value) {
  return Offset((value[0] as num).toDouble(), (value[1] as num).toDouble());
}

double _pressureOf(List value) {
  return value.length > 2 ? (value[2] as num).toDouble() : 1.0;
}

List<Map<String, dynamic>> splitStroke(
  Map<String, dynamic> stroke,
  Offset point,
  double radius,
) {
  final raw = stroke['points'] as List? ?? const [];
  final samples = <List<double>>[];
  if (raw.length == 1) {
    final only = raw.first as List;
    samples.add([_pointOf(only).dx, _pointOf(only).dy, _pressureOf(only)]);
  } else {
    for (var i = 1; i < raw.length; i++) {
      final a = raw[i - 1] as List;
      final b = raw[i] as List;
      final pa = _pointOf(a);
      final pb = _pointOf(b);
      final length = (pb - pa).distance;
      final steps = math.max(1, (length / 1.5).ceil()).clamp(1, 4000);
      for (var step = 0; step < steps; step++) {
        final t = step / steps;
        samples.add([
          pa.dx + (pb.dx - pa.dx) * t,
          pa.dy + (pb.dy - pa.dy) * t,
          _pressureOf(a) + (_pressureOf(b) - _pressureOf(a)) * t,
        ]);
      }
    }
    final last = raw.last as List;
    samples.add([_pointOf(last).dx, _pointOf(last).dy, _pressureOf(last)]);
  }

  final segments = <List<List<double>>>[];
  var current = <List<double>>[];
  for (final sample in samples) {
    final dx = sample[0] - point.dx;
    final dy = sample[1] - point.dy;
    final erased = dx * dx + dy * dy <= radius * radius;
    if (erased) {
      if (current.isNotEmpty) {
        segments.add(current);
        current = <List<double>>[];
      }
    } else {
      current.add(sample);
    }
  }
  if (current.isNotEmpty) segments.add(current);
  if (segments.length > 64) return const <Map<String, dynamic>>[];

  final result = <Map<String, dynamic>>[];
  final style = Map<String, dynamic>.from(stroke);
  style.remove('points');
  final baseId = stroke['id'] as String? ?? 'stroke';
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment.isEmpty) continue;
    final copy = Map<String, dynamic>.from(style)
      ..['id'] = '${baseId}_s${DateTime.now().microsecondsSinceEpoch}_$i'
      ..['points'] = [
        for (final sample in segment) [sample[0], sample[1], sample[2]],
      ];
    result.add(copy);
  }
  return result;
}

void translateElement(Map<String, dynamic> element, Offset delta) {
  if (element['type'] == 'stroke') {
    final raw = element['points'] as List? ?? const [];
    for (var i = 0; i < raw.length; i++) {
      final value = raw[i] as List;
      raw[i] = [
        (value[0] as num).toDouble() + delta.dx,
        (value[1] as num).toDouble() + delta.dy,
        if (value.length > 2) value[2],
      ];
    }
    return;
  }
  element['x'] = ((element['x'] as num?)?.toDouble() ?? 0) + delta.dx;
  element['y'] = ((element['y'] as num?)?.toDouble() ?? 0) + delta.dy;
}

void scaleElement(
  Map<String, dynamic> source,
  Map<String, dynamic> target,
  Rect from,
  Rect to,
) {
  final safeFromWidth = math.max(1.0, from.width);
  final safeFromHeight = math.max(1.0, from.height);
  final sx = to.width / safeFromWidth;
  final sy = to.height / safeFromHeight;
  final factor = math.sqrt((sx.abs() * sy.abs()).clamp(0.0001, 10000.0));

  if (source['type'] == 'stroke') {
    final raw = source['points'] as List? ?? const [];
    final points = <List<double>>[];
    for (final value in raw) {
      final list = value as List;
      points.add([
        to.left + ((list[0] as num).toDouble() - from.left) * sx,
        to.top + ((list[1] as num).toDouble() - from.top) * sy,
        if (list.length > 2) (list[2] as num).toDouble(),
      ]);
    }
    target['points'] = points;
    target['width'] = (((source['width'] as num?)?.toDouble() ?? 2.0) * factor)
        .clamp(0.5, 96.0);
    return;
  }

  final x = (source['x'] as num?)?.toDouble() ?? 0;
  final y = (source['y'] as num?)?.toDouble() ?? 0;
  final w = (source['w'] as num?)?.toDouble() ?? 100;
  final h = (source['h'] as num?)?.toDouble() ?? 60;
  target['x'] = to.left + (x - from.left) * sx;
  target['y'] = to.top + (y - from.top) * sy;
  target['w'] = math.max(8.0, w * sx);
  target['h'] = math.max(8.0, h * sy);
  if (source['type'] == 'text') {
    target['fontSize'] =
        (((source['fontSize'] as num?)?.toDouble() ?? 16.0) * factor).clamp(
          6.0,
          96.0,
        );
  }
}
