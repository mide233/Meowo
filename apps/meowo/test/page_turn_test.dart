import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/page_turn.dart';

void main() {
  const canvasKey = ValueKey('meowo-canvas');

  Map<String, dynamic> document({String kind = 'paged'}) => {
    'id': 'doc_turn',
    'kind': kind,
    'paper': {'width': 500.0, 'height': 500.0, 'background': 'blank'},
  };

  Map<String, dynamic> page(int index, {String kind = 'paged'}) => {
    'id': 'page_$index',
    'width': 500.0,
    'height': 500.0,
    'layers': [
      {
        'id': 'layer_1',
        'visible': true,
        'locked': false,
        'opacity': 1.0,
        'elements': <dynamic>[],
      },
    ],
    if (kind == 'book') 'sourceAssetId': 'asset_$index',
  };

  Future<PageTurnController> pumpLayer(
    WidgetTester tester, {
    int pageIndex = 1,
    int pageCount = 3,
    String documentKind = 'paged',
    String tool = 'hand',
    List<int>? requested,
    void Function()? onStroke,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = [for (var i = 0; i < pageCount; i++) page(i)];
    PageTurnController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageTurnLayer(
            document: document(kind: documentKind),
            pages: pages,
            pageIndex: pageIndex,
            images: const {},
            onPageRequested: (delta) async {
              requested?.add(delta);
            },
            builder: (context, pageTurn) {
              controller = pageTurn;
              return CanvasView(
                document: document(kind: documentKind),
                page: pages[pageIndex],
                tool: tool,
                color: Colors.black,
                width: 2,
                activeLayerId: 'layer_1',
                images: const {},
                selectionIds: const {},
                selectionBounds: null,
                lassoRect: false,
                pageTurnController: pageTurn,
                onStroke: (_, _, _) => onStroke?.call(),
                onErase: (_) {},
                onEraseStart: () {},
                onEraseEnd: () {},
                onElementTap: (_) {},
                onSelection: (_, _) {},
                onSelectionMove: (_) {},
                onSelectionScale: (_) {},
                onSelectionGestureEnd: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller!;
  }

  Future<CanvasViewState> pumpCanvas(
    WidgetTester tester, {
    required PageTurnController controller,
    String kind = 'paged',
    String tool = 'hand',
    void Function()? onStroke,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(kind: kind),
            page: page(0, kind: kind),
            tool: tool,
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: const {},
            selectionBounds: null,
            lassoRect: false,
            pageTurnController: controller,
            onStroke: (_, _, _) => onStroke?.call(),
            onErase: (_) {},
            onEraseStart: () {},
            onEraseEnd: () {},
            onElementTap: (_) {},
            onSelection: (_, _) {},
            onSelectionMove: (_) {},
            onSelectionScale: (_) {},
            onSelectionGestureEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<CanvasViewState>(find.byType(CanvasView));
  }

  PageTurnController createController(
    WidgetTester tester, {
    List<int>? requested,
  }) {
    final controller = PageTurnController(
      vsync: const TestVSync(),
      onPageRequested: (delta) async {
        requested?.add(delta);
      },
    );
    addTearDown(controller.dispose);
    controller.configure(
      enabled: true,
      hasPrevious: true,
      hasNext: true,
      viewportWidth: 800,
      reducedMotion: false,
    );
    return controller;
  }

  testWidgets('hand drag follows the finger and reveals next page', (
    tester,
  ) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    final center = tester.getCenter(find.byKey(canvasKey));
    expect(find.byKey(const ValueKey('page-turn-previews')), findsNothing);

    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    expect(controller.progress, closeTo(-120 / 800, 0.002));
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('page-turn-current')))
          .transform
          .getTranslation()
          .x,
      closeTo(-120, 0.5),
    );
    expect(find.byKey(const ValueKey('page-turn-previews')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('page-turn-preview-next')),
      findsOneWidget,
    );

    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, [1]);
    expect(controller.progress, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag right snaps to the previous page', (tester) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    final center = tester.getCenter(find.byKey(canvasKey));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    expect(controller.progress, closeTo(220 / 800, 0.002));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, [-1]);
    expect(controller.progress, 0);
  });

  testWidgets('short drag springs back without changing pages', (tester) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    final center = tester.getCenter(find.byKey(canvasKey));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(controller.progress, lessThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
    expect(controller.progress, 0);
    expect(controller.phase, PageTurnPhase.idle);
  });

  testWidgets('first page drag right is damped and does not change page', (
    tester,
  ) async {
    final requested = <int>[];
    final controller = await pumpLayer(
      tester,
      pageIndex: 0,
      requested: requested,
    );
    final center = tester.getCenter(find.byKey(canvasKey));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(controller.progress, greaterThan(0));
    expect(controller.progress, lessThanOrEqualTo(kPageTurnMaxEdgeProgress));
    expect(controller.progress, lessThan(300 / 800));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
    expect(controller.progress, 0);
  });

  testWidgets('last page drag left is damped and does not change page', (
    tester,
  ) async {
    final requested = <int>[];
    final controller = await pumpLayer(
      tester,
      pageIndex: 2,
      requested: requested,
    );
    final center = tester.getCenter(find.byKey(canvasKey));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();
    expect(controller.progress, lessThan(0));
    expect(
      controller.progress,
      greaterThanOrEqualTo(-kPageTurnMaxEdgeProgress),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
    expect(controller.progress, 0);
  });

  testWidgets('book pages use the same hand-drag page turn', (tester) async {
    final requested = <int>[];
    final controller = await pumpLayer(
      tester,
      documentKind: 'book',
      requested: requested,
    );
    final center = tester.getCenter(find.byKey(canvasKey));
    await tester.dragFrom(center, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(controller.progress, 0);
    expect(requested, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pen drag draws and never turns the page', (tester) async {
    final requested = <int>[];
    var strokes = 0;
    final controller = await pumpLayer(
      tester,
      tool: 'pen',
      requested: requested,
      onStroke: () => strokes += 1,
    );
    final center = tester.getCenter(find.byKey(canvasKey));
    await tester.dragFrom(center - const Offset(120, 0), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(controller.progress, 0);
    expect(requested, isEmpty);
    expect(strokes, 1);
  });

  testWidgets('hand drag pans when zoomed in beyond fit', (tester) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    final center = tester.getCenter(find.byKey(canvasKey));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(canvasKey);
    final before = tester.getTopLeft(canvas);
    await tester.dragFrom(center, const Offset(-160, 0));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(canvas);
    expect(controller.progress, 0);
    expect(requested, isEmpty);
    expect(after.dx - before.dx, closeTo(-160, 2));
  });

  testWidgets('paged zoom cannot shrink below fit-to-window', (tester) async {
    final controller = createController(tester);
    final state = await pumpCanvas(tester, controller: controller);
    final fitScale = state.scale;
    final center = tester.getCenter(find.byKey(canvasKey));
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();
    }
    expect(state.scale, closeTo(fitScale, 0.001));
    expect(tester.getSize(find.byKey(canvasKey)).width, closeTo(728, 0.5));
  });

  testWidgets('infinite canvas never page-turns even with a controller', (
    tester,
  ) async {
    final requested = <int>[];
    final controller = createController(tester, requested: requested);
    final state = await pumpCanvas(
      tester,
      controller: controller,
      kind: 'infinite',
      tool: 'hand',
    );
    final before = state.visibleWorldCenter;
    await tester.dragFrom(
      tester.getCenter(find.byKey(canvasKey)),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    final after = state.visibleWorldCenter;
    expect(controller.progress, 0);
    expect(requested, isEmpty);
    expect(after.dx, greaterThan(before.dx + 100));
  });

  testWidgets('two-finger pinch at fit zooms and does not turn the page', (
    tester,
  ) async {
    final requested = <int>[];
    await pumpLayer(tester, requested: requested);
    final state = tester.state<CanvasViewState>(find.byType(CanvasView));
    final before = state.scale;
    final center = tester.getCenter(find.byKey(canvasKey));
    final first = await tester.startGesture(center - const Offset(80, 0));
    final second = await tester.startGesture(center + const Offset(80, 0));
    await tester.pump();
    await first.moveBy(const Offset(-80, 0));
    await second.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(state.scale, greaterThan(before));
    expect(requested, isEmpty);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
  });

  testWidgets('middle-mouse drag pans and never turns pages', (tester) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    final canvas = find.byKey(canvasKey);
    final before = tester.getTopLeft(canvas);
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.moveBy(const Offset(-120, 20));
    await gesture.up();
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(canvas);
    expect(after.dx - before.dx, closeTo(-120, 2));
    expect(controller.progress, 0);
    expect(requested, isEmpty);
  });

  testWidgets('fling velocity commits without crossing the distance threshold', (
    tester,
  ) async {
    final requested = <int>[];
    final controller = await pumpLayer(tester, requested: requested);
    controller.cancel(animate: false);
    // Drive the controller directly with real timestamps so the fling path is
    // deterministic (widget-test pointer timestamps are usually zero).
    controller.canStart = true;
    controller.configure(
      enabled: true,
      hasPrevious: true,
      hasNext: true,
      viewportWidth: 800,
      reducedMotion: false,
    );
    expect(
      controller.begin(const Offset(400, 400), Duration.zero, pointer: 1),
      isTrue,
    );
    controller.update(
      const Offset(350, 400),
      const Duration(milliseconds: 16),
      pointer: 1,
    );
    controller.update(
      const Offset(300, 400),
      const Duration(milliseconds: 32),
      pointer: 1,
    );
    controller.end(
      const Offset(300, 400),
      const Duration(milliseconds: 40),
      pointer: 1,
    );
    await tester.pumpAndSettle();
    // 100 px is below the 200 px distance threshold, but 6250 px/s is a fling.
    expect(requested, [1]);
  });

  testWidgets('editor hand drag changes page and keeps the page label', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('meowo-page-turn-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '相册翻页',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 页'), findsOneWidget);

    await tester.tap(find.byTooltip('移动'));
    await tester.pumpAndSettle();
    final canvas = find.byType(CanvasView);
    final size = tester.getSize(canvas);
    final topLeft = tester.getTopLeft(canvas);
    await tester.dragFrom(
      topLeft + Offset(size.width / 2, size.height / 2),
      Offset(size.width * 0.35, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor pen drag does not change page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('meowo-page-turn-pen-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '笔迹翻页',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 页'), findsOneWidget);

    final canvas = find.byType(CanvasView);
    final size = tester.getSize(canvas);
    final topLeft = tester.getTopLeft(canvas);
    await tester.dragFrom(
      topLeft + Offset(size.width / 2, size.height / 2),
      Offset(-size.width * 0.4, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
