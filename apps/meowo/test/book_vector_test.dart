import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/book_vector.dart';
import 'package:meowo/canvas_view.dart';

const _vectorSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
  <rect width="10" height="10" fill="#00ff00"/>
  <rect x="5" width="5" height="10" fill="#ffffff"/>
</svg>
''';

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return image;
}

Future<Color> _pixelColor(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final offset = (y * frame.image.width + x) * 4;
    final bytes = data!.buffer.asUint8List();
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  } finally {
    frame.image.dispose();
  }
}

Map<String, dynamic> _page() => {
  'id': 'page_test',
  'width': 10.0,
  'height': 10.0,
  'sourceAssetId': 'asset_png',
  'isNotePage': false,
  'sourceIndex': 0,
  'body': null,
  'layers': <dynamic>[],
};

Map<String, dynamic> _document() => {
  'id': 'doc_test',
  'kind': 'book',
  'paper': {'width': 10.0, 'height': 10.0, 'background': 'blank'},
  'pages': [_page()],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a vector page and reports its point size', () async {
    final page = await loadBookVectorPage(_vectorSvg);
    expect(page, isNotNull);
    expect(page!.size, const Size(10, 10));
    page.dispose();
  });

  test('malformed SVG falls back without throwing', () async {
    expect(await loadBookVectorPage('<svg><broken'), isNull);
    expect(await loadBookVectorPage(''), isNull);
  });

  test('vector background replaces the PNG snapshot in exports', () async {
    final vector = (await loadBookVectorPage(_vectorSvg))!;
    addTearDown(vector.dispose);
    final raster = await _solidImage(const Color(0xFFFF0000));
    addTearDown(raster.dispose);
    final png = await renderPagePng(
      document: _document(),
      page: _page(),
      images: {'asset_png': raster},
      vectors: {'page_test': vector},
      pixelRatio: 8.0,
    );

    expect(await _pixelColor(png, 20, 40), const Color(0xFF00FF00));
    expect(await _pixelColor(png, 60, 40), const Color(0xFFFFFFFF));
  });

  test('missing vector keeps the imported PNG fallback', () async {
    final raster = await _solidImage(const Color(0xFFFF0000));
    addTearDown(raster.dispose);
    final png = await renderPagePng(
      document: _document(),
      page: _page(),
      images: {'asset_png': raster},
      pixelRatio: 8.0,
    );
    expect(await _pixelColor(png, 20, 40), const Color(0xFFFF0000));
  });

  test('background painter repaints when a PNG asset arrives late', () async {
    final document = _document();
    final page = _page();
    final images = <String, ui.Image>{};
    final vectors = <String, BookVectorPage>{};
    final before = BookBackgroundPainter(
      document: document,
      page: page,
      scale: 1,
      images: images,
      vectors: vectors,
    );
    final unchanged = BookBackgroundPainter(
      document: document,
      page: page,
      scale: 1,
      images: images,
      vectors: vectors,
    );
    expect(unchanged.shouldRepaint(before), isFalse);
    images['asset_png'] = await _solidImage(const Color(0xFFFF0000));
    final after = BookBackgroundPainter(
      document: document,
      page: page,
      scale: 1,
      images: images,
      vectors: vectors,
    );
    expect(after.shouldRepaint(unchanged), isTrue);

    final vector = (await loadBookVectorPage(_vectorSvg))!;
    vectors['page_test'] = vector;
    final afterVector = BookBackgroundPainter(
      document: document,
      page: page,
      scale: 1,
      images: images,
      vectors: vectors,
    );
    expect(afterVector.shouldRepaint(after), isTrue);
    for (final image in images.values) {
      image.dispose();
    }
    vector.dispose();
  });

  test('background painter stays sharp when zoomed', () async {
    final vector = (await loadBookVectorPage(_vectorSvg))!;
    addTearDown(vector.dispose);
    final raster = await _solidImage(const Color(0xFFFF0000));
    addTearDown(raster.dispose);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    BookBackgroundPainter(
      document: _document(),
      page: _page(),
      scale: 8.0,
      images: {'asset_png': raster},
      vectors: {'page_test': vector},
    ).paint(canvas, const Size(80, 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 80);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final png = data!.buffer.asUint8List();

    // At 8x the vector/white boundary is one device pixel at x=40. A stretched
    // 120-dpi PNG would have no such boundary and would stay red throughout.
    expect(await _pixelColor(png, 39, 40), const Color(0xFF00FF00));
    expect(await _pixelColor(png, 41, 40), const Color(0xFFFFFFFF));
  });
}
