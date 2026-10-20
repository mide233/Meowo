import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';

void main() {
  const canvasKey = ValueKey('meowo-canvas');

  Future<AppState> pumpEditor(
    WidgetTester tester, {
    required String kind,
    Size size = const Size(1000, 900),
    void Function(Map<String, dynamic> page)? configurePage,
  }) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('meowo-zoom-ui-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final created = core.call('create_document', {
      'title': '缩放指示 $kind',
      'kind': kind,
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(created['id'] as String);
    if (configurePage != null) {
      configurePage(
        (state.activeDocument!['pages'] as List).first as Map<String, dynamic>,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  String zoomText(WidgetTester tester, CanvasViewState canvas) {
    return '${(canvas.zoom * 100).round()}%';
  }

  void expectZoomLabel(WidgetTester tester, CanvasViewState canvas) {
    expect(
      find.text(zoomText(tester, canvas)),
      findsOneWidget,
      reason: 'bottom bar should show ${zoomText(tester, canvas)}',
    );
  }

  testWidgets('paged zoom label follows wheel, pinch and fit page', (
    tester,
  ) async {
    await pumpEditor(tester, kind: 'paged');
    final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
    expect(find.text('100%'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(canvasKey)),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();
    expectZoomLabel(tester, canvas);
    expect(canvas.zoom, greaterThan(1.05));

    final center = tester.getCenter(find.byKey(canvasKey));
    final first = await tester.startGesture(center - const Offset(60, 0));
    final second = await tester.startGesture(center + const Offset(60, 0));
    await tester.pump();
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expectZoomLabel(tester, canvas);
    expect(canvas.zoom, greaterThan(1.05));

    await tester.tap(find.byTooltip('适应页面'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'infinite zoom label follows wheel, fit content and origin reset',
    (tester) async {
      await pumpEditor(
        tester,
        kind: 'infinite',
        configurePage: (page) {
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
        },
      );
      final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
      expectZoomLabel(tester, canvas);
      expect(canvas.zoom, isNot(0));
      final initialZoom = canvas.zoom;

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(canvasKey)),
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pumpAndSettle();
      expectZoomLabel(tester, canvas);
      expect(canvas.zoom, greaterThan(initialZoom * 1.2));

      await tester.tap(find.byTooltip('适应内容'));
      await tester.pumpAndSettle();
      expectZoomLabel(tester, canvas);
      expect(canvas.zoom, closeTo(initialZoom, 0.001));

      await tester.tap(find.byTooltip('回到原点'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('zoom label stays usable on a narrow infinite canvas', (
    tester,
  ) async {
    await pumpEditor(tester, kind: 'infinite', size: const Size(360, 720));
    expect(find.text('无极画布'), findsOneWidget);
    expect(find.byKey(const ValueKey('zoom-percentage')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
