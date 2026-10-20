import 'dart:math' as math;

/// Helpers shared by the vector PDF export UI and tests. Keeping them free of
/// Flutter bindings makes the range/filename/report rules easy to verify.

String sanitizePdfTitle(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? '未命名' : cleaned;
}

/// `<书名>-annotated-YYYYMMDD.pdf`
String annotatedPdfFileName(String title, DateTime date) {
  final stamp =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
  return '${sanitizePdfTitle(title)}-annotated-$stamp.pdf';
}

/// Parses a 1-based page range such as `1-3, 5, 8–9` into sorted 0-based
/// document page indexes. Throws [FormatException] for invalid/out-of-range
/// input so the dialog can show an inline error instead of silently clipping.
List<int> parsePageRange(String input, int pageCount) {
  if (pageCount <= 0) throw const FormatException('文档没有可导出的页面');
  final text = input
      .replaceAll('，', ',')
      .replaceAll('；', ',')
      .replaceAll(';', ',')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .trim();
  if (text.isEmpty) throw const FormatException('请输入页面范围，例如 1-3, 5');
  final selected = <int>{};
  for (final raw in text.split(',')) {
    final token = raw.trim();
    if (token.isEmpty) throw const FormatException('页面范围包含空项');
    final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(token);
    if (match == null) throw FormatException('无法识别页面范围: $token');
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2) ?? match.group(1)!);
    if (start < 1 || end < 1) throw const FormatException('页码从 1 开始');
    if (start > end) throw FormatException('范围起点大于终点: $token');
    if (end > pageCount) {
      throw FormatException('页码超出范围: $end（共 $pageCount 页）');
    }
    for (var page = start; page <= end; page++) {
      selected.add(page - 1);
    }
  }
  final result = selected.toList()..sort();
  if (result.isEmpty) throw const FormatException('请选择至少一页');
  return result;
}

/// Compacts 1-based page numbers into `1–3, 5, 8–9` for the export report.
String compactPageRanges(Iterable<int> pages) {
  final sorted = pages.toSet().toList()..sort();
  if (sorted.isEmpty) return '无';
  final parts = <String>[];
  var start = sorted.first;
  var end = start;
  for (var i = 1; i < sorted.length; i++) {
    final value = sorted[i];
    if (value == end + 1) {
      end = value;
      continue;
    }
    parts.add(start == end ? '$start' : '$start–$end');
    start = value;
    end = value;
  }
  parts.add(start == end ? '$start' : '$start–$end');
  return parts.join(', ');
}

bool _isRasterElement(Map element) {
  final type = element['type'];
  return type == 'text' || type == 'image' || type == 'attachment';
}

/// True when a page has any visible element that must be rasterized into the
/// transparent overlay PNG. Ink/highlighter are intentionally excluded.
bool pageHasRasterOverlay(Map<String, dynamic> page) {
  final body = page['body'];
  if (body is Map && _isRasterElement(body)) return true;
  for (final value in page['layers'] as List? ?? const []) {
    if (value is! Map) continue;
    if (value['visible'] == false) continue;
    final opacity = (value['opacity'] as num?)?.toDouble() ?? 1.0;
    if (opacity <= 0.01) continue;
    for (final element in value['elements'] as List? ?? const []) {
      if (element is Map && _isRasterElement(element)) return true;
    }
  }
  return false;
}

String fallbackReasonLabel(String reason) {
  return switch (reason) {
    'missing_book_source' => '旧文档没有可用的原始 PDF',
    'epub_fixed_page' => 'EPUB 固定页使用 PNG 快照',
    'encrypted_pdf_no_password' => '加密 PDF 的密码未保存',
    'source_not_pdf' => '书籍源不是 PDF',
    'source_page_out_of_range' => '源页面索引超出 PDF 页数',
    'missing_source_index' => '页面缺少源 PDF 索引',
    'vector_render_failed' => '矢量渲染失败',
    'missing_page_bitmap' => '缺少 PNG 回退位图',
    _ => reason,
  };
}

class PdfExportEstimate {
  const PdfExportEstimate({
    required this.estimatedBytes,
    required this.estimatedSeconds,
  });

  final int estimatedBytes;
  final double estimatedSeconds;

  bool get warns =>
      estimatedBytes > 200 * 1024 * 1024 || estimatedSeconds > 120;
}

/// Heuristic only: source PDF bytes prorated to selected source pages, plus a
/// conservative raster-overlay allowance. The soft warning threshold is
/// 200 MB or 2 minutes.
PdfExportEstimate estimatePdfExport(
  Map<String, dynamic> document,
  List<int> pageIndexes,
) {
  final pages = document['pages'] as List? ?? const [];
  final book = document['bookSource'];
  var sourceBytes = 0;
  final totalSourcePages = book is Map
      ? ((book['pageCount'] as num?)?.toInt() ?? 0)
      : 0;
  var selectedSourcePages = 0;
  for (final index in pageIndexes) {
    if (index < 0 || index >= pages.length) continue;
    final page = pages[index] as Map;
    if (page['isNotePage'] != true) selectedSourcePages++;
  }
  for (final asset in document['assets'] as List? ?? const []) {
    if (asset is Map && asset['kind'] == 'book_source') {
      sourceBytes += (asset['size'] as num?)?.toInt() ?? 0;
    }
  }
  final sourcePart = totalSourcePages > 0
      ? sourceBytes * selectedSourcePages / totalSourcePages
      : sourceBytes.toDouble();
  final overlayPart = pageIndexes.length * 1_500_000.0;
  final estimatedBytes = (sourcePart * 1.35 + overlayPart + 100000).round();
  final seconds = 0.6 * pageIndexes.length + selectedSourcePages * 0.8;
  return PdfExportEstimate(
    estimatedBytes: math.max(0, estimatedBytes),
    estimatedSeconds: seconds,
  );
}

class PdfExportProgress {
  const PdfExportProgress({
    required this.phase,
    required this.completed,
    required this.total,
    this.pageNumber = 0,
  });

  final String phase;
  final int completed;
  final int total;
  final int pageNumber;

  double? get fraction => total > 0 ? completed / total : null;

  factory PdfExportProgress.fromJson(Map<String, dynamic> json) {
    return PdfExportProgress(
      phase: json['phase'] as String? ?? 'exporting',
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
    );
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
