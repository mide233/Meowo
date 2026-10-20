import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';

void main() {
  testWidgets('imported PDF paints a parsed vector background', (tester) async {
    late Directory root;
    late MeowoCore core;
    late AppState state;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('meowo-vector-ui-');
      core = await MeowoCore.open(root.path);
      final pdf = File('${root.path}/page.pdf');
      final result = await Process.run('python3', [
        '-c',
        'from PIL import Image; Image.new("RGB",(300,400),"white").save(r"${pdf.path}")',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final imported = core.call('import_pdf', {'sourcePath': pdf.path});
      state = AppState(core: core, libraryRoot: root.path);
      await state.openDocument(imported['id'] as String);
    });
    addTearDown(() {
      core.close();
      root.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );

    List<BookBackgroundPainter> backgrounds() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<BookBackgroundPainter>()
        .toList();

    // Isolate work and flutter_svg's compute() need real async in widget
    // tests; pump alone uses the fake clock.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final paints = backgrounds();
      if (paints.isNotEmpty && paints.first.vectors.isNotEmpty) break;
    }
    final paints = backgrounds();
    expect(paints, isNotEmpty);
    expect(
      paints.first.vectors,
      isNotEmpty,
      reason: 'the PDF page should be parsed through the background isolate',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
