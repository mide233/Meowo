import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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

  Map<String, dynamic> page({List<dynamic> elements = const []}) => {
    'id': 'page_selection',
    'width': pageSize,
    'height': pageSize,
    'layers': [
      {
        'id': 'layer_1',
        'visible': true,
        'locked': false,
        'opacity': 1.0,
        'elements': elements,
      },
    ],
  };

  Future<Offset Function(Offset)> pumpCanvas(
    WidgetTester tester, {
    required Set<String> selectionIds,
    required Rect? selectionBounds,
    required bool lassoRect,
    String tool = 'select',
    List<dynamic> elements = const [],
    void Function(List<Offset>, bool)? onSelection,
    void Function(Map<String, dynamic>)? onElementTap,
    void Function()? onSelectionCleared,
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
            page: page(elements: elements),
            tool: tool,
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
            onElementTap: (element) => onElementTap?.call(element),
            onSelection: (polygon, rectangle) =>
                onSelection?.call(polygon, rectangle),
            onSelectionMove: (delta) => onMove?.call(delta),
            onSelectionScale: (bounds) => onScale?.call(bounds),
            onSelectionGestureEnd: () {},
            onSelectionCleared: onSelectionCleared,
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

  Map<String, dynamic> textElement() => {
    'id': 'text_1',
    'type': 'text',
    'x': 100.0,
    'y': 100.0,
    'w': 160.0,
    'h': 80.0,
    'markdown': 'hello',
    'fontSize': 16.0,
    'lineHeight': 1.5,
    'color': '#222222',
  };

  testWidgets('pointer tool selects one element on tap', (tester) async {
    String? tapped;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: false,
      tool: 'pointer',
      elements: [textElement()],
      onElementTap: (element) => tapped = element['id'] as String?,
    );
    await tester.tapAt(toGlobal(const Offset(180, 140)));
    await tester.pumpAndSettle();
    expect(tapped, 'text_1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection tool tap does not directly pick an element', (
    tester,
  ) async {
    String? tapped;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: false,
      tool: 'select',
      elements: [textElement()],
      onElementTap: (element) => tapped = element['id'] as String?,
    );
    await tester.tapAt(toGlobal(const Offset(180, 140)));
    await tester.pumpAndSettle();
    expect(tapped, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer blank drag does not start a lasso selection', (
    tester,
  ) async {
    List<Offset>? polygon;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: false,
      tool: 'pointer',
      onSelection: (points, _) => polygon = points,
    );
    await tester.dragFrom(
      toGlobal(const Offset(300, 300)),
      const Offset(80, 60),
    );
    await tester.pumpAndSettle();
    expect(polygon, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer blank tap clears the current selection', (tester) async {
    var cleared = 0;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {'text_1'},
      selectionBounds: const Rect.fromLTWH(100, 100, 160, 80),
      lassoRect: false,
      tool: 'pointer',
      elements: [textElement()],
      onSelectionCleared: () => cleared += 1,
    );
    await tester.tapAt(toGlobal(const Offset(400, 400)));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  testWidgets('pointer tool drags a selected object', (tester) async {
    Offset? delta;
    final toGlobal = await pumpCanvas(
      tester,
      selectionIds: const {'text_1'},
      selectionBounds: const Rect.fromLTWH(100, 100, 160, 80),
      lassoRect: false,
      tool: 'pointer',
      elements: [textElement()],
      onMove: (value) => delta = value,
    );
    final start = toGlobal(const Offset(160, 140));
    final end = toGlobal(const Offset(185, 170));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(delta, isNotNull);
    expect(delta!.dx, closeTo(25, 1.5));
    expect(delta!.dy, closeTo(30, 1.5));
  });

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

  testWidgets('dragging a corner handle reports scaled bounds', (tester) async {
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

  testWidgets('hand tool pans the viewport', (tester) async {
    await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: false,
      tool: 'hand',
    );
    final canvas = find.byKey(const ValueKey('meowo-canvas'));
    final before = tester.getTopLeft(canvas);
    await tester.dragFrom(const Offset(400, 400), const Offset(55, 35));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(canvas);
    expect(after.dx - before.dx, closeTo(55, 1.5));
    expect(after.dy - before.dy, closeTo(35, 1.5));
  });

  testWidgets('mouse wheel zooms the canvas', (tester) async {
    await pumpCanvas(
      tester,
      selectionIds: const {},
      selectionBounds: null,
      lassoRect: false,
    );
    final canvas = find.byKey(const ValueKey('meowo-canvas'));
    final before = tester.getSize(canvas);
    final center = tester.getCenter(canvas);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pumpAndSettle();
    final after = tester.getSize(canvas);
    expect(after.width, greaterThan(before.width));
  });
}
