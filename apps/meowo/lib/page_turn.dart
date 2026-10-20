import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'book_vector.dart';
import 'canvas_view.dart';

/// Defaults for album-style page turning.
///
/// The drag must travel at least 25% of the viewport width, with a 72 logical
/// pixel floor, unless it is released as a fling. A fling counts when it is at
/// least 700 logical pixels/second and has travelled at least 40 pixels.
/// Overscrolling at the first/last page is damped to at most 12% of the
/// viewport and springs back without changing pages.
const double kPageTurnDistanceFraction = 0.25;
const double kPageTurnMinDistance = 72.0;
const double kPageTurnFlingVelocity = 700.0;
const double kPageTurnFlingMinDistance = 40.0;
const double kPageTurnAxisSlop = 8.0;
const double kPageTurnAxisDominance = 1.15;
const double kPageTurnEdgeResistance = 0.22;
const double kPageTurnMaxEdgeProgress = 0.12;
const Duration kPageTurnSnapDuration = Duration(milliseconds: 260);
const Duration kPageTurnCommitDuration = Duration(milliseconds: 240);
const Duration kPageTurnRestoreDuration = Duration(milliseconds: 300);

enum PageTurnPhase { idle, pending, dragging, settling, committing }

/// Result of feeding a pointer move to a [PageTurnController].
enum PageTurnDrag { none, horizontal, vertical }

class _DragSample {
  const _DragSample(this.dx, this.time);

  final double dx;
  final Duration time;
}

/// Owns the drag/snap state for album-style paged navigation.
///
/// [CanvasView] feeds raw pointer events here only while the hand tool is
/// active and the page is at fit zoom. The visual presentation (translating
/// the live page and revealing neighbours) lives in [PageTurnLayer].
class PageTurnController extends ChangeNotifier {
  PageTurnController({
    required TickerProvider vsync,
    required this.onPageRequested,
  }) : _animation = AnimationController(vsync: vsync) {
    _animation.addListener(_onAnimationTick);
    _animation.addStatusListener(_onAnimationStatus);
  }

  /// Called with -1 for the previous page and +1 for the next page.
  Future<void> Function(int delta) onPageRequested;

  final AnimationController _animation;
  double _animationFrom = 0;
  double _animationTo = 0;
  Curve _animationCurve = Curves.easeOutCubic;
  VoidCallback? _animationDone;

  /// Set by [PageTurnLayer] on every build.
  bool enabled = true;
  bool hasPrevious = false;
  bool hasNext = false;
  double viewportWidth = 1;
  bool reducedMotion = false;

  /// Set by [CanvasView] on every build: paged/book, hand tool, fit zoom.
  bool canStart = false;

  PageTurnPhase _phase = PageTurnPhase.idle;
  double _progress = 0;
  int _pointer = -1;
  Offset _start = Offset.zero;
  final List<_DragSample> _samples = [];
  int? _pendingCommit;
  bool _disposed = false;

  PageTurnPhase get phase => _phase;
  double get progress => _progress;
  bool get isDragging => _phase == PageTurnPhase.dragging;
  bool get busy =>
      _phase == PageTurnPhase.settling || _phase == PageTurnPhase.committing;

  /// True while the current page is dragged or snapping and should ignore
  /// other hand-tool pointer gestures.
  bool get isActive => _phase != PageTurnPhase.idle;

  /// Updates availability without notifying listeners; safe during build.
  ///
  /// [PageTurnLayer] calls this each time it lays out so the controller knows
  /// whether the neighbouring page exists and how wide the viewport is.
  void configure({
    required bool enabled,
    required bool hasPrevious,
    required bool hasNext,
    required double viewportWidth,
    required bool reducedMotion,
  }) {
    this.enabled = enabled;
    this.hasPrevious = hasPrevious;
    this.hasNext = hasNext;
    this.viewportWidth = math.max(1.0, viewportWidth);
    this.reducedMotion = reducedMotion;
  }

  /// Starts the pending phase. No page movement happens until the pointer has
  /// moved far enough to lock the horizontal axis.
  bool begin(Offset position, Duration timeStamp, {required int pointer}) {
    if (!enabled || !canStart || _phase != PageTurnPhase.idle) return false;
    _phase = PageTurnPhase.pending;
    _pointer = pointer;
    _start = position;
    _progress = 0;
    _pendingCommit = null;
    _samples
      ..clear()
      ..add(_DragSample(0, timeStamp));
    return true;
  }

  /// Feeds a pointer move. Returns [PageTurnDrag.vertical] when the gesture
  /// should fall back to normal hand-tool panning.
  PageTurnDrag update(
    Offset position,
    Duration timeStamp, {
    required int pointer,
  }) {
    if (pointer != _pointer) return PageTurnDrag.none;
    final delta = position - _start;
    if (_phase == PageTurnPhase.pending) {
      if (delta.distance < kPageTurnAxisSlop) return PageTurnDrag.none;
      final horizontal = delta.dx.abs();
      final vertical = delta.dy.abs();
      if (horizontal >= vertical * kPageTurnAxisDominance) {
        _phase = PageTurnPhase.dragging;
      } else if (vertical >= horizontal * kPageTurnAxisDominance) {
        _resetState();
        return PageTurnDrag.vertical;
      } else {
        return PageTurnDrag.none;
      }
    }
    if (_phase != PageTurnPhase.dragging) return PageTurnDrag.none;
    _recordSample(delta.dx, timeStamp);
    _progress = _pageProgressFor(delta.dx);
    _notify();
    return PageTurnDrag.horizontal;
  }

  /// Ends the gesture, snapping to the adjacent page or springing back.
  void end(Offset position, Duration timeStamp, {required int pointer}) {
    if (pointer != _pointer) return;
    if (_phase == PageTurnPhase.pending) {
      _resetState();
      return;
    }
    if (_phase != PageTurnPhase.dragging) return;

    final dx = position.dx - _start.dx;
    _recordSample(dx, timeStamp);
    final distance = dx.abs();
    final velocity = _horizontalVelocity;
    final threshold = math.max(
      kPageTurnMinDistance,
      viewportWidth * kPageTurnDistanceFraction,
    );
    final passedDistance = distance >= threshold;
    final isFling =
        velocity.abs() >= kPageTurnFlingVelocity &&
        distance >= kPageTurnFlingMinDistance;
    final direction = dx < 0 ? 1 : -1;
    final flingMatchesDirection =
        (direction == 1 && velocity < 0) || (direction == -1 && velocity > 0);
    final targetAvailable = direction == 1 ? hasNext : hasPrevious;
    if ((passedDistance || (isFling && flingMatchesDirection)) &&
        targetAvailable) {
      _commit(direction);
    } else {
      _settleTo(0, kPageTurnSnapDuration);
    }
  }

  /// Cancels the in-flight gesture. Used when a second finger arrives, the
  /// pointer is cancelled, or the widget goes away.
  void cancel({bool animate = true}) {
    _pointer = -1;
    _samples.clear();
    _pendingCommit = null;
    if (_phase == PageTurnPhase.idle) return;
    if (animate && _progress != 0) {
      _settleTo(0, kPageTurnRestoreDuration);
      return;
    }
    _resetState();
  }

  /// Called by [PageTurnLayer] when the document page actually changes. The
  /// parent is already rebuilding, so this is deliberately silent.
  void handlePageChanged() {
    _animation.stop();
    _animationDone = null;
    _phase = PageTurnPhase.idle;
    _progress = 0;
    _pointer = -1;
    _pendingCommit = null;
    _samples.clear();
  }

  void _commit(int delta) {
    final target = delta > 0 ? -1.0 : 1.0;
    _pendingCommit = delta;
    _settleTo(target, kPageTurnCommitDuration, phase: PageTurnPhase.committing);
  }

  void _settleTo(
    double target,
    Duration duration, {
    PageTurnPhase phase = PageTurnPhase.settling,
  }) {
    _phase = phase;
    _animationFrom = _progress;
    _animationTo = target;
    _animationCurve = Curves.easeOutCubic;
    _animationDone = target == 0 ? _finishRestore : _finishCommit;
    if (reducedMotion) {
      _progress = target;
      _notify();
      final done = _animationDone;
      _animationDone = null;
      done?.call();
      return;
    }
    _animation
      ..duration = duration
      ..value = 0
      ..forward();
  }

  void _onAnimationTick() {
    if (_phase == PageTurnPhase.idle) return;
    final t = _animationCurve.transform(_animation.value.clamp(0.0, 1.0));
    _progress = _animationFrom + (_animationTo - _animationFrom) * t;
    _notify();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final done = _animationDone;
    _animationDone = null;
    done?.call();
  }

  void _finishRestore() {
    _resetState();
  }

  Future<void> _finishCommit() async {
    final delta = _pendingCommit;
    _pendingCommit = null;
    if (delta == null) {
      _resetState();
      return;
    }
    try {
      await onPageRequested(delta);
    } finally {
      // If [handlePageChanged] ran, the layer already reset silently. Only
      // clear here when the request did not change the page (for example a
      // stale bounds check), so the preview cannot stay on screen forever.
      if (!_disposed && _phase == PageTurnPhase.committing) {
        _resetState();
      }
    }
  }

  void _resetState() {
    if (_disposed) return;
    _animation.stop();
    _animationDone = null;
    _phase = PageTurnPhase.idle;
    _progress = 0;
    _pointer = -1;
    _pendingCommit = null;
    _samples.clear();
    _notify();
  }

  double _pageProgressFor(double rawDx) {
    final fraction = rawDx / viewportWidth;
    if (fraction < 0) {
      if (!hasNext) return -_damp(fraction.abs());
      return fraction.clamp(-1.0, 0.0);
    }
    if (!hasPrevious) return _damp(fraction);
    return fraction.clamp(0.0, 1.0);
  }

  double _damp(double value) {
    return math.min(kPageTurnMaxEdgeProgress, value * kPageTurnEdgeResistance);
  }

  void _recordSample(double dx, Duration timeStamp) {
    _samples.add(_DragSample(dx, timeStamp));
    while (_samples.length > 2 &&
        timeStamp - _samples.first.time > const Duration(milliseconds: 120)) {
      _samples.removeAt(0);
    }
  }

  double get _horizontalVelocity {
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final micros = (last.time - first.time).inMicroseconds;
    // Widget tests and some synthetic pointers report a zero timestamp; do
    // not turn that into a near-infinite synthetic fling.
    if (micros < 1000) return 0;
    return (last.dx - first.dx) * 1000000 / micros;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _animation.dispose();
    super.dispose();
  }
}

/// Visual album-style page-turn layer around a paged/book canvas.
///
/// The live [CanvasView] is translated with the finger. Previous and next
/// pages are painted read-only with [MeowoCanvasPainter] in their normal
/// fit-to-window positions, one viewport to either side, and translated by the
/// same amount. This keeps the side-by-side reveal convincing without creating
/// extra interactive canvases or sharing the editor's GlobalKey.
class PageTurnLayer extends StatefulWidget {
  const PageTurnLayer({
    super.key,
    required this.document,
    required this.pages,
    required this.pageIndex,
    required this.images,
    this.vectors = const <String, BookVectorPage>{},
    required this.onPageRequested,
    required this.builder,
    this.enabled = true,
  });

  final Map<String, dynamic> document;
  final List<Map<String, dynamic>> pages;
  final int pageIndex;
  final Map<String, ui.Image> images;
  final Map<String, BookVectorPage> vectors;
  final Future<void> Function(int delta) onPageRequested;
  final Widget Function(BuildContext context, PageTurnController controller)
  builder;
  final bool enabled;

  @override
  State<PageTurnLayer> createState() => _PageTurnLayerState();
}

class _PageTurnLayerState extends State<PageTurnLayer>
    with SingleTickerProviderStateMixin {
  late final PageTurnController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageTurnController(
      vsync: this,
      onPageRequested: widget.onPageRequested,
    );
  }

  @override
  void didUpdateWidget(covariant PageTurnLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.onPageRequested = widget.onPageRequested;
    if (!widget.enabled) {
      _controller.handlePageChanged();
      return;
    }
    final oldId = _pageIdAt(oldWidget, oldWidget.pageIndex);
    final newId = _pageIdAt(widget, widget.pageIndex);
    if (oldWidget.pageIndex != widget.pageIndex || oldId != newId) {
      _controller.handlePageChanged();
    }
  }

  String? _pageIdAt(PageTurnLayer layer, int index) {
    if (index < 0 || index >= layer.pages.length) return null;
    return layer.pages[index]['id'] as String?;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final index = widget.pageIndex
            .clamp(0, math.max(0, widget.pages.length - 1))
            .toInt();
        final hasPrevious = widget.enabled && index > 0;
        final hasNext = widget.enabled && index + 1 < widget.pages.length;
        _controller.configure(
          enabled: widget.enabled,
          hasPrevious: hasPrevious,
          hasNext: hasNext,
          viewportWidth: viewport.width,
          reducedMotion: reduceMotion,
        );
        final child = widget.builder(context, _controller);
        final previews = _buildPreviews(viewport, index);
        return AnimatedBuilder(
          animation: _controller,
          child: child,
          builder: (context, child) {
            final dx = _controller.progress * viewport.width;
            final showing = _controller.progress.abs() > 0.0001;
            return ClipRect(
              child: Stack(
                children: [
                  if (showing)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Transform.translate(
                          key: const ValueKey('page-turn-previews'),
                          offset: Offset(dx, 0),
                          child: previews,
                        ),
                      ),
                    ),
                  Transform.translate(
                    key: const ValueKey('page-turn-current'),
                    offset: Offset(dx, 0),
                    child: child,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreviews(Size viewport, int index) {
    final children = <Widget>[];
    if (index > 0) {
      children.add(
        _preview(
          widget.pages[index - 1],
          viewport,
          slotOffset: -viewport.width,
          key: const ValueKey('page-turn-preview-prev'),
        ),
      );
    }
    if (index + 1 < widget.pages.length) {
      children.add(
        _preview(
          widget.pages[index + 1],
          viewport,
          slotOffset: viewport.width,
          key: const ValueKey('page-turn-preview-next'),
        ),
      );
    }
    return RepaintBoundary(
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  Widget _preview(
    Map<String, dynamic> page,
    Size viewport, {
    required double slotOffset,
    required Key key,
  }) {
    final pageSize = pagedPageSize(widget.document, page);
    final rect = pagedPageRect(viewport, pageSize);
    final scale = rect.width / math.max(1.0, pageSize.width);
    return Positioned(
      key: key,
      left: rect.left + slotOffset,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: RepaintBoundary(
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
            child: CustomPaint(
              size: rect.size,
              painter: MeowoCanvasPainter(
                document: widget.document,
                page: page,
                scale: scale,
                images: widget.images,
                vectors: widget.vectors,
                inProgress: const [],
                inProgressPressures: const [],
                inProgressColor: const Color(0xFF2B2A27),
                inProgressWidth: 1,
                inProgressHighlighter: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
