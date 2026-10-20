import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/ink_ops.dart';

void main() {
  const canvasKey = ValueKey('meowo-canvas');

  Map<String, dynamic> document({String kind = 'infinite'}) => {
    'id': 'doc_infinite',
    'kind': kind,
    'paper': {'width': 500.0, 'height': 500.0, 'background': 'blank'},
  };

  Map<String, dynamic> page({
    String kind = 'infinite',
    List<dynamic> elements = const [],
    Map<String, dynamic>? body,
  }) => {
    'id': 'page_infinite',
    'width': kind == 'infinite' ? 1600.0 : 500.0,
    'height': kind == 'infinite' ? 1200.0 : 500.0,
    'layers': [
      {
        'id': 'layer_1',
        'visible': true,
        'locked': false,
        'opacity': 1.0,
        'elements': elements,
      },
    ],
    'body': body,
  };

  Future<CanvasViewState> pumpCanvas(
    WidgetTester tester, {
    String kind = 'infinite',
    String tool = 'hand',
    List<dynamic> elements = const [],
    Set<String> selectionIds = const {},
    Rect? selectionBounds,
    void Function(List<Offset>, List<double>, bool)? onStroke,
    void Function(Map<String, dynamic>)? onElementTap,
    void Function(Offset)? onSelectionMove,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(kind: kind),
            page: page(kind: kind, elements: elements),
            tool: tool,
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: selectionIds,
            selectionBounds: selectionBounds,
            lassoRect: false,
            onStroke: (points, pressures, highlighter) =>
                onStroke?.call(points, pressures, highlighter),
            onErase: (_) {},
            onEraseStart: () {},
            onEraseEnd: () {},
            onElementTap: (element) => onElementTap?.call(element),
            onSelection: (_, _) {},
            onSelectionMove: (delta) => onSelectionMove?.call(delta),
            onSelectionScale: (_) {},
            onSelectionGestureEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<CanvasViewState>(find.byType(CanvasView));
  }

  testWidgets('infinite viewport pans beyond the old fixed page rectangle', (
    tester,
  ) async {
    final state = await pumpCanvas(tester, tool: 'hand');
    expect(state.pagePixelRect, isNull);
    expect(tester.getSize(find.byKey(canvasKey)), const Size(800, 800));

    final initial = state.visibleWorldCenter;
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(const Offset(700, 700), const Offset(-600, -600));
      await tester.pumpAndSettle();
    }
    expect(state.visibleWorldCenter.dx, greaterThan(1600));
    expect(state.visibleWorldCenter.dy, greaterThan(1200));
    expect(state.visibleWorldCenter.dx, greaterThan(initial.dx + 2000));
    expect(state.visibleWorldRect.left, greaterThanOrEqualTo(-100000));
    expect(state.visibleWorldRect.top, greaterThanOrEqualTo(-100000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pen strokes can be placed at negative world coordinates', (
    tester,
  ) async {
    List<Offset>? points;
    await pumpCanvas(
      tester,
      tool: 'pen',
      onStroke: (value, _, _) => points = value,
    );
    expect(points, isNull);
    await tester.dragFrom(const Offset(30, 30), const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(points, isNotNull);
    expect(points!.first.dx, lessThan(0));
    expect(points!.first.dy, lessThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative-coordinate element can be selected and moved', (
    tester,
  ) async {
    final element = <String, dynamic>{
      'id': 'text_negative',
      'type': 'text',
      'x': -600.0,
      'y': -400.0,
      'w': 120.0,
      'h': 60.0,
      'markdown': 'negative',
      'fontSize': 16.0,
      'lineHeight': 1.5,
      'color': '#222222',
    };
    String? tapped;
    Offset? moved;
    final state = await pumpCanvas(
      tester,
      tool: 'select',
      elements: [element],
      onElementTap: (value) => tapped = value['id'] as String?,
      onSelectionMove: (delta) => moved = delta,
    );
    final center = state.worldToScreen(const Offset(-540, -370));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(tapped, 'text_negative');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(),
            page: page(elements: [element]),
            tool: 'select',
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: const {'text_negative'},
            selectionBounds: const Rect.fromLTWH(-600, -400, 120, 60),
            lassoRect: false,
            onStroke: (_, _, _) {},
            onErase: (_) {},
            onEraseStart: () {},
            onEraseEnd: () {},
            onElementTap: (_) {},
            onSelection: (_, _) {},
            onSelectionMove: (delta) => moved = delta,
            onSelectionScale: (_) {},
            onSelectionGestureEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refreshed = tester.state<CanvasViewState>(find.byType(CanvasView));
    final start = refreshed.worldToScreen(const Offset(-540, -370));
    await tester.dragFrom(start, const Offset(30, 20));
    await tester.pumpAndSettle();
    expect(moved, isNotNull);
    expect(moved!.dx, closeTo(30 / refreshed.scale, 1.5));
    expect(moved!.dy, closeTo(20 / refreshed.scale, 1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite panning clamps to the logical bounds', (tester) async {
    final state = await pumpCanvas(tester, tool: 'hand');
    final center = tester.getCenter(find.byKey(canvasKey));
    for (var i = 0; i < 9; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();
    }
    expect(state.scale, closeTo(kInfiniteMinZoom, 0.001));
    for (var i = 0; i < 24; i++) {
      await tester.dragFrom(const Offset(700, 700), const Offset(-600, -600));
      await tester.pump();
    }
    expect(state.visibleWorldRect.right, lessThanOrEqualTo(100000.001));
    expect(state.visibleWorldRect.bottom, lessThanOrEqualTo(100000.001));
    expect(state.visibleWorldRect.left, greaterThanOrEqualTo(-100000));
    expect(state.visibleWorldRect.top, greaterThanOrEqualTo(-100000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged documents still use the fitted page rectangle', (
    tester,
  ) async {
    final state = await pumpCanvas(tester, kind: 'paged');
    final pageRect = state.pagePixelRect;
    expect(pageRect, isNotNull);
    expect(pageRect!.width, closeTo(728, 0.5));
    expect(pageRect.height, closeTo(728, 0.5));
    expect(pageRect.left, closeTo(36, 0.5));
    expect(pageRect.top, closeTo(36, 0.5));
    expect(tester.getSize(find.byKey(canvasKey)), const Size(728, 728));
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite toolbar resets to origin and fits content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('meowo-infinite-toolbar-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final created = core.call('create_document', {
      'title': '无极工具栏',
      'kind': 'infinite',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(created['id'] as String);
    final page = (state.activeDocument!['pages'] as List).first as Map;
    final layer = (page['layers'] as List).first as Map;
    (layer['elements'] as List).add({
      'id': 'text_far',
      'type': 'text',
      'x': 5000.0,
      'y': 5000.0,
      'w': 120.0,
      'h': 60.0,
      'markdown': 'far',
      'fontSize': 16.0,
      'lineHeight': 1.5,
      'color': '#222222',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
    expect(find.byTooltip('回到原点'), findsOneWidget);
    expect(find.byTooltip('适应内容'), findsOneWidget);
    expect(find.byTooltip('适应页面'), findsNothing);
    expect(canvas.visibleWorldRect.contains(const Offset(5060, 5030)), isTrue);

    await tester.tap(find.byTooltip('回到原点'));
    await tester.pumpAndSettle();
    expect(canvas.worldToScreen(Offset.zero).dx, closeTo(64, 0.5));
    expect(canvas.worldToScreen(Offset.zero).dy, closeTo(64, 0.5));
    expect(canvas.visibleWorldRect.contains(const Offset(5060, 5030)), isFalse);

    await tester.tap(find.byTooltip('适应内容'));
    await tester.pumpAndSettle();
    expect(canvas.visibleWorldRect.contains(const Offset(5060, 5030)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite text boxes are created at the view center', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('meowo-infinite-text-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final created = core.call('create_document', {
      'title': '无极文本',
      'kind': 'infinite',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(created['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
    final center = canvas.visibleWorldCenter;

    await tester.tap(find.byTooltip('文本框'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '居中文本');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    final page = (state.activeDocument!['pages'] as List).first as Map;
    final layer = (page['layers'] as List).first as Map;
    final element = (layer['elements'] as List).last as Map;
    final width = element['w'] as double;
    expect((element['x'] as double) + width / 2, closeTo(center.dx, 1.0));
    expect((element['y'] as double) + 80, closeTo(center.dy, 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite export crops to content with padding', (tester) async {
    await tester.runAsync(() async {
      final exportPage = page(
        elements: [
          {
            'id': 'text_negative',
            'type': 'text',
            'x': -600.0,
            'y': -400.0,
            'w': 120.0,
            'h': 60.0,
            'markdown': 'negative export',
            'fontSize': 16.0,
            'lineHeight': 1.5,
            'color': '#222222',
          },
          {
            'id': 'stroke_far',
            'type': 'stroke',
            'width': 2.0,
            'points': [
              [2000, 1500, 1.0],
              [2100, 1560, 1.0],
            ],
          },
        ],
      );
      final region = infiniteContentBounds(exportPage);
      expect(region.left, lessThanOrEqualTo(-632));
      expect(region.top, lessThanOrEqualTo(-432));
      expect(region.right, greaterThanOrEqualTo(2132));
      expect(region.bottom, greaterThanOrEqualTo(1592));

      final png = await renderInfiniteCanvasPng(
        document: document(),
        page: exportPage,
        images: const {},
        region: region,
        pixelRatio: 1,
      );
      expect(png.length, greaterThan(1000));
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, closeTo(region.width, 1));
      expect(frame.image.height, closeTo(region.height, 1));
      frame.image.dispose();
      codec.dispose();
    });
  });

  test('infinite content bounds fall back to a documented viewport', () {
    expect(infiniteContentBounds(page()), kInfiniteEmptyExportBounds);
  });
}
