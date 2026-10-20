import 'package:flutter/material.dart';

/// Attachment list for the current document.
///
/// Attachments are embedded in the `.meowo` file and are never previewed
/// inside the app. Opening is delegated to the platform's external app.
class AttachmentPanel extends StatefulWidget {
  const AttachmentPanel({
    super.key,
    required this.load,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  final Future<List<Map<String, dynamic>>> Function() load;
  final Future<void> Function() onAdd;
  final Future<void> Function(Map<String, dynamic> asset) onOpen;
  final Future<void> Function(String assetId) onDelete;

  @override
  State<AttachmentPanel> createState() => _AttachmentPanelState();
}

class _AttachmentPanelState extends State<AttachmentPanel> {
  List<Map<String, dynamic>> _assets = const [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assets = await widget.load();
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd();
      await _reload();
    } catch (error) {
      _showError('添加附件失败: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> asset) async {
    try {
      await widget.onOpen(asset);
    } catch (error) {
      _showError('打开附件失败: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> asset) async {
    final id = asset['id'] as String?;
    if (id == null) return;
    if (asset['referenced'] == true) {
      final references = (asset['references'] as List? ?? const [])
          .map((value) => '• $value')
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('附件仍被引用'),
          content: Text(
            references.isEmpty
                ? '该附件仍被文档引用，无法删除。'
                : '该附件仍被以下位置引用，无法删除：\n\n$references',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete(id);
      await _reload();
    } catch (error) {
      _showError('删除附件失败: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.attach_file_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '附件',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '添加附件',
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text('加载附件失败\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_assets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file, size: 40),
              const SizedBox(height: 12),
              const Text('暂无附件'),
              const SizedBox(height: 4),
              Text(
                '附件会嵌入文档，只能用系统应用打开。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('添加附件'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _assets.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final asset = _assets[index];
        final referenced = asset['referenced'] == true;
        final references = (asset['references'] as List? ?? const []);
        return ListTile(
          leading: CircleAvatar(
            child: Icon(_iconFor(asset['mime'] as String?)),
          ),
          title: Text(
            asset['name'] as String? ?? '未命名附件',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              _formatBytes(asset['size']),
              asset['mime'] as String? ?? '未知类型',
              if (referenced)
                '引用 ${asset['referenceCount'] ?? references.length} 处'
              else
                '未引用',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '用系统应用打开',
                onPressed: () => _open(asset),
                icon: const Icon(Icons.open_in_new),
              ),
              IconButton(
                tooltip: referenced ? '仍被引用，不能删除' : '删除附件',
                onPressed: _busy ? null : () => _delete(asset),
                icon: Icon(
                  referenced ? Icons.lock_outline : Icons.delete_outline,
                ),
              ),
            ],
          ),
          onTap: () => _open(asset),
        );
      },
    );
  }

  static IconData _iconFor(String? mime) {
    if (mime == null) return Icons.insert_drive_file_outlined;
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mime.startsWith('video/')) return Icons.video_file_outlined;
    if (mime.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _formatBytes(dynamic value) {
    final bytes = value is num ? value.toDouble() : 0;
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
