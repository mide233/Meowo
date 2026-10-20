#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace meowo {

struct ExportStrokePoint {
  double x = 0;
  double y = 0;
  double pressure = 1.0;
};

// A visible stroke translated from the document JSON into the exact values
// needed by the PDF content writer. Coordinates are page points, origin at the
// displayed top-left (the same space Flutter paints in).
struct ExportStroke {
  std::vector<ExportStrokePoint> points;
  uint32_t rgb = 0x222222;
  double width = 2.0;
  bool highlighter = false;
  double opacity = 1.0;
  std::vector<std::pair<double, double>> pressureCurve;
};

struct BookExportPage {
  int pageNumber = 0;         // 1-based document page number
  int documentPageIndex = 0;  // 0-based document page index
  bool notePage = false;
  double width = 0;   // document page width in points
  double height = 0;  // document page height in points
  int sourceIndex = -1;
  bool forceFallback = false;
  std::string fallbackReason;
  std::string fallbackDetail;
  // Loaded lazily so vector exports never copy the per-page PNG fallback.
  std::function<std::string()> loadFallbackPng;
  std::string overlayPath;  // transparent PNG with text/images/attachments
  std::vector<ExportStroke> strokes;
};

struct BookExportRequest {
  std::string targetPath;   // caller supplies a temporary path
  std::string sourcePdf;    // original book_source bytes, empty when absent
  bool sourceEncrypted = false;
  std::vector<BookExportPage> pages;
  std::string progressPath;
  std::string cancelPath;
};

struct BookExportFallback {
  int pageNumber = 0;
  std::string reason;
  std::string detail;
};

struct BookExportResult {
  bool ok = false;
  bool cancelled = false;
  std::string error;
  std::vector<int> exportedPages;
  std::vector<int> vectorPages;
  std::vector<BookExportFallback> fallbackPages;
  std::vector<std::string> warnings;
  size_t outputBytes = 0;
};

// Builds a flattened PDF. Original PDF source pages are rebuilt as vector
// content (text converted to outlines), ink/highlighter strokes are written as
// PDF paths, and only the Dart-rendered raster overlay is embedded as an image.
// Per-page failures fall back to the stored page PNG instead of aborting.
BookExportResult build_book_pdf(const BookExportRequest& request);

}  // namespace meowo
