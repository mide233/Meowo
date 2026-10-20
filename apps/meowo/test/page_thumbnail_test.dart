import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/page_thumbnail.dart';

void main() {
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  test(
    'thumbnail cache deduplicates requests and serves cached bytes',
    () async {
      final cache = PageThumbnailCache();
      var renders = 0;
      final completer = Completer<Uint8List?>();
      Future<Uint8List?> render() {
        renders += 1;
        return completer.future;
      }

      final first = cache.load('page_a', render);
      final second = cache.load('page_a', render);
      expect(identical(first, second), isTrue);

      completer.complete(onePixelPng);
      expect(await first, onePixelPng);
      expect(await second, onePixelPng);
      expect(renders, 1);
      expect(cache.cachedCount, 1);
      expect(cache.peek('page_a'), onePixelPng);

      // A cache hit must not render again.
      expect(await cache.load('page_a', render), onePixelPng);
      expect(renders, 1);
    },
  );

  test('thumbnail cache clear invalidates in-flight results', () async {
    final cache = PageThumbnailCache();
    final completer = Completer<Uint8List?>();
    var renders = 0;
    final first = cache.load('page_a', () {
      renders += 1;
      return completer.future;
    });
    cache.clear();
    completer.complete(onePixelPng);
    await first;
    expect(cache.peek('page_a'), isNull);

    final fresh = await cache.load('page_a', () async {
      renders += 1;
      return onePixelPng;
    });
    expect(fresh, onePixelPng);
    expect(renders, 2);
    expect(cache.peek('page_a'), onePixelPng);
  });

  testWidgets('thumbnail widget shows a placeholder then the image', (
    tester,
  ) async {
    final completer = Completer<Uint8List?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 160,
              child: PageThumbnail(
                pageId: 'page_a',
                aspectRatio: 0.75,
                load: () => completer.future,
                placeholder: const ColoredBox(
                  key: ValueKey('thumbnail-placeholder'),
                  color: Color(0xFFFFFCF5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('thumbnail-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-image')), findsNothing);

    completer.complete(onePixelPng);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-thumbnail-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumbnail-placeholder')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache renders a real page at thumbnail resolution', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final document = <String, dynamic>{
        'id': 'doc_thumb',
        'kind': 'paged',
        'paper': {'width': 595.276, 'height': 841.89, 'background': 'blank'},
      };
      final page = <String, dynamic>{
        'id': 'page_thumb',
        'width': 595.276,
        'height': 841.89,
        'layers': [
          {
            'id': 'layer_1',
            'visible': true,
            'opacity': 1.0,
            'elements': [
              {
                'id': 'text_1',
                'type': 'text',
                'x': 48.0,
                'y': 48.0,
                'w': 400.0,
                'h': 120.0,
                'markdown': 'thumbnail',
                'fontSize': 16.0,
                'lineHeight': 1.5,
                'color': '#222222',
              },
            ],
          },
        ],
      };
      final cache = PageThumbnailCache();
      var renders = 0;
      Future<Uint8List?> render() {
        renders += 1;
        return renderPagePng(
          document: document,
          page: page,
          images: const {},
          pixelRatio: 0.3,
        );
      }

      final bytes = await cache.load('page_thumb', render);
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(100));
      expect(cache.peek('page_thumb'), same(bytes));
      expect(await cache.load('page_thumb', render), same(bytes));
      expect(renders, 1);

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, closeTo(595.276 * 0.3, 1));
      expect(frame.image.height, closeTo(841.89 * 0.3, 1));
      frame.image.dispose();
      codec.dispose();
    });
  });
}
