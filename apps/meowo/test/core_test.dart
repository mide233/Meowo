import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/core/meowo_core.dart';

void main() {
  test('FFI core round trip', () async {
    final root = await Directory.systemTemp.createTemp('meowo-ffi-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.delete(recursive: true));
    final info = core.call('workspace_info');
    expect(info['version'], isNotEmpty);
    final doc = core.call('create_document', {
      'title': 'FFI 测试',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    expect(doc['title'], 'FFI 测试');
    final list = core.call('list_documents');
    expect((list['items'] as List).length, 1);
    final opened = core.call('open_document', {'id': doc['id']});
    expect((opened['pages'] as List).length, 1);
  });

  test('pre-rendered PDF pages create a book', () async {
    final root = Directory.systemTemp.createTempSync('meowo-pages-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    final png = File('${root.path}/page-1.png');
    png.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
      ),
    );
    final doc = core.call('import_pdf_pages', {
      'title': 'Android PDF',
      'pages': [
        {'path': png.path, 'width': 300, 'height': 400},
      ],
    });
    expect(doc['pages'], 1);
    final opened = core.call('open_document', {'id': doc['id']});
    expect(opened['kind'], 'book');
    expect((opened['pages'] as List).first['sourceAssetId'], isNotEmpty);
  });

  test('PDF import creates a fixed-page book', () async {
    final root = Directory.systemTemp.createTempSync('meowo-pdf-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    final pdf = File('${root.path}/sample.pdf');
    final result = await Process.run('python3', [
      '-c',
      'from PIL import Image; Image.new("RGB",(300,400),"white").save(r"${pdf.path}")',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final doc = core.call('import_pdf', {'sourcePath': pdf.path});
    expect(doc['pages'], 1);
    final opened = core.call('open_document', {'id': doc['id']});
    expect((opened['pages'] as List).first['sourceAssetId'], isNotEmpty);
    expect(opened['kind'], 'book');
  });
}
