import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';

void main() {
  Map<String, dynamic> textElement(String id, double y) => {
    'id': id,
    'type': 'text',
    'x': 80.0,
    'y': y,
    'w': 180.0,
    'h': 100.0,
    'markdown': id,
    'fontSize': 16.0,
    'lineHeight': 1.5,
    'color': '#222222',
  };

  Future<({AppState state, CanvasViewState canvas})> pumpEditor(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('meowo-selection-ui-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '选择交互',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);

    final page = (state.activeDocument!['pages'] as List).first as Map;
    final layer = (page['layers'] as List).first as Map;
    (layer['elements'] as List)
      ..add(textElement('text_1', 80))
      ..add(textElement('text_2', 260))
      ..add({
        'id': 'image_1',
        'type': 'image',
        'assetId': 'missing_asset',
        'x': 340.0,
        'y': 80.0,
        'w': 120.0,
        'h': 80.0,
        'cropLeft': 0.0,
        'cropTop': 0.0,
        'cropRight': 1.0,
        'cropBottom': 1.0,
        'rotation': 0,
        'flipH': false,
        'flipV': false,
        'opacity': 1.0,
        'locked': false,
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
    return (state: state, canvas: canvas);
  }

  Offset globalPoint(
    WidgetTester tester,
    CanvasViewState canvas,
    Offset world,
  ) {
    return tester.getTopLeft(find.byType(CanvasView)) +
        canvas.worldToScreen(world);
  }

  testWidgets('pointer tap selects text without opening the editor', (
    tester,
  ) async {
    final setup = await pumpEditor(tester);
    await tester.tap(find.byTooltip('指针'));
    await tester.pumpAndSettle();

    await tester.tapAt(
      globalPoint(tester, setup.canvas, const Offset(170, 130)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-edit')), findsOneWidget);
    expect(find.text('编辑文本'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('selection-edit')));
    await tester.pumpAndSettle();
    expect(find.text('编辑文本'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rectangle selection keeps multi-select free of the edit button',
    (tester) async {
      final setup = await pumpEditor(tester);
      await tester.tap(find.byTooltip('框选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('自由套索'));
      await tester.pumpAndSettle();

      final start = globalPoint(tester, setup.canvas, const Offset(60, 60));
      final end = globalPoint(tester, setup.canvas, const Offset(300, 400));
      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();

      expect(find.text('已选 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-edit')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single image selection exposes the image edit button', (
    tester,
  ) async {
    final setup = await pumpEditor(tester);
    await tester.tap(find.byTooltip('指针'));
    await tester.pumpAndSettle();

    await tester.tapAt(
      globalPoint(tester, setup.canvas, const Offset(400, 120)),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选 1'), findsOneWidget);
    final edit = find.byKey(const ValueKey('selection-edit'));
    expect(edit, findsOneWidget);
    expect(tester.widget<IconButton>(edit).tooltip, '编辑图片');
    expect(find.text('编辑图片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
