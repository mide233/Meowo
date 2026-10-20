import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A parsed, device-independent PDF page background.
///
/// The SVG is produced by MuPDF from the original PDF at import/open time, so
/// painting this picture stays sharp at any zoom instead of upscaling a
/// fixed-DPI snapshot.
class BookVectorPage {
  BookVectorPage._(this.picture, this.size);

  final ui.Picture picture;
  final Size size;

  void dispose() {
    picture.dispose();
  }
}

/// Parses one page of SVG. Returns null when the document uses an SVG feature
/// that flutter_svg cannot compile; callers keep the PNG fallback.
Future<BookVectorPage?> loadBookVectorPage(String svg) async {
  if (svg.isEmpty) return null;
  try {
    final info = await vg.loadPicture(SvgStringLoader(svg), null);
    if (info.size.isEmpty) {
      info.picture.dispose();
      return null;
    }
    return BookVectorPage._(info.picture, info.size);
  } catch (_) {
    return null;
  }
}

/// Draws a vector page into [rect]. The page box is stretched to the document
/// page bounds, matching the previous `BoxFit.fill` PNG background.
void paintBookVector(Canvas canvas, Rect rect, BookVectorPage page) {
  if (page.size.isEmpty) return;
  canvas.save();
  canvas.clipRect(rect);
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width / page.size.width, rect.height / page.size.height);
  canvas.drawPicture(page.picture);
  canvas.restore();
}

/// Small LRU-ish cache for parsed page pictures. The editor keeps the current
/// page and its neighbours, disposing pictures as pages move out of range.
class BookVectorCache {
  final _pages = <String, BookVectorPage>{};
  final _retired = <String, BookVectorPage>{};
  final _retireTimers = <String, Timer>{};
  final _pending = <String, Future<BookVectorPage?>>{};
  final _unavailable = <String>{};
  int _epoch = 0;

  BookVectorPage? operator [](String key) => _pages[key];

  /// Read-only-ish view used by painters. The map identity is stable; the
  /// background painter compares its length and the current page entry.
  Map<String, BookVectorPage> get pages => _pages;

  bool isUnavailable(String key) => _unavailable.contains(key);

  void markUnavailable(String key) {
    _unavailable.add(key);
  }

  Future<BookVectorPage?> load(String key, String? svg) async {
    final existing = _pages[key];
    if (existing != null) return existing;
    final retired = _retired.remove(key);
    if (retired != null) {
      _retireTimers.remove(key)?.cancel();
      _pages[key] = retired;
      return retired;
    }
    if (svg == null || svg.isEmpty || _unavailable.contains(key)) return null;
    final pending = _pending[key];
    if (pending != null) return pending;
    final epoch = _epoch;
    final future = loadBookVectorPage(svg).then((page) {
      _pending.remove(key);
      if (page == null) {
        if (epoch == _epoch) _unavailable.add(key);
        return null;
      }
      if (epoch != _epoch) {
        page.dispose();
        return null;
      }
      _pages[key] = page;
      return page;
    });
    _pending[key] = future;
    return future;
  }

  /// Drops every picture whose cache key is not in [keep].
  ///
  /// Removal is deferred briefly because a page-slide transition keeps the
  /// outgoing canvas mounted for 240 ms; disposing its picture immediately
  /// would leave the old widget painting a disposed Picture.
  void retain(Set<String> keep) {
    final remove = _pages.keys.where((key) => !keep.contains(key)).toList();
    for (final key in remove) {
      final page = _pages.remove(key);
      if (page == null) continue;
      _retireTimers.remove(key)?.cancel();
      _retired.remove(key)?.dispose();
      _retired[key] = page;
      _retireTimers[key] = Timer(const Duration(milliseconds: 500), () {
        _retireTimers.remove(key);
        _retired.remove(key)?.dispose();
      });
    }
  }

  void dispose() {
    _epoch += 1;
    for (final timer in _retireTimers.values) {
      timer.cancel();
    }
    _retireTimers.clear();
    for (final page in _pages.values) {
      page.dispose();
    }
    for (final page in _retired.values) {
      page.dispose();
    }
    _pages.clear();
    _retired.clear();
    _pending.clear();
    _unavailable.clear();
  }
}
