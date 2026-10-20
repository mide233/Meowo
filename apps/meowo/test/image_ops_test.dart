import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/image_ops.dart';

void main() {
  test('image crop defaults to full frame', () {
    expect(normalizeImageCrop({}), const Rect.fromLTRB(0, 0, 1, 1));
  });

  test('image crop clamps invalid values and preserves minimum area', () {
    final crop = normalizeImageCrop({
      'cropLeft': 0.99,
      'cropTop': -1.0,
      'cropRight': 1.2,
      'cropBottom': 0.99,
    });
    expect(crop.left, closeTo(0.95, 0.0001));
    expect(crop.top, 0.0);
    expect(crop.right, 1.0);
    expect(crop.bottom, closeTo(0.99, 0.0001));
    expect(crop.width, greaterThanOrEqualTo(kMinImageCropFraction));
    expect(crop.height, greaterThanOrEqualTo(kMinImageCropFraction));
  });

  test('image rotation normalizes to quarter turns', () {
    expect(normalizeImageRotation(null), 0);
    expect(normalizeImageRotation(-90), 270);
    expect(normalizeImageRotation(450), 90);
    expect(normalizeImageRotation(180), 180);
  });

  test('image flip flags are opt-in', () {
    expect(imageFlag({}, 'flipH'), isFalse);
    expect(imageFlag({'flipH': true}, 'flipH'), isTrue);
    expect(imageFlag({'flipH': 1}, 'flipH'), isFalse);
  });

}
