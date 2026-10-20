import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/library_page.dart';

void main() {
  Map<String, dynamic> document() => {
    'id': 'doc_nav',
    'kind': 'paged',
    'paper': {'width': 500.0, 'height': 500.0, 'background': 'blank'},
  };

  Map<String, dynamic> page() => {
    'id': 'page_nav',
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
  };

  Future<void> pumpCanvas(
    WidgetTester tester, {
    String tool = 'pen',
    ValueChanged<int>? onPageSwipe,
    void Function()? onStroke,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(),
            page: page(),
            tool: tool,
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: const {},
            selectionBounds: null,
            lassoRect: false,
            onPageSwipe: onPageSwipe,
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
  }

  testWidgets('edge fling requests the next page at fit zoom', (tester) async {
    int? direction;
    await pumpCanvas(tester, onPageSwipe: (value) => direction = value);
    final size = tester.getSize(find.byType(CanvasView));
    await tester.flingFrom(
      Offset(size.width - 8, size.height / 2),
      const Offset(-140, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(direction, 1);
  });

  testWidgets('pen fling on the page draws instead of paging', (tester) async {
    var swipes = 0;
    var strokes = 0;
    await pumpCanvas(
      tester,
      onPageSwipe: (_) => swipes += 1,
      onStroke: () => strokes += 1,
    );
    final center = tester.getCenter(find.byType(CanvasView));
    await tester.flingFrom(
      center - const Offset(120, 0),
      const Offset(240, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(swipes, 0);
    expect(strokes, 1);
  });

  testWidgets('short hand-tool drag pans without paging', (tester) async {
    var swipes = 0;
    await pumpCanvas(tester, tool: 'hand', onPageSwipe: (_) => swipes += 1);
    final canvas = find.byKey(const ValueKey('meowo-canvas'));
    final before = tester.getTopLeft(canvas);
    await tester.dragFrom(const Offset(400, 400), const Offset(60, 0));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(canvas);
    expect(swipes, 0);
    expect(after.dx - before.dx, closeTo(60, 1.5));
  });

  testWidgets('hand-tool fling on the page requests the next page', (
    tester,
  ) async {
    int? direction;
    await pumpCanvas(
      tester,
      tool: 'hand',
      onPageSwipe: (value) => direction = value,
    );
    final center = tester.getCenter(find.byType(CanvasView));
    await tester.flingFrom(
      center - const Offset(120, 0),
      const Offset(-240, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(direction, 1);
  });

  testWidgets('page count opens cards and jumps to a page', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-page-picker-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '翻页测试',
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
    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 3 页'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-count-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-picker')), findsOneWidget);
    expect(find.text('当前第 3 / 3 页'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-card-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-card-0')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edge swipe moves a paged document to the previous page', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('meowo-page-swipe-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '滑动翻页',
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
    final topLeft = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    await tester.flingFrom(
      topLeft + Offset(6, size.height / 2),
      const Offset(140, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite canvas has no page picker', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-infinite-nav-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '无极导航',
      'kind': 'infinite',
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
    expect(find.text('无极画布'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-count-button')), findsNothing);
  });

  testWidgets('library shows an import overlay and disables import buttons', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('meowo-import-ui-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    state.importing = true;
    state.importLabel = 'PDF';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryPage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('import-progress')), findsOneWidget);
    expect(find.text('正在导入 PDF…'), findsOneWidget);
    final pdfButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('导入 PDF'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(pdfButton.onPressed, isNull);
    final barrier = tester.widget<ModalBarrier>(
      find.descendant(
        of: find.byKey(const ValueKey('import-progress')),
        matching: find.byType(ModalBarrier),
      ),
    );
    expect(barrier.dismissible, isFalse);
    expect(tester.takeException(), isNull);
  });
}
