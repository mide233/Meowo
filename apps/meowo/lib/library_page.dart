import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.state});

  final AppState state;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final narrow = MediaQuery.sizeOf(context).width < 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 16 : 28,
                20,
                narrow ? 16 : 28,
                12,
              ),
              child: narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _Logo(scheme: scheme),
                            const SizedBox(width: 12),
                            Text(
                              '喵记',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Meowo',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _searchField(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _Logo(scheme: scheme),
                                  const SizedBox(width: 12),
                                  Text(
                                    '喵记',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1,
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Meowo',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          letterSpacing: 2,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '本地优先的手写与阅读笔记 · ${state.libraryRoot}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(width: 300, child: _searchField()),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _guard(() => _createDialog('paged')),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('新建书页'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _guard(() => _createDialog('infinite')),
                    icon: const Icon(Icons.open_with),
                    label: const Text('新建无极'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _guard(_importPdf),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('导入 PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _guard(_importEpub),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('导入 EPUB'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _guard(_importMarkdown),
                    icon: const Icon(Icons.code),
                    label: const Text('导入 Markdown'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _guard(_folderDialog),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新建文件夹'),
                  ),
                  if (state.selectedFolderId != null)
                    ActionChip(
                      avatar: const Icon(Icons.folder_open, size: 18),
                      label: const Text('清除文件夹筛选'),
                      onPressed: () => state.setFolder(null),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 28),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (narrow)
                    DropdownButton<LibraryFilter>(
                      value: state.filter,
                      items: const [
                        DropdownMenuItem(
                          value: LibraryFilter.all,
                          child: Text('全部'),
                        ),
                        DropdownMenuItem(
                          value: LibraryFilter.favorites,
                          child: Text('收藏'),
                        ),
                        DropdownMenuItem(
                          value: LibraryFilter.trash,
                          child: Text('回收站'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) _guard(() => state.setFilter(value));
                      },
                    )
                  else
                    SegmentedButton<LibraryFilter>(
                      segments: const [
                        ButtonSegment(
                          value: LibraryFilter.all,
                          icon: Icon(Icons.grid_view_outlined),
                          label: Text('全部'),
                        ),
                        ButtonSegment(
                          value: LibraryFilter.favorites,
                          icon: Icon(Icons.star_outline),
                          label: Text('收藏'),
                        ),
                        ButtonSegment(
                          value: LibraryFilter.trash,
                          icon: Icon(Icons.delete_outline),
                          label: Text('回收站'),
                        ),
                      ],
                      selected: {state.filter},
                      onSelectionChanged: (value) =>
                          _guard(() => state.setFilter(value.first)),
                    ),
                  if (state.folders.isNotEmpty)
                    DropdownButton<String?>(
                      value: state.selectedFolderId,
                      hint: const Text('全部文件夹'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('全部文件夹'),
                        ),
                        for (final folder in state.folders)
                          DropdownMenuItem(
                            value: folder['id'] as String,
                            child: Text(folder['name'] as String? ?? '文件夹'),
                          ),
                      ],
                      onChanged: (value) =>
                          _guard(() => state.setFolder(value)),
                    ),
                  Text(
                    '${state.documents.length} 个文档',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.documents.isEmpty
                  ? _EmptyLibrary(state: state)
                  : GridView.extent(
                      padding: EdgeInsets.fromLTRB(
                        narrow ? 16 : 28,
                        0,
                        narrow ? 16 : 28,
                        28,
                      ),
                      maxCrossAxisExtent: narrow ? 520 : 320,
                      mainAxisExtent: 166,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.8,
                      children: [
                        for (final document in state.documents)
                          _DocumentCard(
                            state: state,
                            document: document,
                            onOpen: () => _guard(
                              () =>
                                  state.openDocument(document['id'] as String),
                            ),
                            onGuard: _guard,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: '搜索标题、文本、书籍文字、附件名',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  state.setSearch('');
                },
              ),
      ),
      onChanged: (value) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          state.setSearch(value);
        });
        setState(() {});
      },
    );
  }

  Future<void> _importPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await state.importPdf(file.path);
  }

  Future<void> _importEpub() async {
    const typeGroup = XTypeGroup(label: 'EPUB', extensions: ['epub']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await state.importEpub(file.path);
  }

  Future<void> _importMarkdown() async {
    const typeGroup = XTypeGroup(
      label: 'Markdown',
      extensions: ['md', 'markdown'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await state.importMarkdown(file.path);
  }

  Future<void> _createDialog(String kind) async {
    final title = TextEditingController(text: kind == 'paged' ? '新笔记' : '无极画布');
    final preset = ValueNotifier('A4');
    final landscape = ValueNotifier(false);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(kind == 'paged' ? '新建书页文档' : '新建无极文档'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              if (kind == 'paged') ...[
                const SizedBox(height: 14),
                ValueListenableBuilder<String>(
                  valueListenable: preset,
                  builder: (context, value, _) =>
                      DropdownButtonFormField<String>(
                        initialValue: value,
                        decoration: const InputDecoration(labelText: '纸张'),
                        items: const [
                          DropdownMenuItem(value: 'A4', child: Text('A4')),
                          DropdownMenuItem(value: 'A5', child: Text('A5')),
                          DropdownMenuItem(value: 'B5', child: Text('B5')),
                          DropdownMenuItem(
                            value: 'Letter',
                            child: Text('Letter'),
                          ),
                          DropdownMenuItem(
                            value: 'Legal',
                            child: Text('Legal'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) preset.value = value;
                        },
                      ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: landscape,
                  builder: (context, value, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('横向'),
                    value: value,
                    onChanged: (value) => landscape.value = value,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result == true) {
      await state.createDocument(
        title: title.text,
        kind: kind,
        paperPreset: preset.value,
        landscape: landscape.value,
      );
    }
    title.dispose();
    preset.dispose();
    landscape.dispose();
  }

  Future<void> _folderDialog() async {
    final name = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      await state.createFolder(name.text.trim());
    }
    name.dispose();
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.pets, color: scheme.onPrimaryContainer),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = switch (state.filter) {
      LibraryFilter.trash => '回收站是空的。删除的文档会在这里保留 30 天。',
      LibraryFilter.favorites => '还没有收藏的文档。',
      LibraryFilter.all => '从一张空白纸开始，或导入 PDF / Markdown。',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined, size: 72, color: scheme.outline),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.state,
    required this.document,
    required this.onOpen,
    required this.onGuard,
  });

  final AppState state;
  final Map<String, dynamic> document;
  final VoidCallback onOpen;
  final Future<void> Function(Future<void> Function()) onGuard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = document['kind'] as String? ?? 'paged';
    final icon = switch (kind) {
      'book' => Icons.menu_book_outlined,
      'infinite' => Icons.open_with,
      _ => Icons.description_outlined,
    };
    final favorite = document['favorite'] == true;
    final deleted = document['deletedAt'] != null;
    final updated = DateTime.fromMillisecondsSinceEpoch(
      (document['updatedAt'] as num?)?.toInt() ?? 0,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: deleted ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: scheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      document['title'] as String? ?? '未命名',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _menu(context, value),
                    itemBuilder: (context) => [
                      if (!deleted) ...[
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(favorite ? '取消收藏' : '收藏'),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('重命名'),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('导出 .meowo'),
                        ),
                        const PopupMenuItem(
                          value: 'folders',
                          child: Text('移动到文件夹'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('移到回收站'),
                        ),
                      ] else ...[
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('恢复'),
                        ),
                        const PopupMenuItem(
                          value: 'purge',
                          child: Text('永久删除'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    switch (kind) {
                      'book' => '喵书籍',
                      'infinite' => '无极画布',
                      _ => '书页',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '· ${updated.month}/${updated.day} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (favorite)
                    Icon(Icons.star, size: 18, color: scheme.tertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, String value) async {
    switch (value) {
      case 'favorite':
        await onGuard(() => state.toggleFavorite(document['id'] as String));
      case 'rename':
        final controller = TextEditingController(
          text: document['title'] as String? ?? '',
        );
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('重命名'),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          ),
        );
        if (result == true) {
          await onGuard(
            () => state.renameDocument(
              document['id'] as String,
              controller.text.trim(),
            ),
          );
        }
        controller.dispose();
      case 'export':
        final location = await getSaveLocation(
          suggestedName:
              '${(document['title'] as String? ?? '未命名').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.meowo',
        );
        if (location != null) {
          await onGuard(
            () => state.exportDocument(document['id'] as String, location.path),
          );
        }
      case 'folders':
        if (context.mounted) {
          final folder = await showDialog<String?>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('移动到文件夹'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('未分类'),
                ),
                for (final folder in state.folders)
                  SimpleDialogOption(
                    onPressed: () =>
                        Navigator.pop(context, folder['id'] as String),
                    child: Text(folder['name'] as String? ?? '文件夹'),
                  ),
              ],
            ),
          );
          if (folder != null) {
            await onGuard(
              () => state.moveToFolder(
                document['id'] as String,
                folder.isEmpty ? null : folder,
              ),
            );
          }
        }
      case 'delete':
        if (await _confirm(context, '移到回收站？', '文档会在回收站保留 30 天。')) {
          await onGuard(() => state.deleteDocument(document['id'] as String));
        }
      case 'restore':
        await onGuard(() => state.restoreDocument(document['id'] as String));
      case 'purge':
        if (await _confirm(context, '永久删除？', '此操作不可撤销。')) {
          await onGuard(() => state.purgeDocument(document['id'] as String));
        }
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
