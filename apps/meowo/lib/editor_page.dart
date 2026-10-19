import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'canvas_view.dart';

enum _SaveState { saved, saving, failed }

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.state});

  final AppState state;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _canvasKey = GlobalKey();
  final _undo = <String>[];
  final _redo = <String>[];
  final _images = <String, ui.Image>{};

  String _tool = 'pen';
  Color _color = const Color(0xFF2B2A27);
  double _width = 2.5;
  int _pageIndex = 0;
  String? _activeLayerId;
  String? _loadedDocId;
  bool _loading = true;
  _SaveState _saveState = _SaveState.saved;
  Timer? _saveTimer;
  int _saveGeneration = 0;

  AppState get state => widget.state;
  Map<String, dynamic>? get _doc => state.activeDocument;

  Map<String, dynamic> get _page {
    final pages = _doc!['pages'] as List;
    if (_pageIndex >= pages.length) _pageIndex = pages.length - 1;
    return pages[_pageIndex] as Map<String, dynamic>;
  }

  List get _layersRaw => _page['layers'] as List;

  List<Map<String, dynamic>> get _layers {
    return _layersRaw.map((e) => e as Map<String, dynamic>).toList();
  }

  Map<String, dynamic>? get _activeLayer {
    final layers = _layers;
    if (layers.isEmpty) return null;
    for (final layer in layers) {
      if (layer['id'] == _activeLayerId) return layer;
    }
    _activeLayerId = layers.first['id'] as String?;
    return layers.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocument());
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loadedDocId != state.activeDocumentId) {
      _loadDocument();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final id = state.activeDocumentId;
    if (id == null) return;
    setState(() {
      _loading = true;
    });
    try {
      if (state.activeDocument == null || state.activeDocument?['id'] != id) {
        await state.loadActiveDocument();
      }
      if (!mounted) return;
      _loadedDocId = id;
      _pageIndex = 0;
      _undo.clear();
      _redo.clear();
      _activeLayerId = _layers.isEmpty ? null : _layers.first['id'] as String?;
      await _loadPageImages();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _saveState = _SaveState.saved;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _message(error.toString(), error: true);
    }
  }

  Future<void> _loadPageImages() async {
    final doc = _doc;
    if (doc == null) return;
    final ids = <String>{};
    final page = _page;
    final source = page['sourceAssetId'] as String?;
    if (source != null) ids.add(source);
    for (final layer in _layers) {
      for (final value in layer['elements'] as List? ?? const []) {
        final element = value as Map;
        if (element['type'] == 'image') {
          final id = element['assetId'] as String?;
          if (id != null) ids.add(id);
        }
      }
    }
    final old = Map<String, ui.Image>.from(_images);
    for (final id in ids) {
      if (old.containsKey(id)) continue;
      try {
        final asset = await state.getAsset(doc['id'] as String, id);
        final bytes = base64Decode(asset['base64'] as String);
        final image = await _decodeImage(bytes);
        _images[id] = image;
      } catch (_) {
        // Missing assets are rendered as placeholders by the canvas.
      }
    }
    for (final entry in old.entries) {
      if (!ids.contains(entry.key)) {
        entry.value.dispose();
        _images.remove(entry.key);
      }
    }
    if (mounted) setState(() {});
  }

  Future<ui.Image> _decodeImage(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _pushUndo() {
    final doc = _doc;
    if (doc == null) return;
    _undo.add(jsonEncode(doc));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _mutate(void Function() action) {
    if (_doc == null) return;
    _pushUndo();
    action();
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final generation = ++_saveGeneration;
    setState(() => _saveState = _SaveState.saving);
    _saveTimer = Timer(const Duration(milliseconds: 350), () async {
      final doc = _doc;
      if (doc == null) return;
      try {
        await state.saveDocument(doc);
        if (mounted && generation == _saveGeneration) {
          setState(() => _saveState = _SaveState.saved);
        }
      } catch (error) {
        if (mounted) {
          setState(() => _saveState = _SaveState.failed);
          _message('保存失败: $error', error: true);
        }
      }
    });
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    final doc = _doc;
    if (doc == null) return;
    try {
      await state.saveDocument(doc);
      if (mounted) setState(() => _saveState = _SaveState.saved);
    } catch (error) {
      if (mounted) setState(() => _saveState = _SaveState.failed);
    }
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final current = jsonEncode(_doc);
    final previous = jsonDecode(_undo.removeLast()) as Map<String, dynamic>;
    _redo.add(current);
    state.setActiveDocument(previous);
    _pageIndex = 0;
    _activeLayerId = _layers.isEmpty ? null : _layers.first['id'] as String?;
    _loadPageImages();
    _scheduleSave();
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    final current = jsonEncode(_doc);
    final next = jsonDecode(_redo.removeLast()) as Map<String, dynamic>;
    _undo.add(current);
    state.setActiveDocument(next);
    _pageIndex = 0;
    _activeLayerId = _layers.isEmpty ? null : _layers.first['id'] as String?;
    _loadPageImages();
    _scheduleSave();
  }

  Future<void> _setPage(int index) async {
    if (index < 0 || index >= (_doc!['pages'] as List).length) return;
    await _flushSave();
    setState(() {
      _pageIndex = index;
      _activeLayerId = _layers.isEmpty ? null : _layers.first['id'] as String?;
    });
    await _loadPageImages();
  }

  void _addStroke(
    List<Offset> points,
    List<double> pressures,
    bool highlighter,
  ) {
    final layer = _activeLayer;
    if (layer == null) return;
    if (layer['locked'] == true) {
      _message('当前图层已锁定');
      return;
    }
    _mutate(() {
      (layer['elements'] as List).add({
        'id': 'stroke_${DateTime.now().microsecondsSinceEpoch}',
        'type': 'stroke',
        'color': _hexColor(_color),
        'width': _width,
        'opacity': 1.0,
        'highlighter': highlighter,
        'points': [
          for (var i = 0; i < points.length; i++)
            [
              points[i].dx,
              points[i].dy,
              pressures.length > i ? pressures[i] : 1.0,
            ],
        ],
      });
    });
  }

  void _eraseAt(Offset point) {
    final layer = _activeLayer;
    if (layer == null || layer['locked'] == true) return;
    final elements = layer['elements'] as List;
    final removed = <int>[];
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i] as Map;
      if (element['type'] != 'stroke') continue;
      final points = element['points'] as List? ?? const [];
      var hit = false;
      for (final value in points) {
        final p = value as List;
        final dx = (p[0] as num).toDouble() - point.dx;
        final dy = (p[1] as num).toDouble() - point.dy;
        if (dx * dx + dy * dy < 100) {
          hit = true;
          break;
        }
      }
      if (hit) removed.add(i);
    }
    if (removed.isEmpty) return;
    _pushUndo();
    for (final index in removed.reversed) {
      elements.removeAt(index);
    }
    setState(() {});
    _scheduleSave();
  }

  Future<String?> _markdownDialog(String initial, String title) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final wide = MediaQuery.sizeOf(context).width > 760;
          final source = TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Markdown 源码',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setDialogState(() {}),
          );
          final preview = Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: controller.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              ),
            ),
          );
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: wide ? 760 : 360,
              height: 440,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: source),
                        const SizedBox(width: 12),
                        Expanded(child: preview),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: source),
                        const SizedBox(height: 10),
                        Expanded(child: preview),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addTextBox() async {
    final text = await _markdownDialog('', '插入文本框');
    if (text == null || text.trim().isEmpty) return;
    final layer = _activeLayer;
    if (layer == null) return;
    final pageWidth = (_page['width'] as num?)?.toDouble() ?? 595;
    _mutate(() {
      (layer['elements'] as List).add({
        'id': 'text_${DateTime.now().microsecondsSinceEpoch}',
        'type': 'text',
        'x': 64.0,
        'y': 64.0,
        'w': (pageWidth - 128).clamp(160.0, 360.0),
        'h': 160.0,
        'markdown': text,
        'fontSize': 16.0,
        'lineHeight': 1.5,
        'color': _hexColor(_color),
        'align': 'left',
        'opacity': 1.0,
        'locked': false,
      });
    });
  }

  Future<void> _editBody() async {
    if ((_page['isNotePage'] as bool?) == false) {
      _message('书籍源页不允许正文文本');
      return;
    }
    final existing = _page['body'] as Map?;
    final text = await _markdownDialog(
      existing?['markdown'] as String? ?? '',
      existing == null ? '添加正文' : '编辑正文',
    );
    if (text == null) return;
    final pageWidth = (_page['width'] as num?)?.toDouble() ?? 595;
    final pageHeight = (_page['height'] as num?)?.toDouble() ?? 842;
    _mutate(() {
      _page['body'] = {
        'id':
            existing?['id'] ?? 'body_${DateTime.now().microsecondsSinceEpoch}',
        'type': 'text',
        'layoutMode': 'body',
        'x': 48.0,
        'y': 48.0,
        'w': _doc!['kind'] == 'infinite' ? 720.0 : pageWidth - 96,
        'h': pageHeight - 96,
        'markdown': text,
        'fontSize': 16.0,
        'lineHeight': 1.5,
        'color': '#222222',
        'align': 'left',
        'opacity': 1.0,
        'locked': false,
      };
    });
  }

  Future<void> _addImage() async {
    const typeGroup = XTypeGroup(
      label: '图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final mime = _mimeFor(file.path);
    final asset = await state.addAsset(_doc!['id'] as String, file.path, mime);
    final image = await _decodeImage(bytes);
    _images[asset['id'] as String] = image;
    final layer = _activeLayer;
    if (layer == null) return;
    final pageWidth = (_page['width'] as num?)?.toDouble() ?? 595;
    final targetWidth = (pageWidth * 0.55).clamp(120.0, 420.0);
    final targetHeight = targetWidth * image.height / image.width;
    _mutate(() {
      (layer['elements'] as List).add({
        'id': 'image_${DateTime.now().microsecondsSinceEpoch}',
        'type': 'image',
        'assetId': asset['id'],
        'x': (pageWidth - targetWidth) / 2,
        'y': 80.0,
        'w': targetWidth,
        'h': targetHeight,
        'rotation': 0.0,
        'opacity': 1.0,
        'locked': false,
      });
    });
    setState(() {});
  }

  Future<void> _addAttachment() async {
    final file = await openFile();
    if (file == null) return;
    final asset = await state.addAsset(
      _doc!['id'] as String,
      file.path,
      _mimeFor(file.path),
    );
    final layer = _activeLayer;
    if (layer == null) return;
    _mutate(() {
      (layer['elements'] as List).add({
        'id': 'attachment_${DateTime.now().microsecondsSinceEpoch}',
        'type': 'attachment',
        'assetId': asset['id'],
        'name': asset['name'],
        'mime': asset['mime'],
        'size': asset['size'],
        'x': 64.0,
        'y': 120.0,
        'w': 260.0,
        'h': 52.0,
        'opacity': 1.0,
        'locked': false,
      });
    });
  }

  Future<void> _onElementTap(Map<String, dynamic> picked) async {
    final id = picked['id'] as String?;
    Map<String, dynamic>? element;
    for (final layer in _layers) {
      for (final value in layer['elements'] as List? ?? const []) {
        final candidate = value as Map<String, dynamic>;
        if (candidate['id'] == id) {
          element = candidate;
          break;
        }
      }
      if (element != null) break;
    }
    if (element == null) return;
    if (element['type'] == 'text') {
      final text = await _markdownDialog(
        element['markdown'] as String? ?? '',
        '编辑文本',
      );
      if (text == null) return;
      _mutate(() {
        element!['markdown'] = text;
      });
      return;
    }
    if (element['type'] == 'attachment') {
      await _showAttachment(element);
      return;
    }
    if (element['type'] == 'image') {
      _message('图片元素：${element['assetId']}');
    }
  }

  Future<void> _showAttachment(Map<String, dynamic> element) async {
    final size = (element['size'] as num?)?.toInt() ?? 0;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(element['name'] as String? ?? '附件'),
        content: Text(
          '类型: ${element['mime'] ?? '未知'}\n大小: ${(size / 1024).toStringAsFixed(1)} KiB\n\n'
          '首版不在应用内预览附件。可用系统应用打开。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _openAttachmentExternally(element);
            },
            child: const Text('用系统应用打开'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAttachmentExternally(Map<String, dynamic> element) async {
    try {
      final asset = await state.getAsset(
        _doc!['id'] as String,
        element['assetId'] as String,
      );
      final bytes = base64Decode(asset['base64'] as String);
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/${element['name'] ?? 'attachment'}');
      await file.writeAsBytes(bytes);
      if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      } else {
        _message('当前平台暂不支持系统打开');
      }
    } catch (error) {
      _message('打开附件失败: $error', error: true);
    }
  }

  void _addLayer() {
    final layers = _layersRaw;
    if (layers.length >= 5) {
      _message('每页最多 5 个图层');
      return;
    }
    final id = 'layer_${DateTime.now().microsecondsSinceEpoch}';
    _mutate(() {
      layers.add({
        'id': id,
        'name': '图层 ${layers.length + 1}',
        'visible': true,
        'locked': false,
        'opacity': 1.0,
        'elements': <dynamic>[],
      });
      _activeLayerId = id;
    });
  }

  void _deleteLayer() {
    final layers = _layersRaw;
    if (layers.length <= 1) {
      _message('至少保留一个图层');
      return;
    }
    final index = _layers.indexWhere((layer) => layer['id'] == _activeLayerId);
    if (index < 0) return;
    _mutate(() {
      layers.removeAt(index);
      _activeLayerId =
          (layers[mathMin(index, layers.length - 1)] as Map)['id'] as String?;
    });
  }

  int mathMin(int a, int b) => a < b ? a : b;

  void _moveLayer(int delta) {
    final layers = _layersRaw;
    final index = _layers.indexWhere((layer) => layer['id'] == _activeLayerId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= layers.length) return;
    _mutate(() {
      final layer = layers.removeAt(index);
      layers.insert(target, layer);
    });
  }

  void _toggleLayer(String key) {
    final layer = _activeLayer;
    if (layer == null) return;
    _mutate(() => layer[key] = !(layer[key] == true));
  }

  void _setLayerOpacity(double value) {
    final layer = _activeLayer;
    if (layer == null) return;
    _mutate(() => layer['opacity'] = value);
  }

  Future<void> _addPage() async {
    await _flushSave();
    final pageWidth = (_page['width'] as num?)?.toDouble() ?? 595;
    final pageHeight = (_page['height'] as num?)?.toDouble() ?? 842;
    final page = {
      'id': 'page_${DateTime.now().microsecondsSinceEpoch}',
      'sourceIndex': null,
      'sourceAssetId': null,
      'isNotePage': true,
      'width': pageWidth,
      'height': pageHeight,
      'layers': [
        {
          'id': 'layer_${DateTime.now().microsecondsSinceEpoch}',
          'name': '图层 1',
          'visible': true,
          'locked': false,
          'opacity': 1.0,
          'elements': <dynamic>[],
        },
      ],
      'body': null,
    };
    _mutate(() {
      (_doc!['pages'] as List).insert(_pageIndex + 1, page);
      _pageIndex += 1;
      _activeLayerId = (page['layers'] as List).first['id'] as String;
    });
    await _loadPageImages();
  }

  Future<void> _deletePage() async {
    final pages = _doc!['pages'] as List;
    if (pages.length <= 1) {
      _message('至少保留一页');
      return;
    }
    if ((_page['isNotePage'] as bool?) == false) {
      _message('书籍源页不能删除');
      return;
    }
    await _flushSave();
    _mutate(() {
      pages.removeAt(_pageIndex);
      if (_pageIndex >= pages.length) _pageIndex = pages.length - 1;
      _activeLayerId = _layers.isEmpty ? null : _layers.first['id'] as String?;
    });
    await _loadPageImages();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(
      text: _doc!['title'] as String? ?? '',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名文档'),
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
      final title = controller.text.trim().isEmpty
          ? '未命名'
          : controller.text.trim();
      _mutate(() => _doc!['title'] = title);
      await _flushSave();
    }
    controller.dispose();
  }

  Future<void> _exportMeowo() async {
    final title = (_doc!['title'] as String? ?? '未命名').replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final location = await getSaveLocation(suggestedName: '$title.meowo');
    if (location == null) return;
    try {
      final path = await state.exportDocument(
        _doc!['id'] as String,
        location.path,
      );
      _message('已导出到 $path');
    } catch (error) {
      _message('导出失败: $error', error: true);
    }
  }

  Future<void> _exportPdf() async {
    final doc = _doc;
    if (doc == null) return;
    final pages = doc['pages'] as List;
    final allPages = doc['kind'] != 'infinite' && pages.length > 1;
    bool exportAll = false;
    if (allPages) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出 PDF'),
          content: const Text('选择导出范围。PDF 会按当前页面顺序保留源页与笔记页。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('仅当前页'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('全部页面'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      exportAll = choice;
    }
    final title = (doc['title'] as String? ?? '未命名').replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final location = await getSaveLocation(suggestedName: '$title.pdf');
    if (location == null) return;
    _message(exportAll ? '正在导出全部页面 PDF…' : '正在导出 PDF…');
    try {
      final pdf = pw.Document();
      final indexes = exportAll
          ? List<int>.generate(pages.length, (index) => index)
          : <int>[_pageIndex];
      for (final index in indexes) {
        final page = pages[index] as Map<String, dynamic>;
        final images = await _imagesForPage(page);
        try {
          final width = (page['width'] as num?)?.toDouble() ?? 595.276;
          final height = (page['height'] as num?)?.toDouble() ?? 841.89;
          final png = await renderPagePng(
            document: doc,
            page: page,
            images: images,
            pixelRatio: 2.0,
          );
          final image = pw.MemoryImage(png);
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(width, height, marginAll: 0),
              build: (context) => pw.Image(image, fit: pw.BoxFit.fill),
            ),
          );
        } finally {
          for (final image in images.values) {
            image.dispose();
          }
        }
      }
      final bytes = await pdf.save();
      await File(location.path).writeAsBytes(bytes);
      _message('PDF 已导出（${indexes.length} 页）');
    } catch (error) {
      _message('PDF 导出失败: $error', error: true);
    }
  }

  Future<Map<String, ui.Image>> _imagesForPage(
    Map<String, dynamic> page,
  ) async {
    final ids = <String>{};
    final source = page['sourceAssetId'] as String?;
    if (source != null) ids.add(source);
    for (final value in page['layers'] as List? ?? const []) {
      final layer = value as Map;
      for (final elementValue in layer['elements'] as List? ?? const []) {
        final element = elementValue as Map;
        if (element['type'] == 'image') {
          final id = element['assetId'] as String?;
          if (id != null) ids.add(id);
        }
      }
    }
    final images = <String, ui.Image>{};
    for (final id in ids) {
      try {
        final asset = await state.getAsset(_doc!['id'] as String, id);
        final bytes = base64Decode(asset['base64'] as String);
        images[id] = await _decodeImage(bytes);
      } catch (_) {
        // Missing assets render as placeholders in the PDF as well.
      }
    }
    return images;
  }

  Future<void> _exportPng() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final title = (_doc!['title'] as String? ?? '未命名').replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final location = await getSaveLocation(
        suggestedName: '$title-page-${_pageIndex + 1}.png',
      );
      if (location == null) return;
      await File(location.path).writeAsBytes(data.buffer.asUint8List());
      _message('已导出 PNG');
    } catch (error) {
      _message('PNG 导出失败: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _doc == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final media = MediaQuery.sizeOf(context);
    final wide = media.width >= 1040;
    final compact = media.width < 760;
    return Column(
      children: [
        _topBar(context, wide, compact),
        Expanded(
          child: Row(
            children: [
              _toolRail(context),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CanvasView(
                      document: _doc!,
                      page: _page,
                      tool: _tool,
                      color: _color,
                      width: _width,
                      activeLayerId: _activeLayerId ?? '',
                      images: _images,
                      onStroke: _addStroke,
                      onErase: _eraseAt,
                      onElementTap: (element) {
                        _tool = 'select';
                        setState(() {});
                        _onElementTap(element);
                      },
                    ),
                  ),
                ),
              ),
              if (wide) _layersPanel(context),
            ],
          ),
        ),
        _pageBar(context),
      ],
    );
  }

  Widget _topBar(BuildContext context, bool wide, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (_saveState) {
      _SaveState.saved => const _SaveIndicator(
        icon: Icons.cloud_done_outlined,
        text: '已保存',
      ),
      _SaveState.saving => const _SaveIndicator(icon: Icons.sync, text: '保存中'),
      _SaveState.failed => _SaveIndicator(
        icon: Icons.error_outline,
        text: '保存失败',
        color: scheme.error,
      ),
    };
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回资料库',
                onPressed: state.showLibrary,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _rename,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      _doc!['title'] as String? ?? '未命名',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              status,
              const SizedBox(width: 8),
              if (!compact) ...[
                IconButton(
                  tooltip: '撤销',
                  onPressed: _undo.isEmpty ? null : _undoLast,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: _redo.isEmpty ? null : _redoLast,
                  icon: const Icon(Icons.redo),
                ),
              ],
              if (!wide)
                IconButton(
                  tooltip: '图层',
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (context) => _LayersSheet(
                      layers: _layers,
                      activeLayerId: _activeLayerId,
                      onSelect: (id) => setState(() => _activeLayerId = id),
                      onAdd: _addLayer,
                      onDelete: _deleteLayer,
                      onToggleVisible: () => _toggleLayer('visible'),
                      onToggleLock: () => _toggleLayer('locked'),
                      onOpacity: _setLayerOpacity,
                      onMove: _moveLayer,
                    ),
                  ),
                  icon: const Icon(Icons.layers_outlined),
                ),
              PopupMenuButton<String>(
                tooltip: '导出',
                onSelected: (value) {
                  if (value == 'meowo') _exportMeowo();
                  if (value == 'png') _exportPng();
                  if (value == 'pdf') _exportPdf();
                  if (value == 'undo') _undoLast();
                  if (value == 'redo') _redoLast();
                },
                itemBuilder: (context) => [
                  if (compact) ...[
                    PopupMenuItem(
                      value: 'undo',
                      enabled: _undo.isNotEmpty,
                      child: const Text('撤销'),
                    ),
                    PopupMenuItem(
                      value: 'redo',
                      enabled: _redo.isNotEmpty,
                      child: const Text('重做'),
                    ),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(
                    value: 'meowo',
                    child: Text('导出 .meowo 快照'),
                  ),
                  const PopupMenuItem(value: 'png', child: Text('导出当前页 PNG')),
                  const PopupMenuItem(value: 'pdf', child: Text('导出 PDF')),
                ],
                icon: const Icon(Icons.ios_share),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolRail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tools = <(String, IconData, String)>[
      ('select', Icons.near_me_outlined, '选择'),
      ('pen', Icons.edit_outlined, '笔'),
      ('highlighter', Icons.brush_outlined, '荧光笔'),
      ('eraser', Icons.auto_fix_normal, '橡皮'),
      ('text', Icons.title, '文本框'),
      ('body', Icons.notes, '正文'),
      ('image', Icons.image_outlined, '图片'),
      ('attachment', Icons.attach_file, '附件'),
    ];
    return Material(
      color: scheme.surface,
      child: Container(
        width: 64,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    for (final tool in tools)
                      _ToolButton(
                        icon: tool.$2,
                        label: tool.$3,
                        selected: _tool == tool.$1,
                        onTap: () {
                          if (tool.$1 == 'text') {
                            _addTextBox();
                          } else if (tool.$1 == 'body') {
                            _editBody();
                          } else if (tool.$1 == 'image') {
                            _addImage();
                          } else if (tool.$1 == 'attachment') {
                            _addAttachment();
                          } else {
                            setState(() {
                              _tool = tool.$1;
                              if (_tool == 'highlighter') _width = 14;
                              if (_tool == 'pen') _width = 2.5;
                            });
                          }
                        },
                      ),
                    const Divider(height: 18),
                    _ColorButton(color: _color, onTap: _chooseColor),
                    const SizedBox(height: 6),
                    RotatedBox(
                      quarterTurns: 3,
                      child: SizedBox(
                        width: 72,
                        child: Slider(
                          value: _width.clamp(1, 24),
                          min: 1,
                          max: 24,
                          onChanged: (value) => setState(() => _width = value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '重置视图',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.fit_screen_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseColor() async {
    const colors = [
      Color(0xFF2B2A27),
      Color(0xFFB3261E),
      Color(0xFFB4692A),
      Color(0xFF2E6B4F),
      Color(0xFF275D8C),
      Color(0xFF6B4C9A),
      Color(0xFFD8A21B),
      Color(0xFF9E9E9E),
    ];
    final value = await showDialog<Color>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('笔迹颜色'),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in colors)
                InkWell(
                  onTap: () => Navigator.pop(context, color),
                  child: CircleAvatar(backgroundColor: color, radius: 18),
                ),
            ],
          ),
        ],
      ),
    );
    if (value != null) setState(() => _color = value);
  }

  Widget _layersPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: _LayersSheet(
        layers: _layers,
        activeLayerId: _activeLayerId,
        onSelect: (id) => setState(() => _activeLayerId = id),
        onAdd: _addLayer,
        onDelete: _deleteLayer,
        onToggleVisible: () => _toggleLayer('visible'),
        onToggleLock: () => _toggleLayer('locked'),
        onOpacity: _setLayerOpacity,
        onMove: _moveLayer,
      ),
    );
  }

  Widget _pageBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = _doc!['pages'] as List;
    final isBook = _doc!['kind'] == 'book';
    final isInfinite = _doc!['kind'] == 'infinite';
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 12),
            IconButton(
              tooltip: '上一页',
              onPressed: _pageIndex > 0 ? () => _setPage(_pageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              isInfinite ? '无极画布' : '第 ${_pageIndex + 1} / ${pages.length} 页',
            ),
            IconButton(
              tooltip: '下一页',
              onPressed: _pageIndex + 1 < pages.length
                  ? () => _setPage(_pageIndex + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            if (!isInfinite) ...[
              const SizedBox(width: 10),
              IconButton(
                tooltip: '插入一页',
                onPressed: _addPage,
                icon: const Icon(Icons.add_box_outlined),
              ),
              IconButton(
                tooltip: '删除当前页',
                onPressed: _deletePage,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
            const Spacer(),
            if (isBook && !compact)
              Text(
                '源页只读 · 可插入笔记页',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            if (!compact) ...[
              const SizedBox(width: 16),
              Text(
                '${(_page['width'] as num?)?.toStringAsFixed(0)} × ${(_page['height'] as num?)?.toStringAsFixed(0)} pt',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  String _hexColor(Color color) {
    final value = color.toARGB32();
    return '#${value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    return 'application/octet-stream';
  }
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(width: 48, height: 40, child: Icon(icon, size: 21)),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '颜色',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}

class _LayersSheet extends StatelessWidget {
  const _LayersSheet({
    required this.layers,
    required this.activeLayerId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onToggleVisible,
    required this.onToggleLock,
    required this.onOpacity,
    required this.onMove,
  });

  final List<Map<String, dynamic>> layers;
  final String? activeLayerId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLock;
  final ValueChanged<double> onOpacity;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Map<String, dynamic>? active;
    for (final layer in layers) {
      if (layer['id'] == activeLayerId) {
        active = layer;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('图层', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                tooltip: '新建图层',
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 20),
              ),
              IconButton(
                tooltip: '删除图层',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final layer in layers.reversed)
                  Material(
                    color: layer['id'] == activeLayerId
                        ? scheme.secondaryContainer.withValues(alpha: 0.55)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onSelect(layer['id'] as String),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed: layer['id'] == activeLayerId
                                  ? onToggleVisible
                                  : null,
                              icon: Icon(
                                layer['visible'] == false
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed: layer['id'] == activeLayerId
                                  ? onToggleLock
                                  : null,
                              icon: Icon(
                                layer['locked'] == true
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                layer['name'] as String? ?? '图层',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (layer['id'] == activeLayerId) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 17,
                                onPressed: () => onMove(1),
                                icon: const Icon(Icons.keyboard_arrow_up),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 17,
                                onPressed: () => onMove(-1),
                                icon: const Icon(Icons.keyboard_arrow_down),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (active != null) ...[
            const Divider(height: 18),
            Text(
              '不透明度 ${((active['opacity'] as num?)?.toDouble() ?? 1.0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: (active['opacity'] as num?)?.toDouble() ?? 1.0,
              onChanged: onOpacity,
            ),
          ],
        ],
      ),
    );
  }
}
