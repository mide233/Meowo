import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'book_vector.dart';
import 'image_ops.dart';
import 'ink_ops.dart';
import 'page_turn.dart';

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.document,
    required this.page,
    required this.tool,
    required this.color,
    required this.width,
    required this.activeLayerId,
    required this.images,
    this.vectors = const <String, BookVectorPage>{},
    required this.selectionIds,
    required this.selectionBounds,
    required this.lassoRect,
    required this.onStroke,
    required this.onErase,
    required this.onEraseStart,
    required this.onEraseEnd,
    required this.onElementTap,
    required this.onSelection,
    required this.onSelectionMove,
    required this.onSelectionScale,
    required this.onSelectionGestureEnd,
    this.onSelectionCleared,
    this.pageTurnController,
    this.viewResetToken = 0,
    this.zoomNotifier,
  });

  final Map<String, dynamic> document;
  final Map<String, dynamic> page;
  final String tool;
  final Color color;
  final double width;
  final String activeLayerId;
  final Map<String, ui.Image> images;
  final Map<String, BookVectorPage> vectors;
  final Set<String> selectionIds;
  final Rect? selectionBounds;
  final bool lassoRect;
  final void Function(
    List<Offset> points,
    List<double> pressures,
    bool highlighter,
  )
  onStroke;
  final void Function(Offset point) onErase;
  final VoidCallback onEraseStart;
  final VoidCallback onEraseEnd;
  final void Function(Map<String, dynamic> element) onElementTap;
  final void Function(List<Offset> polygon, bool rectangle) onSelection;
  final void Function(Offset delta) onSelectionMove;
  final void Function(Rect bounds) onSelectionScale;
  final VoidCallback onSelectionGestureEnd;

  /// Called by the pointer tool when a tap does not hit an element.
  final VoidCallback? onSelectionCleared;

  /// Optional live zoom notifier. Values are relative zoom for paged/book
  /// documents (1.0 = fit) and absolute scale for infinite documents
  /// (1.0 = 100%).
  final ValueNotifier<double>? zoomNotifier;

  /// Optional album-style page-turn controller. Only active for paged/book
  /// documents at fit zoom with the hand tool; null disables page turning.
  final PageTurnController? pageTurnController;
  final int viewResetToken;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

const double kInfiniteMinZoom = 0.1;
const double kInfiniteMaxZoom = 8.0;
const double kPagedMinZoom = 1.0;
const double kPagedMaxZoom = 8.0;
const double kPagedPageMargin = 36.0;

/// Zoom level where paged zoom-out begins easing the page back to center.
///
/// Above this level wheel/pinch zoom keeps the normal focus-point behavior.
/// Between this level and [kPagedMinZoom] the offset is blended toward the
/// centered fit position, reaching it exactly at the minimum zoom.
const double kPagedCenterPullStartZoom = 1.5;
const Offset kInfiniteOriginScreen = Offset(64, 64);

Size pagedPageSize(Map<String, dynamic> document, Map<String, dynamic> page) {
  final paper = document['paper'] as Map?;
  final width =
      (page['width'] as num?)?.toDouble() ??
      (paper?['width'] as num?)?.toDouble() ??
      595.276;
  final height =
      (page['height'] as num?)?.toDouble() ??
      (paper?['height'] as num?)?.toDouble() ??
      841.89;
  return Size(width, height);
}

double pagedFitScale(Size viewport, Size pageSize) {
  return math
      .min(
        (viewport.width - kPagedPageMargin * 2) / pageSize.width,
        (viewport.height - kPagedPageMargin * 2) / pageSize.height,
      )
      .clamp(0.05, 4.0);
}

Rect pagedPageRect(Size viewport, Size pageSize) {
  final scale = pagedFitScale(viewport, pageSize);
  final fitted = Size(pageSize.width * scale, pageSize.height * scale);
  return Rect.fromLTWH(
    (viewport.width - fitted.width) / 2,
    (viewport.height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

/// Top-left screen offset that centers a page of [pageSize] at [scale].
///
/// At [pagedFitScale] this is the fixed fit-to-screen position used when a
/// paged/book document is opened. The caller supplies the current viewport
/// and page size so the result stays correct across layout changes.
Offset pagedCenteredOffset(Size viewport, Size pageSize, double scale) {
  return Offset(
    (viewport.width - pageSize.width * scale) / 2,
    (viewport.height - pageSize.height * scale) / 2,
  );
}

/// Progress of the paged zoom-out pull toward the centered fit position.
///
/// Returns 0 at or above [kPagedCenterPullStartZoom] and 1 at
/// [kPagedMinZoom], so repeated zoom-out steps ease the page back instead of
/// snapping it only on the final frame.
double pagedCenterPull(double zoom) {
  if (zoom >= kPagedCenterPullStartZoom) return 0;
  if (zoom <= kPagedMinZoom) return 1;
  return (kPagedCenterPullStartZoom - zoom) /
      (kPagedCenterPullStartZoom - kPagedMinZoom);
}

class CanvasViewState extends State<CanvasView> {
  final List<Offset> _points = [];
  final List<Offset> _lasso = [];
  final List<double> _pressures = [];
  bool _drawing = false;
  bool _selecting = false;
  String _selectGesture = '';
  Offset? _eraseLast;
  Offset? _selectStart;
  int _scaleHandle = -1;
  Rect? _scaleStartBounds;
  double _lastScale = 1.0;

  double _zoom = 1.0;
  Offset _offset = Offset.zero;
  double _fitScale = 1.0;
  bool _needsFit = true;
  String? _fittedPageId;
  bool _panning = false;
  Offset? _panLast;
  bool _middlePan = false;
  Offset? _middleLast;
  final _touches = <int, Offset>{};
  bool _viewGesture = false;
  double _baseZoom = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _baseCenter = Offset.zero;
  double _baseDistance = 1.0;
  bool? _pinchZoomingOut;

  Size _viewportSize = Size.zero;
  Size _pageSize = Size.zero;
  bool _pageTurnPending = false;

  bool get _atFitZoom => !_needsFit && (_zoom - 1.0).abs() < 0.02;

  bool get _isInfinite => widget.document['kind'] == 'infinite';

  bool _zoomPublishScheduled = false;

  /// Current relative zoom for paged/book documents, absolute scale for
  /// infinite documents.
  double get zoom => _zoom;

  void _scheduleZoomPublish() {
    final notifier = widget.zoomNotifier;
    if (notifier == null) return;
    if ((notifier.value - _zoom).abs() < 0.000001) return;
    if (_zoomPublishScheduled) return;
    _zoomPublishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _zoomPublishScheduled = false;
      if (!mounted) return;
      widget.zoomNotifier?.value = _zoom;
    });
  }

  Rect get _pagePixelRect => Rect.fromLTWH(
    _offset.dx,
    _offset.dy,
    _pageSize.width * _lastScale,
    _pageSize.height * _lastScale,
  );

  /// Absolute world-to-screen scale currently in use.
  double get scale => _lastScale;

  /// Screen position of the document origin.
  Offset get viewOffset => _offset;

  /// World-space rectangle currently visible in the viewport.
  Rect get visibleWorldRect {
    if (_viewportSize.isEmpty || _lastScale <= 0) return Rect.zero;
    return Rect.fromLTWH(
      -_offset.dx / _lastScale,
      -_offset.dy / _lastScale,
      _viewportSize.width / _lastScale,
      _viewportSize.height / _lastScale,
    );
  }

  Offset get visibleWorldCenter => visibleWorldRect.center;

  /// Pixel rectangle of the paper page for paged/book documents; null for
  /// infinite documents, which have no finite page frame.
  Rect? get pagePixelRect => _isInfinite ? null : _pagePixelRect;

  Offset worldToScreen(Offset point) => _offset + point * _lastScale;

  Offset screenToWorld(Offset point) => (point - _offset) / _lastScale;

  /// Resets an infinite canvas to 100% zoom with the origin near the top-left.
  void resetToOrigin() {
    if (!_isInfinite || _viewportSize.isEmpty) return;
    setState(() {
      _zoom = 1.0;
      _lastScale = 1.0;
      _offset = _clampInfiniteOffset(kInfiniteOriginScreen, 1.0);
      _needsFit = false;
      _fittedPageId = widget.page['id'] as String?;
    });
  }

  /// Fits the visible infinite-canvas content with a screen margin.
  ///
  /// Returns false (and falls back to the origin) when there is no content.
  bool fitContent() {
    if (!_isInfinite || _viewportSize.isEmpty) return false;
    if (!hasInfiniteContent(widget.page)) {
      resetToOrigin();
      return false;
    }
    setState(() {
      _fitInfiniteContent(_viewportSize);
      _needsFit = false;
      _fittedPageId = widget.page['id'] as String?;
    });
    return true;
  }

  @override
  void didUpdateWidget(covariant CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final documentChanged = oldWidget.document['id'] != widget.document['id'];
    if (documentChanged ||
        oldWidget.page['id'] != widget.page['id'] ||
        oldWidget.viewResetToken != widget.viewResetToken) {
      _zoom = 1.0;
      _offset = Offset.zero;
      _needsFit = true;
      _fittedPageId = null;
      _panning = false;
      _viewGesture = false;
      _touches.clear();
      _pageTurnPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final pageSize = pagedPageSize(widget.document, page);
    final width = pageSize.width;
    final height = pageSize.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = viewport;
        _pageSize = pageSize;
        final pageId = page['id'] as String?;

        if (_isInfinite) {
          widget.pageTurnController?.canStart = false;
          _fitScale = 1.0;
          if (_needsFit || _fittedPageId != pageId) {
            _initializeInfiniteView(viewport);
            _needsFit = false;
            _fittedPageId = pageId;
          }
          _lastScale = _zoom.clamp(kInfiniteMinZoom, kInfiniteMaxZoom);
          _zoom = _lastScale;
          _offset = _clampInfiniteOffset(_offset, _lastScale);
          _scheduleZoomPublish();
          return SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: ClipRect(
              child: MouseRegion(
                cursor: widget.tool == 'hand'
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.precise,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _onPointerSignal,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: (event) => _cancel(event.pointer),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.tool == 'pointer' ? _onTapUp : null,
                    child: CustomPaint(
                      key: const ValueKey('meowo-canvas'),
                      size: viewport,
                      painter: _painter(_lastScale),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final fitScale = pagedFitScale(viewport, pageSize);
        _fitScale = fitScale;
        if (_needsFit || _fittedPageId != pageId) {
          _zoom = 1.0;
          _offset = pagedCenteredOffset(viewport, pageSize, fitScale);
          _needsFit = false;
          _fittedPageId = pageId;
        }
        widget.pageTurnController?.canStart =
            widget.tool == 'hand' && _atFitZoom;
        final scale = fitScale * _zoom;
        _lastScale = scale;
        _scheduleZoomPublish();
        final canvasSize = Size(width * scale, height * scale);
        return SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: ClipRect(
            child: MouseRegion(
              cursor: widget.tool == 'hand'
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.precise,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: _onPointerSignal,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: (event) => _cancel(event.pointer),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: _offset.dx,
                      top: _offset.dy,
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: widget.tool == 'pointer' ? _onTapUp : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // The book background changes only when the page
                              // or zoom changes. Keeping it in its own repaint
                              // boundary prevents thousands of vector glyph
                              // paths from being replayed for every ink stroke.
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: BookBackgroundPainter(
                                    document: widget.document,
                                    page: page,
                                    scale: scale,
                                    images: widget.images,
                                    vectors: widget.vectors,
                                  ),
                                ),
                              ),
                              CustomPaint(
                                key: const ValueKey('meowo-canvas'),
                                painter: _painter(scale),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MeowoCanvasPainter _painter(double scale) {
    return MeowoCanvasPainter(
      document: widget.document,
      page: widget.page,
      scale: scale,
      viewOffset: _offset,
      images: widget.images,
      vectors: widget.vectors,
      paintBackground: false,
      inProgress: _points,
      inProgressPressures: _pressures,
      inProgressColor: widget.color,
      inProgressWidth: widget.width,
      inProgressHighlighter: widget.tool == 'highlighter',
      selectedIds: widget.selectionIds,
      selectionBounds: widget.selectionBounds,
      lassoPoints: _lasso,
      lassoRect: widget.lassoRect,
    );
  }

  Offset _toPage(Offset local) => (local - _offset) / _lastScale;

  void _initializeInfiniteView(Size viewport) {
    _zoom = 1.0;
    _lastScale = 1.0;
    if (hasInfiniteContent(widget.page)) {
      _fitInfiniteContent(viewport);
    } else {
      _offset = _clampInfiniteOffset(kInfiniteOriginScreen, 1.0);
    }
  }

  void _fitInfiniteContent(Size viewport) {
    final content = infiniteContentBounds(widget.page, padding: 48);
    final availableWidth = math.max(1.0, viewport.width - 96);
    final availableHeight = math.max(1.0, viewport.height - 96);
    final fitted = math
        .min(
          availableWidth / math.max(1.0, content.width),
          availableHeight / math.max(1.0, content.height),
        )
        .clamp(kInfiniteMinZoom, kInfiniteMaxZoom);
    _zoom = fitted;
    _lastScale = fitted;
    _offset = viewport.center(Offset.zero) - content.center * fitted;
    _offset = _clampInfiniteOffset(_offset, fitted);
  }

  Offset _clampInfiniteOffset(Offset candidate, double scale) {
    if (!_isInfinite || scale <= 0 || _viewportSize.isEmpty) return candidate;
    final viewWidth = _viewportSize.width / scale;
    final viewHeight = _viewportSize.height / scale;
    final left = _clampInfiniteAxis(
      -candidate.dx / scale,
      kInfiniteCanvasBounds.left,
      kInfiniteCanvasBounds.right,
      viewWidth,
    );
    final top = _clampInfiniteAxis(
      -candidate.dy / scale,
      kInfiniteCanvasBounds.top,
      kInfiniteCanvasBounds.bottom,
      viewHeight,
    );
    return Offset(-left * scale, -top * scale);
  }

  double _clampInfiniteAxis(
    double worldStart,
    double min,
    double max,
    double viewSize,
  ) {
    if (viewSize >= max - min) return (min + max - viewSize) / 2;
    return worldStart.clamp(min, max - viewSize);
  }

  void _panBy(Offset delta) {
    setState(() {
      _offset = _isInfinite
          ? _clampInfiniteOffset(_offset + delta, _lastScale)
          : _offset + delta;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(-event.scrollDelta.dy / 420);
    _zoomAt(event.localPosition, factor);
  }

  Offset _pagedCenterAt(double scale) {
    if (_viewportSize.isEmpty || _pageSize.isEmpty) return _offset;
    return pagedCenteredOffset(_viewportSize, _pageSize, scale);
  }

  /// Pulls a focus-based paged offset toward the centered fit position.
  ///
  /// Only called while zooming out; zoom-in keeps the normal focus-point
  /// behavior. At [kPagedMinZoom] the centered offset is returned exactly.
  Offset _pagedOffsetForZoomOut(Offset focusOffset, double zoom) {
    if (_isInfinite || _viewportSize.isEmpty || _pageSize.isEmpty) {
      return focusOffset;
    }
    final pull = pagedCenterPull(zoom);
    if (pull <= 0) return focusOffset;
    final centered = _pagedCenterAt(_fitScale * zoom);
    if (pull >= 1) return centered;
    return Offset.lerp(focusOffset, centered, pull)!;
  }

  void _zoomAt(Offset focus, double factor) {
    final oldScale = _fitScale * _zoom;
    if (oldScale <= 0) return;
    final pagePoint = (focus - _offset) / oldScale;
    final zoomingOut = factor < 1.0;
    final newZoom = _isInfinite
        ? (_zoom * factor).clamp(kInfiniteMinZoom, kInfiniteMaxZoom)
        : (_zoom * factor).clamp(kPagedMinZoom, kPagedMaxZoom);
    setState(() {
      _zoom = newZoom;
      final nextScale = _fitScale * _zoom;
      var nextOffset = focus - pagePoint * nextScale;
      if (zoomingOut) {
        nextOffset = _pagedOffsetForZoomOut(nextOffset, newZoom);
      }
      _offset = nextOffset;
      if (_isInfinite) {
        _lastScale = nextScale;
        _offset = _clampInfiniteOffset(_offset, nextScale);
      }
    });
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _startViewGesture();
        return;
      }
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kMiddleMouseButton) != 0) {
      _cancelActiveGesture();
      _middlePan = true;
      _middleLast = event.localPosition;
      return;
    }
    if (widget.tool == 'hand') {
      final turn = widget.pageTurnController;
      if (turn != null) {
        if (turn.busy) return;
        if (_isPageTurnPointer(event) &&
            turn.begin(
              event.localPosition,
              event.timeStamp,
              pointer: event.pointer,
            )) {
          _pageTurnPending = true;
          return;
        }
      }
      setState(() => _panning = true);
      _panLast = event.localPosition;
      return;
    }
    final point = _toPage(event.localPosition);
    if (widget.tool == 'pointer') {
      _pointerDown(point);
      return;
    }
    if (widget.tool == 'select') {
      _selectDown(point);
      return;
    }
    if (widget.tool == 'eraser') {
      _eraseLast = point;
      widget.onEraseStart();
      widget.onErase(point);
      return;
    }
    if (widget.tool != 'pen' && widget.tool != 'highlighter') return;
    setState(() {
      _drawing = true;
      _points
        ..clear()
        ..add(point);
      _pressures
        ..clear()
        ..add(_pressure(event));
    });
  }

  bool _isPageTurnPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    return (event.buttons & kPrimaryButton) != 0;
  }

  void _onMove(PointerMoveEvent event) {
    if (_middlePan) {
      final last = _middleLast;
      if (last != null) {
        _panBy(event.localPosition - last);
      }
      _middleLast = event.localPosition;
      return;
    }
    if (_viewGesture) {
      if (_touches.containsKey(event.pointer)) {
        _touches[event.pointer] = event.localPosition;
        _updateViewGesture();
      }
      return;
    }
    if (_pageTurnPending) {
      final turn = widget.pageTurnController;
      if (turn == null) {
        _pageTurnPending = false;
        return;
      }
      final drag = turn.update(
        event.localPosition,
        event.timeStamp,
        pointer: event.pointer,
      );
      if (drag == PageTurnDrag.vertical) {
        // The gesture was vertical after all; fall back to hand-tool panning
        // from the current position so the page does not jump.
        _pageTurnPending = false;
        setState(() => _panning = true);
        _panLast = event.localPosition;
      }
      return;
    }
    if (_panning) {
      final last = _panLast;
      if (last != null) {
        _panBy(event.localPosition - last);
      }
      _panLast = event.localPosition;
      return;
    }
    final point = _toPage(event.localPosition);
    if (widget.tool == 'pointer') {
      _selectMove(point, _lastScale);
      return;
    }
    if (widget.tool == 'select') {
      _selectMove(point, _lastScale);
      return;
    }
    if (widget.tool == 'eraser') {
      if (_eraseLast == null || (point - _eraseLast!).distance > 4) {
        _eraseLast = point;
        widget.onErase(point);
      }
      return;
    }
    if (!_drawing) return;
    setState(() {
      _points.add(point);
      _pressures.add(_pressure(event));
    });
  }

  void _onUp(PointerUpEvent event) {
    if (_middlePan) {
      _middlePan = false;
      _middleLast = null;
      return;
    }
    _touches.remove(event.pointer);
    if (_viewGesture) {
      if (_touches.length < 2) {
        _viewGesture = false;
        _touches.clear();
      }
      return;
    }
    if (_pageTurnPending) {
      _pageTurnPending = false;
      widget.pageTurnController?.end(
        event.localPosition,
        event.timeStamp,
        pointer: event.pointer,
      );
      return;
    }
    if (_panning) {
      setState(() => _panning = false);
      _panLast = null;
      return;
    }
    final point = _toPage(event.localPosition);
    if (widget.tool == 'pointer' || widget.tool == 'select') {
      _selectUp(point, _lastScale);
      return;
    }
    if (widget.tool == 'eraser') {
      _eraseLast = null;
      widget.onEraseEnd();
      return;
    }
    if (!_drawing) return;
    final points = List<Offset>.from(_points);
    final pressures = List<double>.from(_pressures);
    setState(() {
      _drawing = false;
      _points.clear();
      _pressures.clear();
    });
    if (points.isNotEmpty) {
      widget.onStroke(points, pressures, widget.tool == 'highlighter');
    }
  }

  void _startViewGesture() {
    _cancelActiveGesture();
    final points = _touches.values.take(2).toList();
    if (points.length < 2) return;
    _baseZoom = _zoom;
    _baseOffset = _offset;
    _baseCenter = (points[0] + points[1]) / 2;
    _baseDistance = math.max(1.0, (points[0] - points[1]).distance);
    _viewGesture = true;
    _pinchZoomingOut = null;
    _panning = false;
  }

  void _updateViewGesture() {
    final points = _touches.values.take(2).toList();
    if (points.length < 2) return;
    final center = (points[0] + points[1]) / 2;
    final distance = math.max(1.0, (points[0] - points[1]).distance);
    var nextZoom = _isInfinite
        ? (_baseZoom * distance / _baseDistance).clamp(
            kInfiniteMinZoom,
            kInfiniteMaxZoom,
          )
        : (_baseZoom * distance / _baseDistance).clamp(
            kPagedMinZoom,
            kPagedMaxZoom,
          );
    final intendedZoomOut = nextZoom < _zoom;
    var zoomingOut = intendedZoomOut;
    if (!_isInfinite &&
        _pinchZoomingOut != null &&
        intendedZoomOut != _pinchZoomingOut) {
      // The fingers reversed direction. Rebase onto the current camera so the
      // focus-based zoom-in path starts from where the eased zoom-out ended
      // instead of jumping back to the gesture's original offset.
      _baseZoom = _zoom;
      _baseOffset = _offset;
      _baseCenter = center;
      _baseDistance = distance;
      nextZoom = _zoom;
      zoomingOut = false;
    }
    _pinchZoomingOut = intendedZoomOut;
    final pagePoint = (_baseCenter - _baseOffset) / (_fitScale * _baseZoom);
    setState(() {
      _zoom = nextZoom;
      final nextScale = _fitScale * _zoom;
      var nextOffset = center - pagePoint * nextScale;
      if (zoomingOut) {
        nextOffset = _pagedOffsetForZoomOut(nextOffset, nextZoom);
      }
      _offset = nextOffset;
      if (_isInfinite) {
        _lastScale = nextScale;
        _offset = _clampInfiniteOffset(_offset, nextScale);
      }
    });
  }

  void _cancelActiveGesture() {
    if (_pageTurnPending) {
      _pageTurnPending = false;
      widget.pageTurnController?.cancel();
    }
    if (_drawing) {
      setState(() {
        _drawing = false;
        _points.clear();
        _pressures.clear();
      });
    }
    if (widget.tool == 'eraser' && _eraseLast != null) {
      _eraseLast = null;
      widget.onEraseEnd();
    }
    if (_selecting) {
      _resetSelectionGesture();
    }
  }

  bool _beginSelectionTransform(Offset point) {
    final bounds = widget.selectionBounds;
    if (bounds == null) return false;
    final handle = _hitHandle(point, bounds);
    if (handle >= 0) {
      setState(() {
        _selecting = true;
        _selectGesture = 'scale';
        _scaleHandle = handle;
        _scaleStartBounds = bounds;
      });
      return true;
    }
    final tolerance = 8 / _lastScale;
    if (bounds.inflate(tolerance).contains(point)) {
      setState(() {
        _selecting = true;
        _selectGesture = 'move';
        _selectStart = point;
      });
      return true;
    }
    return false;
  }

  /// Pointer tool: taps select a single object; dragging an existing selection
  /// moves it or its corner handles. Blank drags do not start a lasso.
  void _pointerDown(Offset point) {
    _beginSelectionTransform(point);
  }

  void _selectDown(Offset point) {
    if (_beginSelectionTransform(point)) return;
    setState(() {
      _selecting = true;
      _selectGesture = 'lasso';
      _selectStart = point;
      _lasso
        ..clear()
        ..add(point);
    });
  }

  void _selectMove(Offset point, double scale) {
    if (!_selecting) return;
    if (_selectGesture == 'move') {
      final start = _selectStart;
      if (start == null) return;
      widget.onSelectionMove(point - start);
      return;
    }
    if (_selectGesture == 'scale') {
      final startBounds = _scaleStartBounds;
      if (startBounds == null) return;
      final bounds = _resizedBounds(startBounds, _scaleHandle, point);
      widget.onSelectionScale(bounds);
      return;
    }
    if (_selectGesture == 'lasso') {
      if (_lasso.isEmpty || (point - _lasso.last).distance > 1.5 / scale) {
        setState(() => _lasso.add(point));
      }
    }
  }

  void _selectUp(Offset point, double scale) {
    if (!_selecting) return;
    if (_selectGesture == 'lasso') {
      if (_lasso.isEmpty || (point - _lasso.last).distance > 1.5 / scale) {
        _lasso.add(point);
      }
      final start = _selectStart;
      if (start == null) {
        _resetSelectionGesture();
        return;
      }
      final polygon = widget.lassoRect
          ? _rectanglePolygon(start, point)
          : List<Offset>.from(_lasso);
      if (polygon.length >= 3) {
        widget.onSelection(polygon, widget.lassoRect);
      }
    } else {
      widget.onSelectionGestureEnd();
    }
    _resetSelectionGesture();
  }

  void _resetSelectionGesture() {
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selectGesture = '';
      _selectStart = null;
      _scaleHandle = -1;
      _scaleStartBounds = null;
      _lasso.clear();
    });
  }

  List<Offset> _rectanglePolygon(Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    return [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
  }

  int _hitHandle(Offset point, Rect bounds) {
    final corners = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
    final threshold = 14 / _lastScale;
    for (var i = 0; i < corners.length; i++) {
      if ((point - corners[i]).distance <= threshold) return i;
    }
    return -1;
  }

  Rect _resizedBounds(Rect start, int handle, Offset point) {
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;
    switch (handle) {
      case 0:
        left = point.dx;
        top = point.dy;
        break;
      case 1:
        right = point.dx;
        top = point.dy;
        break;
      case 2:
        right = point.dx;
        bottom = point.dy;
        break;
      case 3:
        left = point.dx;
        bottom = point.dy;
        break;
    }
    const minimum = 16.0;
    if ((right - left).abs() < minimum) {
      if (handle == 0 || handle == 3) {
        left = right - minimum;
      } else {
        right = left + minimum;
      }
    }
    if ((bottom - top).abs() < minimum) {
      if (handle == 0 || handle == 1) {
        top = bottom - minimum;
      } else {
        bottom = top + minimum;
      }
    }
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  void _cancel(int pointer) {
    _touches.remove(pointer);
    if (_pageTurnPending) {
      final turn = widget.pageTurnController;
      _pageTurnPending = false;
      if (turn != null) turn.cancel();
      return;
    }
    if (_viewGesture) {
      if (_touches.length < 2) {
        _viewGesture = false;
        _touches.clear();
      }
      return;
    }
    if (_panning) {
      setState(() => _panning = false);
      _panLast = null;
      return;
    }
    if (widget.tool == 'eraser') {
      _eraseLast = null;
      widget.onEraseEnd();
    }
    if (widget.tool == 'pointer' || widget.tool == 'select') {
      _resetSelectionGesture();
    }
    setState(() {
      _drawing = false;
      _points.clear();
      _pressures.clear();
    });
  }

  double _pressure(PointerEvent event) {
    final pressure = event.pressure;
    if (pressure.isNaN || pressure <= 0) return 1.0;
    return pressure.clamp(0.05, 1.0);
  }

  void _onTapUp(TapUpDetails details) {
    final point = _isInfinite
        ? _toPage(details.localPosition)
        : details.localPosition / _lastScale;
    final layers = (widget.page['layers'] as List? ?? const []);
    for (final layer in layers.reversed) {
      final map = layer as Map;
      if (map['visible'] == false || map['locked'] == true) continue;
      final elements = (map['elements'] as List? ?? const []);
      for (final element in elements.reversed) {
        final e = Map<String, dynamic>.from(element as Map);
        final rect = _elementRect(e);
        if (rect.contains(point)) {
          widget.onElementTap(e);
          return;
        }
      }
    }
    final bounds = widget.selectionBounds;
    if (bounds != null && _hitHandle(point, bounds) >= 0) {
      return;
    }
    widget.onSelectionCleared?.call();
  }

  Rect _elementRect(Map<String, dynamic> element) {
    if (element['type'] == 'stroke') {
      final points = element['points'] as List? ?? const [];
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final p in points) {
        final list = p as List;
        final x = (list[0] as num).toDouble();
        final y = (list[1] as num).toDouble();
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
      if (!minX.isFinite) return Rect.zero;
      return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8);
    }
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final w = (element['w'] as num?)?.toDouble() ?? 100;
    final h = (element['h'] as num?)?.toDouble() ?? 60;
    return Rect.fromLTWH(x, y, w, h);
  }
}

/// Paints the paper base and its ruled/grid/dotted texture in page points.
void paintPagePaper(
  Canvas canvas,
  Map<String, dynamic> document,
  Map<String, dynamic> page,
  Rect rect,
) {
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFCF5));
  final paper = document['paper'] as Map? ?? const {};
  final background =
      page['background'] as String? ??
      paper['background'] as String? ??
      'blank';
  final linePaint = Paint()
    ..color = const Color(0xFFB9CEDB).withValues(alpha: 0.42)
    ..strokeWidth = 0.7;
  if (background == 'ruled') {
    for (double y = 32; y < rect.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), linePaint);
    }
  } else if (background == 'grid') {
    for (double y = 24; y < rect.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), linePaint);
    }
    for (double x = 24; x < rect.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, rect.height), linePaint);
    }
  } else if (background == 'dotted') {
    final dot = Paint()
      ..color = const Color(0xFFB9CEDB).withValues(alpha: 0.55);
    for (double y = 24; y < rect.height; y += 24) {
      for (double x = 24; x < rect.width; x += 24) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }
}

/// Paints the read-only book page background: paper texture followed by a
/// vector page when available, otherwise the imported PNG snapshot.
void paintBookPageBackground(
  Canvas canvas,
  Map<String, dynamic> document,
  Map<String, dynamic> page,
  Rect pageRect,
  Map<String, ui.Image> images,
  Map<String, BookVectorPage> vectors,
) {
  paintPagePaper(canvas, document, page, pageRect);
  final vector = vectors[page['id']];
  if (vector != null) {
    paintBookVector(canvas, pageRect, vector);
    return;
  }
  final sourceAsset = page['sourceAssetId'] as String?;
  final image = sourceAsset == null ? null : images[sourceAsset];
  if (image != null) {
    paintImage(
      canvas: canvas,
      rect: pageRect,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Background layer for a paged/book canvas. It sits behind annotations in its
/// own RepaintBoundary and is the only place the page snapshot/vector is drawn.
class BookBackgroundPainter extends CustomPainter {
  BookBackgroundPainter({
    required this.document,
    required this.page,
    required this.scale,
    required this.images,
    required this.vectors,
  }) : imageCount = images.length,
       vectorCount = vectors.length,
       backgroundImage = images[page['sourceAssetId']],
       backgroundVector = vectors[page['id']];

  final Map<String, dynamic> document;
  final Map<String, dynamic> page;
  final double scale;
  final Map<String, ui.Image> images;
  final Map<String, BookVectorPage> vectors;

  /// Captured at construction because the editor mutates the source maps in
  /// place; comparing the map references alone cannot detect a late PNG/SVG.
  final int imageCount;
  final int vectorCount;
  final ui.Image? backgroundImage;
  final BookVectorPage? backgroundVector;

  @override
  void paint(Canvas canvas, Size size) {
    final pageWidth = (page['width'] as num?)?.toDouble() ?? 595.276;
    final pageHeight = (page['height'] as num?)?.toDouble() ?? 841.89;
    canvas.save();
    canvas.scale(scale);
    final pageRect = Rect.fromLTWH(0, 0, pageWidth, pageHeight);
    canvas.clipRect(pageRect);
    paintBookPageBackground(canvas, document, page, pageRect, images, vectors);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BookBackgroundPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.document != document ||
        oldDelegate.page != page ||
        oldDelegate.imageCount != imageCount ||
        oldDelegate.backgroundImage != backgroundImage ||
        oldDelegate.vectorCount != vectorCount ||
        oldDelegate.backgroundVector != backgroundVector;
  }
}

class MeowoCanvasPainter extends CustomPainter {
  MeowoCanvasPainter({
    required this.document,
    required this.page,
    required this.scale,
    required this.images,
    this.vectors = const <String, BookVectorPage>{},
    this.paintBackground = true,
    required this.inProgress,
    required this.inProgressPressures,
    required this.inProgressColor,
    required this.inProgressWidth,
    required this.inProgressHighlighter,
    this.viewOffset = Offset.zero,
    this.selectedIds = const <String>{},
    this.selectionBounds,
    this.lassoPoints = const <Offset>[],
    this.lassoRect = false,
  });

  final Map<String, dynamic> document;
  final Map<String, dynamic> page;
  final double scale;

  /// Screen-space origin used by infinite canvases. Paged canvases ignore it
  /// because their CustomPaint is already positioned at the paper origin.
  final Offset viewOffset;
  final Map<String, ui.Image> images;
  final Map<String, BookVectorPage> vectors;

  /// Paged views paint the read-only book background in a separate
  /// [BookBackgroundPainter] so ink strokes do not replay it. Export and
  /// thumbnail rendering keep it in this painter.
  final bool paintBackground;
  final List<Offset> inProgress;
  final List<double> inProgressPressures;
  final Color inProgressColor;
  final double inProgressWidth;
  final bool inProgressHighlighter;
  final Set<String> selectedIds;
  final Rect? selectionBounds;
  final List<Offset> lassoPoints;
  final bool lassoRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (document['kind'] == 'infinite') {
      _paintInfinite(canvas, size);
      return;
    }
    final pageWidth = (page['width'] as num?)?.toDouble() ?? 595.276;
    final pageHeight = (page['height'] as num?)?.toDouble() ?? 841.89;
    canvas.save();
    canvas.scale(scale);
    final pageRect = Rect.fromLTWH(0, 0, pageWidth, pageHeight);
    canvas.clipRect(pageRect);
    if (paintBackground) {
      paintBookPageBackground(
        canvas,
        document,
        page,
        pageRect,
        images,
        vectors,
      );
    }
    _paintBodyAndLayers(canvas);
    _paintInProgress(canvas);
    _paintSelection(canvas);
    canvas.restore();
  }

  void _paintInfinite(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintInfinitePaper(canvas, size);
    canvas.save();
    canvas.translate(viewOffset.dx, viewOffset.dy);
    canvas.scale(scale);
    final visibleWorld = Rect.fromLTWH(
      -viewOffset.dx / scale,
      -viewOffset.dy / scale,
      size.width / scale,
      size.height / scale,
    ).inflate(64 / scale);
    _paintBodyAndLayers(canvas, visibleWorld: visibleWorld);
    _paintInProgress(canvas);
    _paintSelection(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _paintBodyAndLayers(Canvas canvas, {Rect? visibleWorld}) {
    final body = page['body'];
    // Infinite documents render text boxes only. Legacy body data is kept in
    // the document but must not appear on the canvas.
    if (document['kind'] != 'infinite' && body is Map) {
      final element = Map<String, dynamic>.from(body);
      if (visibleWorld == null ||
          _isElementVisible(element, visibleWorld, isBody: true)) {
        _paintTextElement(canvas, element, isBody: true);
      }
    }
    final layers = page['layers'] as List? ?? const [];
    for (final layerValue in layers) {
      final layer = layerValue as Map;
      if (layer['visible'] == false) continue;
      final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;
      if (opacity <= 0.01) continue;
      for (final value in layer['elements'] as List? ?? const []) {
        final element = Map<String, dynamic>.from(value as Map);
        if (visibleWorld != null &&
            !_isElementVisible(element, visibleWorld, isBody: false)) {
          continue;
        }
        _paintElement(canvas, element, opacity);
      }
    }
  }

  bool _isElementVisible(
    Map<String, dynamic> element,
    Rect visibleWorld, {
    required bool isBody,
  }) {
    final bounds = elementBounds(element);
    if (bounds.isEmpty) {
      return visibleWorld.contains(bounds.topLeft);
    }
    // Image rotation and text overflow can extend beyond the stored box.
    final margin = math.max(bounds.width, bounds.height) + 24 / scale;
    return bounds.inflate(margin).overlaps(visibleWorld);
  }

  void _paintInProgress(Canvas canvas) {
    if (inProgress.isEmpty) return;
    _paintStroke(
      canvas,
      inProgress,
      inProgressPressures,
      inProgressColor,
      inProgressWidth,
      inProgressHighlighter,
      1.0,
      pressureCurveFor(document, inProgressHighlighter),
    );
  }

  void _paintSelection(Canvas canvas) {
    final accent = const Color(0xFFB4692A);
    if (lassoPoints.length >= 2) {
      final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      if (lassoRect) {
        final rect = Rect.fromPoints(lassoPoints.first, lassoPoints.last);
        path
          ..reset()
          ..addRect(rect);
      } else {
        for (final point in lassoPoints.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.08));
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale,
      );
    }
    final bounds = selectionBounds;
    if (bounds == null) return;
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    canvas.drawRect(bounds, paint);
    final handleSize = 9 / scale;
    final fill = Paint()..color = const Color(0xFFFFFCF5);
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ]) {
      final rect = Rect.fromCenter(
        center: corner,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, paint);
    }
  }

  void _paintInfinitePaper(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFCF5),
    );
    final paper = document['paper'] as Map? ?? const {};
    final background =
        page['background'] as String? ??
        paper['background'] as String? ??
        'blank';
    if (background == 'blank') return;

    final spacing = background == 'ruled' ? 28.0 : 24.0;
    final step = spacing * scale;
    // At very low zoom the pattern would become visual noise; fade it out.
    if (step < 6) return;
    final fade = ((step - 6) / 10).clamp(0.0, 1.0);
    final linePaint = Paint()
      ..color = const Color(0xFFB9CEDB).withValues(alpha: 0.42 * fade)
      ..strokeWidth = 0.7;
    final startX = _positiveModulo(viewOffset.dx, step);
    final startY = _positiveModulo(viewOffset.dy, step);

    if (background == 'ruled') {
      for (double y = startY; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
      return;
    }
    if (background == 'grid') {
      for (double y = startY; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
      for (double x = startX; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      }
      return;
    }
    if (background == 'dotted') {
      final dot = Paint()
        ..color = const Color(0xFFB9CEDB).withValues(alpha: 0.55 * fade);
      for (double y = startY; y <= size.height; y += step) {
        for (double x = startX; x <= size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 0.9, dot);
        }
      }
    }
  }

  double _positiveModulo(double value, double modulus) {
    final result = value % modulus;
    return result < 0 ? result + modulus : result;
  }

  void _paintElement(
    Canvas canvas,
    Map<String, dynamic> element,
    double opacity,
  ) {
    switch (element['type']) {
      case 'stroke':
        final raw = element['points'] as List? ?? const [];
        final points = <Offset>[];
        final pressures = <double>[];
        for (final p in raw) {
          final list = p as List;
          points.add(
            Offset((list[0] as num).toDouble(), (list[1] as num).toDouble()),
          );
          pressures.add(list.length > 2 ? (list[2] as num).toDouble() : 1.0);
        }
        _paintStroke(
          canvas,
          points,
          pressures,
          _hexColor(element['color'] as String? ?? '#222222'),
          (element['width'] as num?)?.toDouble() ?? 2,
          element['highlighter'] == true,
          opacity * ((element['opacity'] as num?)?.toDouble() ?? 1.0),
          pressureCurveFor(document, element['highlighter'] == true),
        );
      case 'text':
        _paintTextElement(canvas, element);
      case 'image':
        _paintImageElement(canvas, element, opacity);
      case 'attachment':
        _paintAttachment(canvas, element, opacity);
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    List<double> pressures,
    Color color,
    double width,
    bool highlighter,
    double opacity,
    List<Offset> curve,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = highlighter
          ? color.withValues(alpha: 0.32 * opacity)
          : color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = highlighter ? BlendMode.multiply : BlendMode.srcOver;
    if (points.length == 1) {
      final raw = pressures.isNotEmpty ? pressures.first : 1.0;
      final pressure = applyPressureCurve(raw, curve);
      canvas.drawCircle(
        points.first,
        width * (0.45 + pressure * 0.85) * 0.5,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    for (var i = 1; i < points.length; i++) {
      final p = pressures.length > i ? pressures[i] : 1.0;
      final start = pressures.length > i - 1 ? pressures[i - 1] : p;
      final pressure =
          ((applyPressureCurve(p, curve) + applyPressureCurve(start, curve)) /
                  2)
              .clamp(0.05, 1.0);
      paint.strokeWidth = width * (0.45 + pressure * 0.85);
      canvas.drawLine(points[i - 1], points[i], paint);
    }
  }

  void _paintTextElement(
    Canvas canvas,
    Map<String, dynamic> element, {
    bool isBody = false,
  }) {
    final x = (element['x'] as num?)?.toDouble() ?? (isBody ? 48 : 40);
    final y = (element['y'] as num?)?.toDouble() ?? (isBody ? 48 : 40);
    final w =
        (element['w'] as num?)?.toDouble() ??
        (((page['width'] as num?)?.toDouble() ?? 595) - x * 2);
    final h =
        (element['h'] as num?)?.toDouble() ??
        (((page['height'] as num?)?.toDouble() ?? 842) - y * 2);
    final markdown = element['markdown'] as String? ?? '';
    final fontSize = (element['fontSize'] as num?)?.toDouble() ?? 16;
    final lineHeight = (element['lineHeight'] as num?)?.toDouble() ?? 1.5;
    final color = _hexColor(element['color'] as String? ?? '#222222');
    final text = _plainText(markdown);
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? ' ' : text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: lineHeight,
          fontFamily: 'Noto Sans CJK SC',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: w);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x, y, w, h));
    painter.paint(canvas, Offset(x, y));
    canvas.restore();
    if (painter.height > h + 0.5) {
      final marker = Paint()..color = const Color(0xFFB4692A);
      canvas.drawCircle(Offset(x + w - 5, y + h - 5), 3.5, marker);
    }
  }

  void _paintImageElement(
    Canvas canvas,
    Map<String, dynamic> element,
    double opacity,
  ) {
    final id = element['assetId'] as String?;
    final image = id == null ? null : images[id];
    if (image == null) {
      _paintMissing(canvas, element, '图片');
      return;
    }
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final w = (element['w'] as num?)?.toDouble() ?? image.width.toDouble();
    final h = (element['h'] as num?)?.toDouble() ?? image.height.toDouble();
    paintImageElementContent(
      canvas,
      Rect.fromLTWH(x, y, w, h),
      image,
      crop: normalizeImageCrop(element),
      rotation: normalizeImageRotation(element['rotation']),
      flipH: imageFlag(element, 'flipH'),
      flipV: imageFlag(element, 'flipV'),
      opacity: opacity * ((element['opacity'] as num?)?.toDouble() ?? 1.0),
    );
  }

  void _paintAttachment(
    Canvas canvas,
    Map<String, dynamic> element,
    double opacity,
  ) {
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final w = (element['w'] as num?)?.toDouble() ?? 230;
    final h = (element['h'] as num?)?.toDouble() ?? 54;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFFF1E6D6).withValues(alpha: opacity),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFB9A58C).withValues(alpha: opacity),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: '附件  ${element['name'] ?? ''}',
        style: const TextStyle(color: Color(0xFF5D4A35), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: w - 24);
    painter.paint(canvas, Offset(x + 12, y + (h - painter.height) / 2));
  }

  void _paintMissing(
    Canvas canvas,
    Map<String, dynamic> element,
    String label,
  ) {
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final w = (element['w'] as num?)?.toDouble() ?? 220;
    final h = (element['h'] as num?)?.toDouble() ?? 120;
    final rect = Rect.fromLTWH(x, y, w, h);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF0E8DC));
    final painter = TextPainter(
      text: TextSpan(
        text: '$label缺失',
        style: const TextStyle(color: Color(0xFF8D7761), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static String _plainText(String markdown) {
    var text = markdown;
    text = text.replaceAllMapped(
      RegExp(r'^#{1,6}\s*', multiLine: true),
      (_) => '',
    );
    text = text.replaceAllMapped(RegExp(r'```[^\n]*\n?'), (_) => '');
    text = text.replaceAll('**', '').replaceAll('__', '').replaceAll('~~', '');
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m[1] ?? '',
    );
    return text;
  }

  static Color _hexColor(String value) {
    final cleaned = value.replaceAll('#', '');
    final parsed = int.tryParse(cleaned, radix: 16) ?? 0x222222;
    if (cleaned.length == 6) return Color(0xFF000000 | parsed);
    if (cleaned.length == 8) return Color(parsed);
    return const Color(0xFF222222);
  }

  @override
  bool shouldRepaint(covariant MeowoCanvasPainter oldDelegate) {
    // The alpha stores document/page payloads as mutable JSON maps. Their
    // identity does not change when an element is added or moved, so repaint
    // whenever the widget rebuilds to avoid stale ink/selection overlays.
    return true;
  }
}

/// Renders an infinite-canvas world region (normally cropped to content).
///
/// The output pixel dimensions are capped so a very large content region does
/// not exhaust memory. The region is scaled down uniformly instead of being
/// cropped, preserving all content.
Future<Uint8List> renderInfiniteCanvasPng({
  required Map<String, dynamic> document,
  required Map<String, dynamic> page,
  required Map<String, ui.Image> images,
  required Rect region,
  double pixelRatio = 2.0,
  double maxDimension = 4096,
  double maxPixels = 12000000,
}) async {
  if (region.width <= 0 || region.height <= 0) {
    throw ArgumentError('无极画布导出区域必须为正数');
  }
  var ratio = pixelRatio;
  ratio = math.min(ratio, maxDimension / region.width);
  ratio = math.min(ratio, maxDimension / region.height);
  ratio = math.min(
    ratio,
    math.sqrt(maxPixels / (region.width * region.height)),
  );
  ratio = math.max(0.000001, ratio);
  final pixelWidth = math.max(1, (region.width * ratio).round());
  final pixelHeight = math.max(1, (region.height * ratio).round());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  MeowoCanvasPainter(
    document: document,
    page: page,
    scale: 1,
    viewOffset: -region.topLeft,
    images: images,
    inProgress: const <Offset>[],
    inProgressPressures: const <double>[],
    inProgressColor: const Color(0xFF222222),
    inProgressWidth: 1,
    inProgressHighlighter: false,
  ).paint(canvas, region.size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelWidth, pixelHeight);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('画布渲染失败');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> renderPagePng({
  required Map<String, dynamic> document,
  required Map<String, dynamic> page,
  required Map<String, ui.Image> images,
  Map<String, BookVectorPage> vectors = const <String, BookVectorPage>{},
  double pixelRatio = 2.0,
}) async {
  final width = (page['width'] as num?)?.toDouble() ?? 595.276;
  final height = (page['height'] as num?)?.toDouble() ?? 841.89;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  MeowoCanvasPainter(
    document: document,
    page: page,
    scale: 1,
    images: images,
    vectors: vectors,
    inProgress: const <Offset>[],
    inProgressPressures: const <double>[],
    inProgressColor: const Color(0xFF222222),
    inProgressWidth: 1,
    inProgressHighlighter: false,
  ).paint(canvas, Size(width, height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * pixelRatio).round(),
    (height * pixelRatio).round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('页面渲染失败');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
