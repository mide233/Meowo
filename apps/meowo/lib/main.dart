import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'core/meowo_core.dart';
import 'editor_page.dart';
import 'library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final support = await getApplicationSupportDirectory();
    final library = Directory(
      '${support.path}${Platform.pathSeparator}library',
    );
    await library.create(recursive: true);
    final core = await MeowoCore.open(library.path);
    final state = AppState(core: core, libraryRoot: library.path);
    await state.initialize();
    runApp(MeowoApp(state: state));
  } catch (error, stack) {
    runApp(StartupErrorApp(error: error, stack: stack));
  }
}

class MeowoApp extends StatelessWidget {
  const MeowoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFB4692A);
    final light = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFCF9F2),
    );
    final dark = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: '喵记 Meowo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: light,
        scaffoldBackgroundColor: const Color(0xFFF7F3EA),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: light.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: dark,
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: MeowoHome(state: state),
    );
  }
}

class MeowoHome extends StatelessWidget {
  const MeowoHome({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (state.openTabs.isNotEmpty) _Tabs(state: state),
                Expanded(
                  child: state.activeDocumentId == null
                      ? LibraryPage(state: state)
                      : EditorPage(state: state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: state.showLibrary,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('资料库'),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final id in state.openTabs)
                    _TabChip(
                      id: id,
                      active: id == state.activeDocumentId,
                      title: _titleFor(id),
                      onTap: () => state.selectDocument(id),
                      onClose: () => state.closeTab(id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleFor(String id) {
    for (final document in state.documents) {
      if (document['id'] == id) return document['title'] as String? ?? '未命名';
    }
    if (state.activeDocument?['id'] == id) {
      return state.activeDocument?['title'] as String? ?? '未命名';
    }
    return '文档';
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.id,
    required this.active,
    required this.title,
    required this.onTap,
    required this.onClose,
  });

  final String id;
  final bool active;
  final String title;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Material(
        color: active ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(title, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    '喵记启动失败',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText('$error'),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('技术细节'),
                    children: [SelectableText('$stack')],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
