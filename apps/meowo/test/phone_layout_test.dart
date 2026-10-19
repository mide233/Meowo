import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/library_page.dart';

void main() {
  testWidgets('phone layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('meowo-phone-test-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '手机布局',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('手机布局'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
