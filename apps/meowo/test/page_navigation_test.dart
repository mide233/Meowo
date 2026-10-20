import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/canvas_view.dart';
import 'package:meowo/core/meowo_core.dart';
import 'package:meowo/editor_page.dart';
import 'package:meowo/library_page.dart';

void main() {
  testWidgets('page count opens cards and jumps to a page', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-page-picker-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '翻页测试',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 3 页'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-count-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-picker')), findsOneWidget);
    expect(find.text('当前第 3 / 3 页'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-card-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-card-0')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hand drag moves a paged document to the previous page', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('meowo-page-swipe-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '滑动翻页',
      'kind': 'paged',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('插入一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 页'), findsOneWidget);

    await tester.tap(find.byTooltip('移动'));
    await tester.pumpAndSettle();
    final canvas = find.byType(CanvasView);
    final topLeft = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    await tester.dragFrom(
      topLeft + Offset(size.width / 2, size.height / 2),
      Offset(size.width * 0.35, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite canvas has no page picker', (tester) async {
    final root = Directory.systemTemp.createTempSync('meowo-infinite-nav-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final doc = core.call('create_document', {
      'title': '无极导航',
      'kind': 'infinite',
      'paper': {'preset': 'A4'},
    });
    await state.refresh();
    await state.openDocument(doc['id'] as String);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无极画布'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-count-button')), findsNothing);
  });

  testWidgets('library shows an import overlay and disables import buttons', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('meowo-import-ui-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    state.importing = true;
    state.importLabel = 'PDF';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryPage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('import-progress')), findsOneWidget);
    expect(find.text('正在导入 PDF…'), findsOneWidget);
    final pdfButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('导入 PDF'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(pdfButton.onPressed, isNull);
    final barrier = tester.widget<ModalBarrier>(
      find.descendant(
        of: find.byKey(const ValueKey('import-progress')),
        matching: find.byType(ModalBarrier),
      ),
    );
    expect(barrier.dismissible, isFalse);
    expect(tester.takeException(), isNull);
  });
}
