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
  // True when the document required a password. Passwords are never
  // persisted, so encrypted books keep their PNG page snapshots.
  bool encrypted = false;
};

struct MuPdfVectorPage {
  bool ok = false;
  std::string error;
  int pageIndex = -1;
  double width = 0;
  double height = 0;
  std::string svg;
};

struct MuPdfProbe {
  bool ok = false;
  std::string error;
  int pageCount = 0;
  bool encrypted = false;
  std::string title;
  std::string author;
  std::string format;
};

// Opens a PDF/EPUB and counts pages without rendering; used for the >500-page
// import warning before the full import job starts.
MuPdfProbe probe_with_mupdf(const std::string& sourcePath,
                            const std::string& password);

// Renders selected pages of an in-memory PDF to standalone SVG documents.
// Glyph <use> references are inlined because Flutter's SVG compiler rejects
// more than 1000 reference expansions per document.
std::vector<MuPdfVectorPage> render_pdf_pages_svg(
    const std::string& pdfBytes, const std::vector<int>& pageIndexes);

// Renders a PDF or EPUB to page-0001.png ... in outputDir using MuPDF.
// The caller owns outputDir and must clean it up. Text is written alongside
// each page as page-0001.txt. MuPDF uses longjmp internally; this function
// keeps C++ objects outside fz_try to keep the boundary safe.
MuPdfResult render_with_mupdf(const std::string& sourcePath,
                              const std::string& outputDir,
                              const std::string& password, int maxPages,
                              const std::string& progressPath = "");

}  // namespace meowo
