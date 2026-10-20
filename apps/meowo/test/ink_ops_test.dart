import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/ink_ops.dart';

void main() {
  test('pressure curve interpolates and clamps', () {
    expect(applyPressureCurve(0.5, kDefaultPressureCurve), closeTo(0.5, 0.001));
    expect(
      applyPressureCurve(0.5, const [Offset(0, 0), Offset(1, 0.5)]),
      closeTo(0.25, 0.001),
    );
    expect(
      applyPressureCurve(-1, const [Offset(0, 0.2), Offset(1, 1)]),
      closeTo(0.2, 0.001),
    );
    expect(
      applyPressureCurve(2, const [Offset(0, 0.2), Offset(1, 1)]),
      closeTo(1.0, 0.001),
    );
  });

  test('stroke hit testing uses the segment distance', () {
    final stroke = <String, dynamic>{
      'type': 'stroke',
      'width': 4.0,
      'points': [
        [0, 0, 1],
        [100, 0, 1],
      ],
    };
    expect(strokeTouches(stroke, const Offset(50, 3), 6), isTrue);
    expect(strokeTouches(stroke, const Offset(50, 80), 6), isFalse);
  });

  test('pixel erase splits a stroke and preserves style', () {
    final stroke = <String, dynamic>{
      'id': 'stroke_a',
      'type': 'stroke',
      'color': '#123456',
      'width': 4.0,
      'opacity': 0.8,
      'highlighter': false,
      'points': [
        [0, 0, 1.0],
        [100, 0, 0.5],
      ],
    };
    final parts = splitStroke(stroke, const Offset(50, 0), 10);
    expect(parts.length, 2);
    expect(parts.first['color'], '#123456');
    expect(parts.first['width'], 4.0);
    expect(parts.first['opacity'], 0.8);
    expect((parts.first['points'] as List).last[0], lessThan(50));
    expect((parts.last['points'] as List).first[0], greaterThan(50));
  });

  test('pixel erase removes a fully covered single point', () {
    final stroke = <String, dynamic>{
      'id': 'dot',
      'type': 'stroke',
      'width': 3.0,
      'points': [
        [10, 10, 1],
      ],
    };
    expect(splitStroke(stroke, const Offset(10, 10), 8), isEmpty);
  });

  test('element bounds, polygon hit and transforms', () {
    final element = <String, dynamic>{
      'type': 'image',
      'x': 10,
      'y': 20,
      'w': 100,
      'h': 50,
    };
    expect(elementBounds(element), const Rect.fromLTWH(10, 20, 100, 50));
    const polygon = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ];
    expect(pointInPolygon(const Offset(50, 50), polygon), isTrue);
    expect(pointInPolygon(const Offset(150, 50), polygon), isFalse);
    expect(
      rectIntersectsPolygon(const Rect.fromLTWH(90, 90, 30, 30), polygon),
      isTrue,
    );
    translateElement(element, const Offset(5, -5));
    expect(element['x'], 15);
    expect(element['y'], 15);
  });

  test('scaling maps stroke points and width into the new bounds', () {
    final source = <String, dynamic>{
      'type': 'stroke',
      'width': 2.0,
      'points': [
        [0, 0, 1],
        [10, 10, 1],
      ],
    };
    final target = jsonClone(source);
    scaleElement(
      source,
      target,
      const Rect.fromLTWH(0, 0, 10, 10),
      const Rect.fromLTWH(0, 0, 20, 20),
    );
    final points = target['points'] as List;
    expect(points.last[0], 20);
    expect(points.last[1], 20);
    expect(target['width'], closeTo(4.0, 0.01));
  });
}

Map<String, dynamic> jsonClone(Map<String, dynamic> source) {
  return <String, dynamic>{
    for (final entry in source.entries)
      entry.key: entry.value is List
          ? [
              for (final value in entry.value as List)
                value is List ? List<dynamic>.from(value) : value,
            ]
          : entry.value,
  };
}
