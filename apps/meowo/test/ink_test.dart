import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/editor_page.dart';

void main() {
  testWidgets('pen stroke is committed to the core', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-ink-test-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '笔迹测试',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byType(CanvasView);
    expect(canvas, findsOneWidget);
    final center = tester.getCenter(canvas);
    await tester.dragFrom(center - const Offset(60, 20), const Offset(120, 40));
    await tester.pump(const Duration(milliseconds: 500));
    final opened = core.call('open_document', {'id': doc['id']});
    final layers = (opened['pages'] as List).first['layers'] as List;
    final elements = layers.first['elements'] as List;
    expect(elements.where((e) => e['type'] == 'stroke').length, 1);
  });
}
