import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'core/meowo_core.dart';

enum LibraryFilter { all, favorites, trash }

class AppState extends ChangeNotifier {
  AppState({required this.core, required this.libraryRoot});

  final MeowoCore core;
  final String libraryRoot;

  List<Map<String, dynamic>> documents = [];
  List<Map<String, dynamic>> folders = [];
  final List<String> openTabs = [];
  String? activeDocumentId;
  Map<String, dynamic>? activeDocument;
  LibraryFilter filter = LibraryFilter.all;
  String searchQuery = '';
  String? selectedFolderId;
  bool loading = false;
  bool importing = false;
  String? importLabel;
  String? error;

  Map<String, dynamic> get info => core.call('workspace_info');

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final args = <String, dynamic>{
        'trash': filter == LibraryFilter.trash,
        'favorites': filter == LibraryFilter.favorites,
      };
      if (selectedFolderId != null) args['folderId'] = selectedFolderId;
      if (searchQuery.trim().isNotEmpty) {
        final result = core.call('search', {'query': searchQuery.trim()});
        documents = (result['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } else {
        final result = core.call('list_documents', args);
        documents = (result['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      final folderResult = core.call('list_folders');
      folders = (folderResult['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(LibraryFilter value) async {
    filter = value;
    selectedFolderId = null;
    await refresh();
  }

  Future<void> setFolder(String? id) async {
    selectedFolderId = id;
    await refresh();
  }

  Future<void> setSearch(String value) async {
    searchQuery = value;
    await refresh();
  }

  Future<void> createDocument({
    required String title,
    required String kind,
    String paperPreset = 'A4',
    bool landscape = false,
    String? paperBackground,
    String? folderId,
  }) async {
    final document = core.call('create_document', {
      'title': title.trim().isEmpty ? '未命名' : title.trim(),
      'kind': kind,
      'paper': {
        'preset': paperPreset,
        'landscape': landscape,
        'background': ?paperBackground,
      },
      'folderId': ?folderId,
    });
    await refresh();
    await openDocument(document['id'] as String);
  }

  Future<void> _importInBackground(String op, String path) async {
    if (importing) return;
    importing = true;
    importLabel = switch (op) {
      'import_pdf' => 'PDF',
      'import_epub' => 'EPUB',
      _ => 'Markdown',
    };
    error = null;
    notifyListeners();
    try {
      final root = libraryRoot;
      final result = await Isolate.run(() async {
        final worker = await MeowoCore.open(root, acquireLock: false);
        try {
          return worker.call(op, {'sourcePath': path});
        } finally {
          worker.close();
        }
      });
      await refresh();
      await openDocument(result['id'] as String);
    } finally {
      importing = false;
      importLabel = null;
      notifyListeners();
    }
  }

  Future<void> importMarkdown(String path) =>
      _importInBackground('import_markdown', path);

  Future<void> importPdf(String path) =>
      _importInBackground('import_pdf', path);

  Future<void> importEpub(String path) =>
      _importInBackground('import_epub', path);

  Future<void> openDocument(String id) async {
    final document = core.call('open_document', {'id': id});
    activeDocument = Map<String, dynamic>.from(document);
    activeDocumentId = id;
    if (!openTabs.contains(id)) openTabs.add(id);
    notifyListeners();
    await refresh();
  }

  Future<void> saveActiveDocument() async {
    final document = activeDocument;
    if (document == null) return;
    try {
      core.call('save_document', {'document': document});
    } catch (_) {
      // The editor shows save errors; callers may still leave the document.
    }
  }

  Future<void> selectDocument(String id) async {
    if (activeDocumentId == id) return;
    await saveActiveDocument();
    activeDocumentId = id;
    activeDocument = null;
    notifyListeners();
    await loadActiveDocument();
  }

  Future<void> loadActiveDocument() async {
    final id = activeDocumentId;
    if (id == null) return;
    try {
      final document = core.call('open_document', {'id': id});
      activeDocument = Map<String, dynamic>.from(document);
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void setActiveDocument(Map<String, dynamic> document) {
    activeDocument = document;
    notifyListeners();
  }

  Future<void> saveDocument(Map<String, dynamic> document) async {
    final id = document['id'] as String;
    document['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    core.call('save_document', {'document': document});
    activeDocument = document;
    final index = documents.indexWhere((item) => item['id'] == id);
    if (index >= 0) {
      documents[index] = {
        ...documents[index],
        'title': document['title'],
        'updatedAt': document['updatedAt'],
      };
    }
    notifyListeners();
  }

  Future<void> closeTab(String id) async {
    if (activeDocumentId == id) await saveActiveDocument();
    openTabs.remove(id);
    if (activeDocumentId == id) {
      activeDocumentId = openTabs.isEmpty ? null : openTabs.last;
      activeDocument = null;
    }
    notifyListeners();
  }

  void showLibrary() {
    activeDocumentId = null;
    activeDocument = null;
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    core.call('toggle_favorite', {'id': id});
    await refresh();
  }

  Future<void> deleteDocument(String id) async {
    core.call('delete_document', {'id': id});
    openTabs.remove(id);
    if (activeDocumentId == id) {
      activeDocumentId = null;
      activeDocument = null;
    }
    await refresh();
  }

  Future<void> restoreDocument(String id) async {
    core.call('restore_document', {'id': id});
    await refresh();
  }

  Future<void> purgeDocument(String id) async {
    core.call('purge_document', {'id': id});
    await refresh();
  }

  Future<void> renameDocument(String id, String title) async {
    core.call('rename_document', {'id': id, 'title': title});
    if (activeDocument?['id'] == id) activeDocument!['title'] = title;
    await refresh();
  }

  Future<void> createFolder(String name, {String? parentId}) async {
    core.call('create_folder', {'name': name, 'parentId': ?parentId});
    await refresh();
  }

  Future<void> deleteFolder(String id) async {
    core.call('delete_folder', {'id': id});
    if (selectedFolderId == id) selectedFolderId = null;
    await refresh();
  }

  Future<void> moveToFolder(String documentId, String? folderId) async {
    core.call('move_document', {'id': documentId, 'folderId': folderId ?? ''});
    await refresh();
  }

  Future<String> exportDocument(String id, String targetPath) async {
    final result = core.call('export_document', {
      'id': id,
      'targetPath': targetPath,
    });
    return result['path'] as String;
  }

  /// Runs the vector PDF exporter in a worker isolate. The worker only reads
  /// the document and its assets; all UI/overlay rasterization happens before
  /// this call. Progress/cancel are exchanged through files because the C ABI
  /// is synchronous.
  Future<Map<String, dynamic>> exportBookPdf({
    required String documentId,
    required String targetPath,
    required List<int> pageIndexes,
    required String overlayDir,
    required String progressPath,
    required String cancelPath,
    bool overwrite = true,
  }) async {
    final root = libraryRoot;
    return Isolate.run(() async {
      final worker = await MeowoCore.open(root, acquireLock: false);
      try {
        return worker.call('export_book_pdf', {
          'documentId': documentId,
          'targetPath': targetPath,
          'pageIndexes': pageIndexes,
          'overlayDir': overlayDir,
          'progressPath': progressPath,
          'cancelPath': cancelPath,
          'overwrite': overwrite,
        });
      } finally {
        worker.close();
      }
    });
  }

  Future<Map<String, dynamic>> addAsset(
    String documentId,
    String path,
    String mime,
  ) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final data = base64Encode(bytes);
    return core.call('add_asset', {
      'documentId': documentId,
      'name': file.uri.pathSegments.last,
      'mime': mime,
      'data': data,
    });
  }

  Future<Map<String, dynamic>> getAsset(
    String documentId,
    String assetId,
  ) async {
    return core.call('get_asset', {
      'documentId': documentId,
      'assetId': assetId,
    });
  }

  /// Renders up to eight PDF pages to SVG in a background isolate. Returns an
  /// empty map when vector pages are unsupported or the source is unavailable;
  /// the editor then keeps the imported PNG snapshots.
  Future<Map<int, String>> renderBookPagesSvg(
    String documentId,
    List<int> pageIndexes,
  ) async {
    if (pageIndexes.isEmpty) return const <int, String>{};
    final root = libraryRoot;
    try {
      final result = await Isolate.run(() async {
        final worker = await MeowoCore.open(root, acquireLock: false);
        try {
          return worker.call('render_book_pages_svg', {
            'documentId': documentId,
            'pageIndexes': pageIndexes,
          });
        } finally {
          worker.close();
        }
      });
      final pages = <int, String>{};
      for (final value in result['pages'] as List? ?? const []) {
        final page = value as Map;
        final index = page['index'];
        final svg = page['svg'];
        if (index is int && svg is String) pages[index] = svg;
      }
      return pages;
    } catch (_) {
      return const <int, String>{};
    }
  }

  Future<List<Map<String, dynamic>>> listAssets(String documentId) async {
    final result = core.call('list_assets', {'documentId': documentId});
    return (result['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> deleteAsset(String documentId, String assetId) async {
    core.call('delete_asset', {'documentId': documentId, 'assetId': assetId});
  }
}
