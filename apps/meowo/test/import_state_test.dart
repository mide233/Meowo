import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/app_state.dart';
import 'package:meowo/core/meowo_core.dart';

void main() {
  test(
    'markdown import exposes state, refreshes and opens the document',
    () async {
      final root = Directory.systemTemp.createTempSync('meowo-import-success-');
      final core = await MeowoCore.open(root.path);
      final state = AppState(core: core, libraryRoot: root.path);
      addTearDown(core.close);
      addTearDown(() => root.deleteSync(recursive: true));
      await state.initialize();
      final source = File('${root.path}/imported-note.md')
        ..writeAsStringSync('# Imported\n\nBody');

      final future = state.importMarkdown(source.path);
      expect(state.importing, isTrue);
      expect(state.importLabel, 'Markdown');
      await future;

      expect(state.importing, isFalse);
      expect(state.importLabel, isNull);
      expect(state.activeDocumentId, isNotNull);
      expect(state.activeDocument?['title'], 'imported-note');
      expect(
        state.documents.any((doc) => doc['id'] == state.activeDocumentId),
        isTrue,
      );
    },
  );

  test('a second import is ignored while one is running', () async {
    final root = Directory.systemTemp.createTempSync('meowo-import-dup-');
    final core = await MeowoCore.open(root.path);
    final state = AppState(core: core, libraryRoot: root.path);
    addTearDown(core.close);
    addTearDown(() => root.deleteSync(recursive: true));
    await state.initialize();
    final missing = '${root.path}/missing.md';

    final first = state.importMarkdown(missing);
    expect(state.importing, isTrue);
    await state.importMarkdown(missing);
    expect(state.importing, isTrue);
    await expectLater(first, throwsA(anything));
    expect(state.importing, isFalse);
    expect(state.importLabel, isNull);
  });
}
