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
    expect(doc['engine'], 'mupdf');
    final opened = core.call('open_document', {'id': doc['id']});
    expect((opened['pages'] as List).first['sourceAssetId'], isNotEmpty);
    expect(opened['kind'], 'book');
    expect(opened['bookSource']['engine'], 'mupdf');
    expect(
      (opened['assets'] as List).any((a) => a['mime'] == 'application/pdf'),
      isTrue,
    );
  });

  test('EPUB import uses MuPDF and stores the original', () async {
    final root = Directory.systemTemp.createTempSync('meowo-epub-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    final epub = File('${root.path}/sample.epub');
    const script = r'''
import sys, zipfile
path = sys.argv[1]
files = {
  "mimetype": "application/epub+zip",
  "META-INF/container.xml": """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
 <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>""",
  "OEBPS/content.opf": """<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id">
 <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:identifier id="id">meowo-test</dc:identifier>
  <dc:title>book.html</dc:title>
  <dc:language>zh-CN</dc:language>
 </metadata>
 <manifest><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
 <spine><itemref idref="c1"/></spine>
</package>""",
  "OEBPS/chapter.xhtml": """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
<body><h1>喵记 EPUB</h1><p>这是通过 MuPDF 导入的固定页测试。</p></body></html>""",
}
with zipfile.ZipFile(path, "w") as z:
    z.writestr("mimetype", files["mimetype"], compress_type=zipfile.ZIP_STORED)
    for name in ("META-INF/container.xml", "OEBPS/content.opf", "OEBPS/chapter.xhtml"):
        z.writestr(name, files[name], compress_type=zipfile.ZIP_DEFLATED)
''';
    final result = await Process.run('python3', ['-c', script, epub.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final doc = core.call('import_epub', {'sourcePath': epub.path});
    expect(doc['pages'], greaterThanOrEqualTo(1));
    expect(doc['engine'], 'mupdf');
    expect(doc['title'], 'sample');
    final opened = core.call('open_document', {'id': doc['id']});
    expect(opened['kind'], 'book');
    expect(opened['bookSource']['engine'], 'mupdf');
    expect(
      (opened['assets'] as List).any(
        (a) => a['mime'] == 'application/epub+zip',
      ),
      isTrue,
    );
  });
}
