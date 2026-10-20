import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ink_ops.dart';

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
  });

  final Map<String, dynamic> document;
  final Map<String, dynamic> page;
  final String tool;
  final Color color;
  final double width;
  final String activeLayerId;
  final Map<String, ui.Image> images;
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

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
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

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final width =
        (page['width'] as num?)?.toDouble() ??
        ((widget.document['paper'] as Map?)?['width'] as num?)?.toDouble() ??
        595.276;
    final height =
        (page['height'] as num?)?.toDouble() ??
        ((widget.document['paper'] as Map?)?['height'] as num?)?.toDouble() ??
        841.89;
    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = 36.0;
        final scale = math
            .min(
              (constraints.maxWidth - margin * 2) / width,
              (constraints.maxHeight - margin * 2) / height,
            )
            .clamp(0.05, 4.0);
        _lastScale = scale;
        final canvasSize = Size(width * scale, height * scale);
        return Center(
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
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _onDown(event, scale),
                  onPointerMove: (event) => _onMove(event, scale),
                  onPointerUp: (event) => _onUp(event, scale),
                  onPointerCancel: (event) => _cancel(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.tool == 'select' ? _onTapUp : null,
                    child: CustomPaint(
                      size: canvasSize,
                      painter: MeowoCanvasPainter(
                        document: widget.document,
                        page: widget.page,
                        scale: scale,
                        images: widget.images,
                        inProgress: _points,
                        inProgressPressures: _pressures,
                        inProgressColor: widget.color,
                        inProgressWidth: widget.width,
                        inProgressHighlighter: widget.tool == 'highlighter',
                        selectedIds: widget.selectionIds,
                        selectionBounds: widget.selectionBounds,
                        lassoPoints: _lasso,
                        lassoRect: widget.lassoRect,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _toPage(Offset local, double scale) => local / scale;

  void _onDown(PointerDownEvent event, double scale) {
    final point = _toPage(event.localPosition, scale);
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

  void _onMove(PointerMoveEvent event, double scale) {
    final point = _toPage(event.localPosition, scale);
    if (widget.tool == 'select') {
      _selectMove(point, scale);
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

  void _onUp(PointerUpEvent event, double scale) {
    final point = _toPage(event.localPosition, scale);
    if (widget.tool == 'select') {
      _selectUp(point, scale);
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

  void _selectDown(Offset point) {
    final bounds = widget.selectionBounds;
    if (bounds != null) {
      final handle = _hitHandle(point, bounds);
      if (handle >= 0) {
        setState(() {
          _selecting = true;
          _selectGesture = 'scale';
          _scaleHandle = handle;
          _scaleStartBounds = bounds;
        });
        return;
      }
      final tolerance = 8 / _lastScale;
      if (bounds.inflate(tolerance).contains(point)) {
        setState(() {
          _selecting = true;
          _selectGesture = 'move';
          _selectStart = point;
        });
        return;
      }
    }
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

  void _cancel() {
    if (widget.tool == 'eraser') {
      _eraseLast = null;
      widget.onEraseEnd();
    }
    if (widget.tool == 'select') {
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
    if (widget.selectionIds.isNotEmpty) return;
    final point = details.localPosition / _lastScale;
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

class MeowoCanvasPainter extends CustomPainter {
  MeowoCanvasPainter({
    required this.document,
    required this.page,
    required this.scale,
    required this.images,
    required this.inProgress,
    required this.inProgressPressures,
    required this.inProgressColor,
    required this.inProgressWidth,
    required this.inProgressHighlighter,
    this.selectedIds = const <String>{},
    this.selectionBounds,
    this.lassoPoints = const <Offset>[],
    this.lassoRect = false,
  });

  final Map<String, dynamic> document;
  final Map<String, dynamic> page;
  final double scale;
  final Map<String, ui.Image> images;
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
    final pageWidth = (page['width'] as num?)?.toDouble() ?? 595.276;
    final pageHeight = (page['height'] as num?)?.toDouble() ?? 841.89;
    canvas.save();
    canvas.scale(scale);
    final pageRect = Rect.fromLTWH(0, 0, pageWidth, pageHeight);
    canvas.clipRect(pageRect);
    _paintPaper(canvas, pageRect);
    final sourceAsset = page['sourceAssetId'] as String?;
    if (sourceAsset != null && images[sourceAsset] != null) {
      paintImage(
        canvas: canvas,
        rect: pageRect,
        image: images[sourceAsset]!,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    }
    final body = page['body'];
    if (body is Map) {
      _paintTextElement(canvas, Map<String, dynamic>.from(body), isBody: true);
    }
    final layers = page['layers'] as List? ?? const [];
    for (final layerValue in layers) {
      final layer = layerValue as Map;
      if (layer['visible'] == false) continue;
      final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1.0;
      if (opacity <= 0.01) continue;
      for (final value in layer['elements'] as List? ?? const []) {
        final element = Map<String, dynamic>.from(value as Map);
        _paintElement(canvas, element, opacity);
      }
    }
    if (inProgress.isNotEmpty) {
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
    _paintSelection(canvas);
    canvas.restore();
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

  void _paintPaper(Canvas canvas, Rect rect) {
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
    final rotation = (element['rotation'] as num?)?.toDouble() ?? 0;
    canvas.save();
    if (rotation != 0) {
      final center = Offset(x + w / 2, y + h / 2);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * math.pi / 180);
      canvas.translate(-center.dx, -center.dy);
    }
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(x, y, w, h),
      image: image,
      fit: BoxFit.fill,
      opacity: opacity * ((element['opacity'] as num?)?.toDouble() ?? 1.0),
      filterQuality: FilterQuality.medium,
    );
    canvas.restore();
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

Future<Uint8List> renderPagePng({
  required Map<String, dynamic> document,
  required Map<String, dynamic> page,
  required Map<String, ui.Image> images,
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
