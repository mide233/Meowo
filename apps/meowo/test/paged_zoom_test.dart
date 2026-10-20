import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/canvas_view.dart';

void main() {
  const viewport = Size(800, 800);
  const pageSize = Size(500, 500);
  const canvasKey = ValueKey('meowo-canvas');

  Map<String, dynamic> document({String kind = 'paged'}) => {
    'id': 'doc_zoom_$kind',
    'kind': kind,
    'paper': {'width': 500.0, 'height': 500.0, 'background': 'blank'},
  };

  Map<String, dynamic> page({String kind = 'paged'}) => {
    'id': 'page_zoom_$kind',
    'width': kind == 'infinite' ? 1600.0 : 500.0,
    'height': kind == 'infinite' ? 1200.0 : 500.0,
    'layers': <dynamic>[],
  };

  Future<CanvasViewState> pumpCanvas(
    WidgetTester tester, {
    String kind = 'paged',
  }) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(
            document: document(kind: kind),
            page: page(kind: kind),
            tool: 'hand',
            color: Colors.black,
            width: 2,
            activeLayerId: 'layer_1',
            images: const {},
            selectionIds: const {},
            selectionBounds: null,
            lassoRect: false,
            onStroke: (_, _, _) {},
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

  Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(position: at, scrollDelta: Offset(0, dy)),
    );
    await tester.pump();
  }

  Future<void> pinchStep(
    WidgetTester tester, {
    required Offset center,
    required double startHalf,
    required double endHalf,
  }) async {
    final first = await tester.startGesture(center - Offset(startHalf, 0));
    final second = await tester.startGesture(center + Offset(startHalf, 0));
    await tester.pump();
    final delta = startHalf - endHalf;
    await first.moveBy(Offset(delta, 0));
    await second.moveBy(Offset(-delta, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();
  }

  test('paged centered offset follows viewport and fit scale', () {
    final fit = pagedFitScale(viewport, pageSize);
    expect(pagedCenteredOffset(viewport, pageSize, fit), const Offset(36, 36));
    expect(pagedCenterPull(kPagedMinZoom), 1);
    expect(pagedCenterPull(1.25), closeTo(0.5, 1e-9));
    expect(pagedCenterPull(kPagedCenterPullStartZoom), 0);
    expect(pagedCenterPull(2), 0);
  });

  testWidgets('paged wheel zoom-in keeps the focus point anchored', (
    tester,
  ) async {
    final state = await pumpCanvas(tester);
    const focus = Offset(620, 280);
    final world = state.screenToWorld(focus);

    for (var i = 0; i < 3; i++) {
      await wheel(tester, focus, -60);
      final screen = state.worldToScreen(world);
      expect(screen.dx, closeTo(focus.dx, 0.001));
      expect(screen.dy, closeTo(focus.dy, 0.001));
    }
    expect(state.scale, greaterThan(pagedFitScale(viewport, pageSize) * 1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged pinch zoom-in keeps the gesture focus anchored', (
    tester,
  ) async {
    final state = await pumpCanvas(tester);
    const focus = Offset(540, 300);
    final world = state.screenToWorld(focus);

    await pinchStep(tester, center: focus, startHalf: 80, endHalf: 180);
    final screen = state.worldToScreen(world);
    expect(screen.dx, closeTo(focus.dx, 0.01));
    expect(screen.dy, closeTo(focus.dy, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged wheel zoom-out eases to the centered fit position', (
    tester,
  ) async {
    final state = await pumpCanvas(tester);
    final fitScale = state.scale;
    final fitCenter = state.pagePixelRect!.center;
    expect(fitCenter, const Offset(400, 400));

    for (var i = 0; i < 3; i++) {
      await wheel(tester, const Offset(700, 150), -120);
    }
    expect(state.scale, greaterThan(fitScale * 2));

    await tester.dragFrom(const Offset(560, 560), const Offset(-300, 220));
    await tester.pumpAndSettle();
    final pannedCenter = state.pagePixelRect!.center;
    expect((pannedCenter - fitCenter).distance, greaterThan(100));

    final zooms = <double>[];
    final centers = <Offset>[];
    for (var i = 0; i < 10 && state.scale > fitScale + 0.0001; i++) {
      await wheel(tester, const Offset(400, 400), 60);
      zooms.add(state.scale / fitScale);
      centers.add(state.pagePixelRect!.center);
    }

    expect(state.scale, closeTo(fitScale, 0.0001));
    final pageRect = state.pagePixelRect!;
    expect(pageRect.left, closeTo(36, 0.001));
    expect(pageRect.top, closeTo(36, 0.001));
    expect(pageRect.width, closeTo(728, 0.001));
    expect(pageRect.height, closeTo(728, 0.001));
    expect((pageRect.center - fitCenter).distance, lessThan(0.001));

    final bandDistances = <double>[];
    for (var i = 0; i < centers.length; i++) {
      if (zooms[i] > kPagedMinZoom + 0.0001 &&
          zooms[i] < kPagedCenterPullStartZoom) {
        bandDistances.add((centers[i] - fitCenter).distance);
      }
    }
    // The pull is distributed across several zoom-out frames, not applied as
    // one final snap.
    expect(bandDistances.length, greaterThanOrEqualTo(2));
    expect(bandDistances.first, greaterThan(1));
    for (var i = 1; i < bandDistances.length; i++) {
      expect(bandDistances[i], lessThanOrEqualTo(bandDistances[i - 1] + 0.5));
    }
    expect(bandDistances.last, lessThan(bandDistances.first));
    expect(tester.getSize(find.byKey(canvasKey)), const Size(728, 728));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged pinch zoom-out eases to the centered fit position', (
    tester,
  ) async {
    final state = await pumpCanvas(tester);
    final fitScale = state.scale;
    final fitCenter = state.pagePixelRect!.center;

    await pinchStep(
      tester,
      center: const Offset(400, 400),
      startHalf: 100,
      endHalf: 200,
    );
    expect(state.scale, closeTo(fitScale * 2, 0.02));

    await tester.dragFrom(const Offset(520, 520), const Offset(-240, 180));
    await tester.pumpAndSettle();
    expect(
      (state.pagePixelRect!.center - fitCenter).distance,
      greaterThan(100),
    );

    final zooms = <double>[];
    final centers = <Offset>[];
    for (var i = 0; i < 6 && state.scale > fitScale + 0.0001; i++) {
      await pinchStep(
        tester,
        center: const Offset(400, 400),
        startHalf: 200,
        endHalf: 170,
      );
      zooms.add(state.scale / fitScale);
      centers.add(state.pagePixelRect!.center);
    }

    expect(state.scale, closeTo(fitScale, 0.0001));
    expect((state.pagePixelRect!.center - fitCenter).distance, lessThan(0.001));
    expect(state.pagePixelRect!.left, closeTo(36, 0.001));
    expect(state.pagePixelRect!.top, closeTo(36, 0.001));

    final bandDistances = <double>[];
    for (var i = 0; i < centers.length; i++) {
      if (zooms[i] > kPagedMinZoom + 0.0001 &&
          zooms[i] < kPagedCenterPullStartZoom) {
        bandDistances.add((centers[i] - fitCenter).distance);
      }
    }
    expect(bandDistances.length, greaterThanOrEqualTo(2));
    expect(bandDistances.first, greaterThan(1));
    expect(bandDistances.last, lessThan(bandDistances.first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite zoom-out keeps free panning instead of centering', (
    tester,
  ) async {
    final state = await pumpCanvas(tester, kind: 'infinite');
    expect(state.pagePixelRect, isNull);

    for (var i = 0; i < 3; i++) {
      await wheel(tester, const Offset(700, 150), -120);
    }
    await tester.dragFrom(const Offset(650, 650), const Offset(-500, -320));
    await tester.pumpAndSettle();
    final beforeZoomOut = state.viewOffset;

    for (var i = 0; i < 30; i++) {
      await wheel(tester, const Offset(400, 400), 120);
    }
    expect(state.scale, closeTo(kInfiniteMinZoom, 0.0001));
    expect(state.pagePixelRect, isNull);
    expect(state.viewOffset, isNot(equals(kInfiniteOriginScreen)));
    expect((state.viewOffset - beforeZoomOut).distance, greaterThan(100));

    final minOffset = state.viewOffset;
    await tester.dragFrom(const Offset(650, 650), const Offset(-120, -80));
    await tester.pumpAndSettle();
    expect(state.viewOffset.dx, lessThan(minOffset.dx - 100));
    expect(state.viewOffset.dy, lessThan(minOffset.dy - 60));
    expect(tester.takeException(), isNull);
  });
}
