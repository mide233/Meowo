import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/pdf_export.dart';

void main() {
  test('annotated PDF filename is sanitized and dated', () {
    expect(
      annotatedPdfFileName('线性代数/讲义', DateTime(2026, 10, 20)),
      '线性代数_讲义-annotated-20261020.pdf',
    );
    expect(
      annotatedPdfFileName('  ', DateTime(2026, 1, 2)),
      '未命名-annotated-20260102.pdf',
    );
  });

  test('page ranges are parsed, sorted and validated', () {
    expect(parsePageRange('1-3, 5', 10), [0, 1, 2, 4]);
    expect(parsePageRange('5，3–4', 10), [2, 3, 4]);
    expect(parsePageRange(' 2 ', 2), [1]);
    expect(() => parsePageRange('0', 5), throwsFormatException);
    expect(() => parsePageRange('4-2', 5), throwsFormatException);
    expect(() => parsePageRange('6', 5), throwsFormatException);
    expect(() => parsePageRange('1,,2', 5), throwsFormatException);
    expect(() => parsePageRange('abc', 5), throwsFormatException);
  });

  test('exported pages are compacted for the report', () {
    expect(compactPageRanges([1, 2, 3, 5, 8, 9]), '1–3, 5, 8–9');
    expect(compactPageRanges([4]), '4');
    expect(compactPageRanges(const []), '无');
  });

  test('only text, images and attachments need a raster overlay', () {
    expect(
      pageHasRasterOverlay({
        'layers': [
          {
            'visible': true,
            'opacity': 1.0,
            'elements': [
              {'type': 'stroke'},
            ],
          },
        ],
      }),
      isFalse,
    );
    expect(
      pageHasRasterOverlay({
        'layers': [
          {
            'visible': true,
            'opacity': 1.0,
            'elements': [
              {'type': 'text'},
            ],
          },
        ],
      }),
      isTrue,
    );
    expect(
      pageHasRasterOverlay({
        'layers': [
          {
            'visible': false,
            'opacity': 1.0,
            'elements': [
              {'type': 'image'},
            ],
          },
        ],
      }),
      isFalse,
    );
  });

  test('large exports trigger only a soft estimate warning', () {
    final document = <String, dynamic>{
      'pages': List.generate(300, (_) => {'isNotePage': true}),
      'bookSource': {'pageCount': 300},
      'assets': [
        {'kind': 'book_source', 'size': 1024 * 1024},
      ],
    };
    final small = estimatePdfExport(document, [0]);
    expect(small.warns, isFalse);
    final large = estimatePdfExport(
      document,
      List<int>.generate(300, (index) => index),
    );
    expect(large.warns, isTrue);
    expect(large.estimatedBytes, greaterThan(200 * 1024 * 1024));
  });

  test('progress files are parsed defensively', () {
    final progress = PdfExportProgress.fromJson({
      'phase': 'exporting',
      'completed': 3,
      'total': 10,
      'pageNumber': 4,
    });
    expect(progress.fraction, 0.3);
    expect(progress.pageNumber, 4);
    expect(PdfExportProgress.fromJson({}).phase, 'exporting');
  });

  testWidgets('Dart overlay PNG is embedded by the vector exporter', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('meowo-overlay-export-');
      final core = await MeowoCore.open(root.path);
      addTearDown(core.close);
      addTearDown(() => root.deleteSync(recursive: true));
      final pdf = File('${root.path}/book.pdf');
      final created = await Process.run('python3', [
        '-c',
        'from PIL import Image; Image.new("RGB",(300,400),"white").save(r"${pdf.path}")',
      ]);
      expect(created.exitCode, 0, reason: created.stderr.toString());
      final imported = core.call('import_pdf', {'sourcePath': pdf.path});
      final document = core.call('open_document', {'id': imported['id']});
      (document['pages'] as List).first['layers'][0]['elements'].add({
        'id': 'text_export',
        'type': 'text',
        'x': 20.0,
        'y': 20.0,
        'w': 200.0,
        'h': 80.0,
        'markdown': 'Overlay export',
        'fontSize': 18.0,
        'lineHeight': 1.4,
        'color': '#222222',
        'opacity': 1.0,
        'locked': false,
      });
      core.call('save_document', {'document': document});
      final page = Map<String, dynamic>.from(
        (document['pages'] as List).first as Map,
      );
      final overlay = await renderBookOverlayPng(
        document: document,
        page: page,
        images: const {},
        dpi: 72,
      );
      final overlayDir = Directory('${root.path}/overlays')..createSync();
      File(
        '${overlayDir.path}/overlay-0.png',
      ).writeAsBytesSync(overlay, flush: true);
      final out = '${root.path}/out.pdf';
      final result = core.call('export_book_pdf', {
        'documentId': imported['id'],
        'targetPath': out,
        'pageIndexes': [0],
        'overlayDir': overlayDir.path,
      });
      expect(result['vectorPages'], [1]);
      expect(result['fallbackPages'], isEmpty);
      final bytes = File(out).readAsBytesSync();
      expect(
        String.fromCharCodes(bytes).contains('/Subtype/Image'),
        isTrue,
        reason: 'the transparent overlay is embedded as an image XObject',
      );
    });
  });

  testWidgets('overlay PNG contains text but not ink or paper', (tester) async {
    await tester.runAsync(() async {
      final document = <String, dynamic>{
        'id': 'doc_export',
        'title': 'export',
        'kind': 'book',
        'paper': {'width': 200, 'height': 200, 'background': 'blank'},
      };
      final page = <String, dynamic>{
        'id': 'page_export',
        'width': 200.0,
        'height': 200.0,
        'body': null,
        'layers': [
          {
            'id': 'layer_export',
            'visible': true,
            'opacity': 1.0,
            'elements': [
              {
                'id': 'text_export',
                'type': 'text',
                'x': 10.0,
                'y': 10.0,
                'w': 120.0,
                'h': 40.0,
                'markdown': 'Meowo',
                'fontSize': 18.0,
                'lineHeight': 1.4,
                'color': '#222222',
              },
              {
                'id': 'ink_export',
                'type': 'stroke',
                'points': [
                  [150.0, 150.0, 1.0],
                  [190.0, 190.0, 1.0],
                ],
                'color': '#FF0000',
                'width': 8.0,
                'highlighter': false,
                'opacity': 1.0,
              },
            ],
          },
        ],
      };
      final png = await renderBookOverlayPng(
        document: document,
        page: page,
        images: const {},
        dpi: 144,
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        expect(image.width, 400);
        expect(image.height, 400);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        int alphaAt(int x, int y) => bytes[(y * image.width + x) * 4 + 3];
        expect(alphaAt(380, 380), 0, reason: 'paper background is excluded');
        var painted = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] != 0) painted++;
        }
        expect(painted, greaterThan(100), reason: 'text is rasterized');
        expect(alphaAt(340, 340), 0, reason: 'ink stays vector');
      } finally {
        image.dispose();
      }
    });
  });
}
