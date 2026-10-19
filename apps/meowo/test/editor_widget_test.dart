import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/library_page.dart';

void main() {
  testWidgets('library and editor render with a real core', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-widget-test-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();

    final doc = core.call('create_document', {
      'title': '编辑器测试',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('喵记'), findsOneWidget);
    expect(find.text('新建书页'), findsOneWidget);
    expect(find.text('编辑器测试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑器测试'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
