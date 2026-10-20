#pragma once

#include <string>
#include <vector>

namespace meowo {

struct MuPdfPage {
  double width = 0;
  double height = 0;
};

struct MuPdfResult {
  bool ok = false;
  std::string error;
  int pageCount = 0;
  std::vector<MuPdfPage> pages;
  std::string title;
  std::string author;
  std::string format;
  std::string version;
};

// Renders a PDF or EPUB to page-0001.png ... in outputDir using MuPDF.
// The caller owns outputDir and must clean it up. Text is written alongside
// each page as page-0001.txt. MuPDF uses longjmp internally; this function
// keeps C++ objects outside fz_try to keep the boundary safe.
MuPdfResult render_with_mupdf(const std::string& sourcePath,
                              const std::string& outputDir,
                              const std::string& password,
                              int maxPages);

}  // namespace meowo
