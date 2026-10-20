import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'image_ops.dart';

class ImageEditResult {
  const ImageEditResult({
    required this.crop,
    required this.rotation,
    required this.flipH,
    required this.flipV,
  });

  final Rect crop;
  final int rotation;
  final bool flipH;
  final bool flipV;
}

Future<ImageEditResult?> showImageEditorDialog(
  BuildContext context, {
  required ui.Image image,
  required Map<String, dynamic> element,
}) {
  return showDialog<ImageEditResult>(
    context: context,
    builder: (context) => _ImageEditDialog(image: image, element: element),
  );
}

class _ImageEditDialog extends StatefulWidget {
  const _ImageEditDialog({required this.image, required this.element});

  final ui.Image image;
  final Map<String, dynamic> element;

  @override
  State<_ImageEditDialog> createState() => _ImageEditDialogState();
}

class _ImageEditDialogState extends State<_ImageEditDialog> {
  late double _left;
  late double _top;
  late double _right;
  late double _bottom;
  late int _rotation;
  late bool _flipH;
  late bool _flipV;

  @override
  void initState() {
    super.initState();
    final crop = normalizeImageCrop(widget.element);
    _left = crop.left;
    _top = crop.top;
    _right = crop.right;
    _bottom = crop.bottom;
    _rotation = normalizeImageRotation(widget.element['rotation']);
    _flipH = imageFlag(widget.element, 'flipH');
    _flipV = imageFlag(widget.element, 'flipV');
  }

  void _reset() {
    setState(() {
      _left = 0;
      _top = 0;
      _right = 1;
      _bottom = 1;
      _rotation = 0;
      _flipH = false;
      _flipV = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final crop = Rect.fromLTRB(_left, _top, _right, _bottom);
    return AlertDialog(
      title: const Text('编辑图片'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: _ImagePreviewPainter(
                    image: widget.image,
                    crop: crop,
                    rotation: _rotation,
                    flipH: _flipH,
                    flipV: _flipV,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '裁剪 · 旋转 $_rotation° · 翻转 '
                '${_flipH ? "水平" : ""}${_flipH && _flipV ? " + " : ""}'
                '${_flipV ? "垂直" : ""}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _CropSlider(
                label: '左',
                value: _left,
                max: 1 - kMinImageCropFraction,
                onChanged: (value) => setState(
                  () => _left = value
                      .clamp(0, _right - kMinImageCropFraction)
                      .toDouble(),
                ),
              ),
              _CropSlider(
                label: '右',
                value: _right,
                min: kMinImageCropFraction,
                onChanged: (value) => setState(
                  () => _right = value
                      .clamp(_left + kMinImageCropFraction, 1)
                      .toDouble(),
                ),
              ),
              _CropSlider(
                label: '上',
                value: _top,
                max: 1 - kMinImageCropFraction,
                onChanged: (value) => setState(
                  () => _top = value
                      .clamp(0, _bottom - kMinImageCropFraction)
                      .toDouble(),
                ),
              ),
              _CropSlider(
                label: '下',
                value: _bottom,
                min: kMinImageCropFraction,
                onChanged: (value) => setState(
                  () => _bottom = value
                      .clamp(_top + kMinImageCropFraction, 1)
                      .toDouble(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _rotation = (_rotation + 270) % 360,
                    ),
                    icon: const Icon(Icons.rotate_left),
                    label: const Text('左转 90°'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _rotation = (_rotation + 90) % 360,
                    ),
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('右转 90°'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _flipH = !_flipH),
                    icon: const Icon(Icons.flip),
                    label: const Text('水平翻转'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _flipV = !_flipV),
                    icon: const Icon(Icons.flip_camera_android),
                    label: const Text('垂直翻转'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('重置')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ImageEditResult(
              crop: crop,
              rotation: _rotation,
              flipH: _flipH,
              flipV: _flipV,
            ),
          ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _CropSlider extends StatelessWidget {
  const _CropSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 24, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: 95,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ImagePreviewPainter extends CustomPainter {
  const _ImagePreviewPainter({
    required this.image,
    required this.crop,
    required this.rotation,
    required this.flipH,
    required this.flipV,
  });

  final ui.Image image;
  final Rect crop;
  final int rotation;
  final bool flipH;
  final bool flipV;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final target = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side * 0.88,
      height: side * 0.88,
    );
    paintImageElementContent(
      canvas,
      target,
      image,
      crop: crop,
      rotation: rotation,
      flipH: flipH,
      flipV: flipV,
      opacity: 1,
    );
  }

  @override
  bool shouldRepaint(_ImagePreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.crop != crop ||
        oldDelegate.rotation != rotation ||
        oldDelegate.flipH != flipH ||
        oldDelegate.flipV != flipV;
  }
}
