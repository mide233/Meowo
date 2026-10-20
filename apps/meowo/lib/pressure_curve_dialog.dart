import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ink_ops.dart';

Future<List<Offset>?> showPressureCurveDialog(
  BuildContext context, {
  required List<Offset> curve,
  required Color color,
  required String title,
}) {
  return showDialog<List<Offset>>(
    context: context,
    builder: (context) => _PressureCurveDialog(
      initial: normalizePressureCurve(curve),
      color: color,
      title: title,
    ),
  );
}

class _PressureCurveDialog extends StatefulWidget {
  const _PressureCurveDialog({
    required this.initial,
    required this.color,
    required this.title,
  });

  final List<Offset> initial;
  final Color color;
  final String title;

  @override
  State<_PressureCurveDialog> createState() => _PressureCurveDialogState();
}

class _PressureCurveDialogState extends State<_PressureCurveDialog> {
  late List<Offset> _points = List<Offset>.from(widget.initial);
  int _dragging = -1;

  void _reset() {
    setState(() => _points = List<Offset>.from(kDefaultPressureCurve));
  }

  void _update(Offset local, Size size) {
    if (_dragging < 0) return;
    final isEndpoint = _dragging == 0 || _dragging == _points.length - 1;
    final x = isEndpoint
        ? _points[_dragging].dx
        : (_dragging / (_points.length - 1)).clamp(0.0, 1.0);
    final y = (1 - local.dy / size.height).clamp(0.02, 0.98);
    setState(() {
      _points[_dragging] = Offset(x, y);
      _points = normalizePressureCurve(_points);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '横轴为原始压力，纵轴为笔迹宽度。拖动控制点调整响应；端点保持 0 与 1。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1.35,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      final threshold = 28.0;
                      var nearest = -1;
                      var distance = threshold;
                      for (var i = 0; i < _points.length; i++) {
                        final p = _points[i];
                        final dx = p.dx * size.width - details.localPosition.dx;
                        final dy =
                            (1 - p.dy) * size.height - details.localPosition.dy;
                        final d = math.sqrt(dx * dx + dy * dy);
                        if (d < distance) {
                          distance = d;
                          nearest = i;
                        }
                      }
                      _dragging = nearest;
                      if (nearest >= 0) _update(details.localPosition, size);
                    },
                    onPanUpdate: (details) =>
                        _update(details.localPosition, size),
                    onPanEnd: (_) => _dragging = -1,
                    child: CustomPaint(
                      painter: _PressureCurvePainter(
                        points: _points,
                        color: widget.color,
                        grid: scheme.outlineVariant,
                        background: scheme.surfaceContainerLowest,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                Text(
                  '0.00 → ${_points.last.dy.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  '线性参考：y = x',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('重置')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, normalizePressureCurve(_points)),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _PressureCurvePainter extends CustomPainter {
  const _PressureCurvePainter({
    required this.points,
    required this.color,
    required this.grid,
    required this.background,
  });

  final List<Offset> points;
  final Color color;
  final Color grid;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final diagonal = Paint()
      ..color = grid.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagonal);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = Offset(
        points[i].dx * size.width,
        (1 - points[i].dy) * size.height,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      final center = Offset(
        point.dx * size.width,
        (1 - point.dy) * size.height,
      );
      canvas.drawCircle(center, 5.5, Paint()..color = background);
      canvas.drawCircle(
        center,
        5.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PressureCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.background != background;
  }
}
