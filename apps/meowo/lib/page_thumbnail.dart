import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Caches rendered page thumbnails by page id.
///
/// Requests for the same page share one in-flight future. [clear] bumps an
/// internal generation so a render that finishes after the content changed
/// cannot repopulate stale bytes.
class PageThumbnailCache {
  final Map<String, Uint8List> _ready = {};
  final Map<String, Future<Uint8List?>> _pending = {};
  Future<void> _serial = Future<void>.value();
  int _generation = 0;

  int get cachedCount => _ready.length;

  Uint8List? peek(String pageId) => _ready[pageId];

  void clear() {
    _generation += 1;
    _ready.clear();
    _pending.clear();
  }

  /// Serializes thumbnail rasterization. `ui.Picture.toImage` must run on the
  /// UI isolate; rendering a grid of previews concurrently causes visible
  /// frame jank, so at most one preview is rendered at a time.
  Future<Uint8List?> _enqueue(Future<Uint8List?> Function() render) {
    final result = _serial.then((_) => render());
    _serial = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Uint8List?> load(String pageId, Future<Uint8List?> Function() render) {
    final cached = _ready[pageId];
    if (cached != null) return Future.value(cached);
    final pending = _pending[pageId];
    if (pending != null) return pending;

    final generation = _generation;
    late final Future<Uint8List?> future;
    future = _enqueue(render)
        .then((bytes) {
          if (bytes != null && generation == _generation) {
            _ready[pageId] = bytes;
          }
          return bytes;
        })
        .whenComplete(() {
          if (identical(_pending[pageId], future)) {
            _pending.remove(pageId);
          }
        });
    _pending[pageId] = future;
    return future;
  }
}

/// Asynchronously renders one page thumbnail with a lightweight placeholder.
///
/// The widget never blocks the surrounding grid: each card starts its own
/// request and swaps its placeholder for the image when the future completes.
class PageThumbnail extends StatefulWidget {
  const PageThumbnail({
    super.key,
    required this.pageId,
    required this.aspectRatio,
    required this.load,
    this.cachedBytes,
    this.placeholder,
  });

  final String pageId;
  final double aspectRatio;
  final Future<Uint8List?> Function() load;
  final Uint8List? cachedBytes;
  final Widget? placeholder;

  @override
  State<PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<PageThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cachedBytes;
    if (_bytes == null) {
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant PageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId) {
      _generation += 1;
      _failed = false;
      _bytes = widget.cachedBytes;
      if (_bytes == null) _start();
      return;
    }
    if (_bytes == null && widget.cachedBytes != null) {
      _bytes = widget.cachedBytes;
      _failed = false;
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    try {
      final bytes = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = bytes == null;
        _bytes = bytes;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return AspectRatio(
      aspectRatio: widget.aspectRatio > 0 ? widget.aspectRatio : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF5),
          border: Border.all(color: const Color(0xFFE0D6C7)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: bytes != null
              ? Image.memory(
                  bytes,
                  key: const ValueKey('page-thumbnail-image'),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) =>
                      _placeholder(failed: true),
                )
              : _placeholder(failed: _failed),
        ),
      ),
    );
  }

  Widget _placeholder({required bool failed}) {
    final background = widget.placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        ?background,
        Center(
          child: failed
              ? const Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: Color(0xFF9A8873),
                )
              : const Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: Color(0xFFB9A58C),
                ),
        ),
      ],
    );
  }
}
