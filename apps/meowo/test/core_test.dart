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
    expect(opened['bookSource']['vector'], 'svg');
    expect(
      (opened['assets'] as List).any(
        (a) => a['kind'] == 'book_page' && a['mime'] == 'image/png',
      ),
      isTrue,
      reason: 'the PNG snapshot stays as the runtime fallback',
    );

    final vector = core.call('render_book_pages_svg', {
      'documentId': doc['id'],
      'pageIndexes': [0],
    });
    expect(vector['failures'], isEmpty);
    final vectorPages = vector['pages'] as List;
    expect(vectorPages, hasLength(1));
    final svg = vectorPages.first['svg'] as String;
    expect(svg, startsWith('<svg'));
    expect(svg, contains('<image'));
    expect(svg, isNot(contains('xlink:href="#font_')));
  });

  test('vector PDF export returns page and fallback reports', () async {
    final root = Directory.systemTemp.createTempSync('meowo-pdf-export-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    final pdf = File('${root.path}/book.pdf');
    final result = await Process.run('python3', [
      '-c',
      'from PIL import Image; '
          'im1=Image.new("RGB",(300,400),"white"); im2=Image.new("RGB",(500,300),"white"); '
          'im1.save(r"${pdf.path}", save_all=True, append_images=[im2])',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final imported = core.call('import_pdf', {'sourcePath': pdf.path});
    final out = '${root.path}/annotated.pdf';
    final exported = core.call('export_book_pdf', {
      'documentId': imported['id'],
      'targetPath': out,
      'pageIndexes': [1],
    });
    expect(exported['exportedPages'], [2]);
    expect(exported['vectorPages'], [2]);
    expect(exported['fallbackPages'], isEmpty);
    expect(File(out).existsSync(), isTrue);
    expect(File(out).readAsBytesSync().take(4), [0x25, 0x50, 0x44, 0x46]);

    final fallbackRoot = Directory.systemTemp.createTempSync(
      'meowo-pdf-fallback-test-',
    );
    final fallbackCore = await MeowoCore.open(fallbackRoot.path);
    addTearDown(fallbackCore.close);
    addTearDown(() => fallbackRoot.deleteSync(recursive: true));
    final png = File('${fallbackRoot.path}/page.png');
    png.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
      ),
    );
    final raster = fallbackCore.call('import_pdf_pages', {
      'title': 'raster',
      'pages': [
        {'path': png.path, 'width': 300, 'height': 400},
      ],
    });
    final fallbackOut = '${fallbackRoot.path}/fallback.pdf';
    final fallback = fallbackCore.call('export_book_pdf', {
      'documentId': raster['id'],
      'targetPath': fallbackOut,
      'pageIndexes': [0],
    });
    expect(fallback['vectorPages'], isEmpty);
    expect(fallback['fallbackPages'], hasLength(1));
    expect(fallback['fallbackPages'].first['reason'], 'missing_book_source');
  });

  test('encrypted PDF keeps PNG pages and never advertises vectors', () async {
    final ghostscript = await Process.run('which', ['gs']);
    if (ghostscript.exitCode != 0) {
      // Optional local dependency; the raster fallback is still covered by the
      // C++ marker tests when Ghostscript is unavailable.
      return;
    }
    final root = Directory.systemTemp.createTempSync('meowo-pdf-enc-test-');
    final core = await MeowoCore.open(root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    final plain = File('${root.path}/plain.pdf');
    final result = await Process.run('python3', [
      '-c',
      'from PIL import Image; Image.new("RGB",(300,400),"white").save(r"${plain.path}")',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final encrypted = File('${root.path}/encrypted.pdf');
    final gs = await Process.run('gs', [
      '-q',
      '-dNOPAUSE',
      '-dBATCH',
      '-sDEVICE=pdfwrite',
      '-sOwnerPassword=owner',
      '-sUserPassword=user',
      '-dPermissions=-4',
      '-dEncryptionR=3',
      '-dKeyLength=128',
      '-sOutputFile=${encrypted.path}',
      plain.path,
    ]);
    expect(gs.exitCode, 0, reason: gs.stderr.toString());

    final doc = core.call('import_pdf', {
      'sourcePath': encrypted.path,
      'password': 'user',
    });
    expect(doc['pages'], greaterThanOrEqualTo(1));
    final opened = core.call('open_document', {'id': doc['id']});
    expect(opened['bookSource']['encrypted'], isTrue);
    expect(opened['bookSource']['vector'], 'raster');
    expect(
      (opened['assets'] as List).any(
        (a) => a['kind'] == 'book_page' && a['mime'] == 'image/png',
      ),
      isTrue,
    );
    expect(
      () => core.call('render_book_pages_svg', {
        'documentId': doc['id'],
        'pageIndexes': [0],
      }),
      throwsA(isA<MeowoException>()),
    );

    final exported = core.call('export_book_pdf', {
      'documentId': doc['id'],
      'targetPath': '${root.path}/encrypted-out.pdf',
      'pageIndexes': [0],
    });
    expect(exported['vectorPages'], isEmpty);
    expect(exported['fallbackPages'], hasLength(1));
    expect(
      exported['fallbackPages'].first['reason'],
      'encrypted_pdf_no_password',
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
    expect(opened['bookSource']['vector'], 'raster');
    expect(
      () => core.call('render_book_pages_svg', {
        'documentId': doc['id'],
        'pageIndexes': [0],
      }),
      throwsA(isA<MeowoException>()),
    );
  });
}
