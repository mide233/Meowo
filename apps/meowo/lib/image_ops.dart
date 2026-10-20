import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Minimum visible fraction of the source image on each axis.
const double kMinImageCropFraction = 0.05;

double _number(Map<String, dynamic> element, String key, double fallback) {
  return (element[key] as num?)?.toDouble() ?? fallback;
}

/// Returns a clamped, non-empty normalized crop rectangle for an image element.
///
/// Defaults to the full image when crop keys are missing or invalid. The
/// rectangle is expressed in normalized source coordinates (0..1).
Rect normalizeImageCrop(Map<String, dynamic> element) {
  var left = _number(element, 'cropLeft', 0).clamp(0.0, 1.0).toDouble();
  var top = _number(element, 'cropTop', 0).clamp(0.0, 1.0).toDouble();
  var right = _number(element, 'cropRight', 1).clamp(0.0, 1.0).toDouble();
  var bottom = _number(element, 'cropBottom', 1).clamp(0.0, 1.0).toDouble();

  if (right - left < kMinImageCropFraction) {
    if (left > 1 - kMinImageCropFraction) {
      left = 1 - kMinImageCropFraction;
      right = 1;
    } else {
      right = left + kMinImageCropFraction;
    }
  }
  if (bottom - top < kMinImageCropFraction) {
    if (top > 1 - kMinImageCropFraction) {
      top = 1 - kMinImageCropFraction;
      bottom = 1;
    } else {
      bottom = top + kMinImageCropFraction;
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Normalizes a rotation to one of 0, 90, 180, 270 degrees.
int normalizeImageRotation(dynamic raw) {
  final degrees = (raw as num?)?.toDouble() ?? 0;
  final turns = (degrees / 90).round();
  return ((turns % 4) + 4) % 4 * 90;
}

bool imageFlag(Map<String, dynamic> element, String key) {
  return element[key] == true;
}

/// Paints an image element with non-destructive crop, rotation and flip.
///
/// The destination rectangle keeps the element frame; the image content is
/// transformed inside that frame. Used by the canvas, PNG export and PDF export.
void paintImageElementContent(
  Canvas canvas,
  Rect destination,
  ui.Image image, {
  required Rect crop,
  required int rotation,
  required bool flipH,
  required bool flipV,
  required double opacity,
}) {
  final source = Rect.fromLTRB(
    crop.left * image.width,
    crop.top * image.height,
    crop.right * image.width,
    crop.bottom * image.height,
  );
  if (source.isEmpty) return;

  final normalizedRotation = normalizeImageRotation(rotation);
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));

  canvas.save();
  canvas.translate(destination.center.dx, destination.center.dy);
  if (normalizedRotation != 0) {
    canvas.rotate(normalizedRotation * math.pi / 180);
  }
  if (flipH || flipV) {
    canvas.scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0);
  }
  final target = Rect.fromCenter(
    center: Offset.zero,
    width: destination.width,
    height: destination.height,
  );
  canvas.drawImageRect(image, source, target, paint);
  canvas.restore();
}
