import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/canvas_view.dart';

void main() {
  const pageSize = 500.0;
  const margin = 36.0;

  Map<String, dynamic> document() => {
    'id': 'doc_selection',
    'kind': 'paged',
    'paper': {'width': pageSize, 'height': pageSize, 'background': 'blank'},
  };

  Map<String, dynamic> page() => {
    'id': 'page_selection',
    'width': pageSize,
    'height': pageSize,
    'layers': [
      {
        'id': 'layer_1',
        'visible': true,
        'locked': false,
        'opacity': 1.0,
        'elements': <dynamic>[],
      },
    ],
  };

  Future<Offset Function(Offset)> pumpCanvas(
    WidgetTester tester, {
    required Set<String> selectionIds,
    required Rect? selectionBounds,
    required bool lassoRect,
    void Function(List<Offset>, bool)? onSelection,
    void Function(Offset)? onMove,
    void Function(Rect)? onScale,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(),
            page: page(),
            tool: 'select',
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: selectionIds,
            selectionBounds: selectionBounds,
            lassoRect: lassoRect,
            onStroke: (_, _, _) {},
            onErase: (_) {},
            onEraseStart: () {},
            onEraseEnd: () {},
            onElementTap: (_) {},
            onSelection: (polygon, rectangle) =>
                onSelection?.call(polygon, rectangle),
            onSelectionMove: (delta) => onMove?.call(delta),
            onSelectionScale: (bounds) => onScale?.call(bounds),
            onSelectionGestureEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final view = tester.getSize(find.byType(CanvasView));
    final scale = math.min(
      (view.width - margin * 2) / pageSize,
      (view.height - margin * 2) / pageSize,
    );
    final origin = Offset(
      (view.width - pageSize * scale) / 2,
      (view.height - pageSize * scale) / 2,
    );
    return (point) => origin + point * scale;
  }

  testWidgets('rectangle lasso reports page-space polygon', (tester) async {
    List<Offset>? polygon;
    bool? rectangle;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: true,
      onSelection: (points, isRect) {
        polygon = points;
        rectangle = isRect;
      },
    );
    await tester.dragFrom(
      toGlobal(const Offset(50, 50)),
      toGlobal(const Offset(220, 180)) - toGlobal(const Offset(50, 50)),
    );
    await tester.pumpAndSettle();
    expect(rectangle, isTrue);
    expect(polygon, isNotNull);
    expect(polygon!.length, 4);
    expect(polygon!.first.dx, closeTo(50, 1.5));
    expect(polygon!.last.dy, closeTo(180, 1.5));
  });

  testWidgets('dragging inside a selection reports a move delta', (
    tester,
  ) async {
    Offset? delta;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {'stroke_1'},
      selectionBounds: const Rect.fromLTWH(40, 40, 180, 140),
      lassoRect: false,
      onMove: (value) => delta = value,
    );
    final start = toGlobal(const Offset(100, 100));
    final end = toGlobal(const Offset(125, 135));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(delta, isNotNull);
    expect(delta!.dx, closeTo(25, 1.5));
    expect(delta!.dy, closeTo(35, 1.5));
  });

  testWidgets('dragging a corner handle reports scaled bounds', (
    tester,
  ) async {
    Rect? scaled;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {'stroke_1'},
      selectionBounds: const Rect.fromLTWH(40, 40, 180, 140),
      lassoRect: false,
      onScale: (value) => scaled = value,
    );
    final start = toGlobal(const Offset(220, 180));
    final end = toGlobal(const Offset(250, 220));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(scaled, isNotNull);
    expect(scaled!.left, closeTo(40, 1.5));
    expect(scaled!.top, closeTo(40, 1.5));
    expect(scaled!.right, closeTo(250, 1.5));
    expect(scaled!.bottom, closeTo(220, 1.5));
  });
}
