#include "meowo_core.h"

#include <gtest/gtest.h>
#include <nlohmann/json.hpp>

#ifdef MEOWO_HAS_MUPDF
#include <mupdf/fitz.h>
#include <mupdf/pdf.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace {

// 2x2 PNG: top row red, bottom row blue. Used to assert that exported
// overlays and fallback page bitmaps keep their display orientation.
const unsigned char kTopRedBottomBluePng[] = {
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x14,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x8d, 0x89, 0x1d, 0x0d, 0x00, 0x00, 0x00,
    0x27, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xfc, 0xcf, 0xc0, 0xf0,
    0x9f, 0x81, 0x8a, 0x80, 0x89, 0x9a, 0x86, 0x8d, 0x50, 0x03, 0x47, 0xc1,
    0x28, 0x18, 0x05, 0xc4, 0x00, 0x46, 0x06, 0x86, 0xff, 0xa3, 0xc5, 0xd7,
    0x20, 0x33, 0x10, 0x00, 0xf7, 0xf8, 0x04, 0x0f, 0xb2, 0x88, 0x6d, 0xdf,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
};

void write_vector_pdf(const fs::path& path) {
  const std::string content1 =
      "BT /F1 24 Tf 40 340 Td (Hello Vector) Tj ET\n"
      "0 0 1 rg 20 20 260 100 re f\n"
      "1 0 0 RG 3 w 20 200 m 280 300 l S\n";
  const std::string content2 =
      "BT /F1 20 Tf 40 340 Td (Page Two) Tj ET\n"
      "0 .6 .2 rg 100 100 100 100 re f\n";
  const std::vector<std::string> objects = {
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400]"
      " /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
      "<< /Length " + std::to_string(content1.size()) + " >>\nstream\n" + content1 +
          "endstream",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400]"
      " /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
      "<< /Length " + std::to_string(content2.size()) + " >>\nstream\n" + content2 +
          "endstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  };
  std::string pdf = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
  std::vector<size_t> offsets;
  for (size_t i = 0; i < objects.size(); ++i) {
    offsets.push_back(pdf.size());
    pdf += std::to_string(i + 1) + " 0 obj\n" + objects[i] + "\nendobj\n";
  }
  const size_t xref = pdf.size();
  pdf += "xref\n0 " + std::to_string(objects.size() + 1) + "\n";
  pdf += "0000000000 65535 f \n";
  for (const size_t offset : offsets) {
    char line[32];
    std::snprintf(line, sizeof(line), "%010zu 00000 n \n", offset);
    pdf += line;
  }
  pdf += "trailer\n<< /Size " + std::to_string(objects.size() + 1) +
         " /Root 1 0 R >>\nstartxref\n" + std::to_string(xref) + "\n%%EOF\n";

  std::ofstream out(path, std::ios::binary);
  out.write(pdf.data(), static_cast<std::streamsize>(pdf.size()));
}

void write_geometry_pdf(const fs::path& path) {
  const std::string content1 =
      "BT /F1 24 Tf 40 120 Td (GEOMETRY_SECRET) Tj ET\n"
      "0 0 1 rg 40 40 120 80 re f\n"
      "1 0 0 RG 3 w 20 200 m 280 200 l S\n";
  const std::string content2 = "0 .5 0 rg 50 50 200 120 re f\n";
  const std::vector<std::string> objects = {
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300]"
      " /CropBox [20 30 380 270] /Rotate 90"
      " /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
      "<< /Length " + std::to_string(content1.size()) + " >>\nstream\n" + content1 +
          "endstream",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 700]"
      " /Resources << >> /Contents 6 0 R >>",
      "<< /Length " + std::to_string(content2.size()) + " >>\nstream\n" + content2 +
          "endstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  };
  std::string pdf = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
  std::vector<size_t> offsets;
  for (size_t i = 0; i < objects.size(); ++i) {
    offsets.push_back(pdf.size());
    pdf += std::to_string(i + 1) + " 0 obj\n" + objects[i] + "\nendobj\n";
  }
  const size_t xref = pdf.size();
  pdf += "xref\n0 " + std::to_string(objects.size() + 1) + "\n";
  pdf += "0000000000 65535 f \n";
  for (const size_t offset : offsets) {
    char line[32];
    std::snprintf(line, sizeof(line), "%010zu 00000 n \n", offset);
    pdf += line;
  }
  pdf += "trailer\n<< /Size " + std::to_string(objects.size() + 1) +
         " /Root 1 0 R >>\nstartxref\n" + std::to_string(xref) + "\n%%EOF\n";
  std::ofstream out(path, std::ios::binary);
  out.write(pdf.data(), static_cast<std::streamsize>(pdf.size()));
}

#ifdef MEOWO_HAS_MUPDF
std::string pdf_stream_text(fz_context* ctx, pdf_obj* page_obj) {
  pdf_obj* contents = pdf_dict_get(ctx, page_obj, PDF_NAME(Contents));
  if (!contents) return {};
  if (pdf_is_array(ctx, contents)) {
    contents = pdf_array_get(ctx, contents, 0);
  }
  if (!contents) return {};
  fz_buffer* buffer = pdf_load_stream(ctx, contents);
  if (!buffer) return {};
  unsigned char* data = nullptr;
  const size_t size = fz_buffer_storage(ctx, buffer, &data);
  std::string text(reinterpret_cast<const char*>(data), size);
  fz_drop_buffer(ctx, buffer);
  return text;
}

std::string stext_text(fz_context* ctx, fz_page* page) {
  fz_stext_page* stext = fz_new_stext_page_from_page(ctx, page, nullptr);
  if (!stext) return {};
  fz_buffer* buffer = fz_new_buffer_from_stext_page(ctx, stext);
  unsigned char* data = nullptr;
  const size_t size = fz_buffer_storage(ctx, buffer, &data);
  std::string text(reinterpret_cast<const char*>(data), size);
  fz_drop_buffer(ctx, buffer);
  fz_drop_stext_page(ctx, stext);
  return text;
}
#endif

struct TempDir {
  fs::path path;
  TempDir() {
    std::string pattern = (fs::temp_directory_path() / "meowo-core-test-XXXXXX").string();
    char* result = mkdtemp(pattern.data());
    if (!result) throw std::runtime_error("mkdtemp failed");
    path = result;
  }
  ~TempDir() {
    std::error_code ec;
    fs::remove_all(path, ec);
  }
};

class Core {
 public:
  explicit Core(const fs::path& root) {
    char* error = nullptr;
    handle_ = meowo_workspace_open(root.string().c_str(), &error);
    if (!handle_) {
      const std::string message = error ? error : "unknown";
      meowo_free(error);
      throw std::runtime_error(message);
    }
  }
  ~Core() { meowo_workspace_close(handle_); }
  json call(const json& request) {
    const std::string text = request.dump();
    char* error = nullptr;
    char* result = meowo_invoke(handle_, text.c_str(), &error);
    if (!result) {
      const std::string message = error ? error : "unknown";
      meowo_free(error);
      throw std::runtime_error(message);
    }
    const std::string output(result);
    meowo_free(result);
    return json::parse(output);
  }

 private:
  uint64_t handle_ = 0;
};

}  // namespace

TEST(Core, CreatesListsOpensAndPersistsDocument) {
  TempDir temp;
  Core core(temp.path);
  const json created = core.call({{"op", "create_document"},
                                  {"title", "课堂笔记"},
                                  {"kind", "paged"},
                                  {"paper", {{"preset", "A4"}}}});
  EXPECT_EQ(created["title"], "课堂笔记");
  EXPECT_EQ(created["kind"], "paged");
  EXPECT_EQ(created["pages"].size(), 1u);
  const std::string id = created["id"];

  const json list = core.call({{"op", "list_documents"}});
  ASSERT_EQ(list["items"].size(), 1u);
  EXPECT_EQ(list["items"][0]["id"], id);

  json doc = core.call({{"op", "open_document"}, {"id", id}});
  doc["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "stroke_test"},
       {"type", "stroke"},
       {"color", "#112233"},
       {"width", 2.0},
       {"opacity", 1.0},
       {"highlighter", false},
       {"points", json::array({{10.0, 20.0, 0.5}, {30.0, 40.0, 0.8}})}});
  core.call({{"op", "save_document"}, {"document", doc}});

  const json reopened = core.call({{"op", "open_document"}, {"id", id}});
  ASSERT_EQ(reopened["pages"][0]["layers"][0]["elements"].size(), 1u);
  EXPECT_EQ(reopened["pages"][0]["layers"][0]["elements"][0]["id"], "stroke_test");
}

TEST(Core, FoldersFavoritesAndTrash) {
  TempDir temp;
  Core core(temp.path);
  const json folder = core.call({{"op", "create_folder"}, {"name", "课程"}});
  const std::string folder_id = folder["id"];
  const json doc = core.call({{"op", "create_document"},
                              {"title", "高数"},
                              {"kind", "paged"},
                              {"folderId", folder_id}});
  const std::string id = doc["id"];
  core.call({{"op", "toggle_favorite"}, {"id", id}});

  const json favorites = core.call({{"op", "list_documents"}, {"favorites", true}});
  ASSERT_EQ(favorites["items"].size(), 1u);
  EXPECT_TRUE(favorites["items"][0]["favorite"].get<bool>());

  core.call({{"op", "delete_document"}, {"id", id}});
  const json trash = core.call({{"op", "list_documents"}, {"trash", true}});
  ASSERT_EQ(trash["items"].size(), 1u);
  core.call({{"op", "restore_document"}, {"id", id}});
  const json active = core.call({{"op", "list_documents"}});
  EXPECT_EQ(active["items"].size(), 1u);
}

TEST(Core, MarkdownImportCreatesBodyText) {
  TempDir temp;
  Core core(temp.path);
  const fs::path markdown = temp.path / "note.md";
  {
    std::ofstream out(markdown);
    out << "# 标题\n\n这是一段 **Markdown**。\n";
  }
  const json result = core.call({{"op", "import_markdown"},
                                 {"sourcePath", markdown.string()}});
  const json doc = core.call({{"op", "open_document"}, {"id", result["id"]}});
  ASSERT_TRUE(doc["pages"][0]["body"].is_object());
  EXPECT_NE(doc["pages"][0]["body"]["markdown"].get<std::string>().find("Markdown"),
            std::string::npos);
}

TEST(Core, PdfImportKeepsRasterFallbackAndRendersVectorPages) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "vector.pdf";
  write_vector_pdf(pdf);

  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  const json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  ASSERT_TRUE(doc["bookSource"].is_object());
  EXPECT_EQ(doc["bookSource"]["vector"], "svg");
  EXPECT_FALSE(doc["bookSource"]["encrypted"].get<bool>());
  ASSERT_EQ(doc["pages"].size(), 2u);
  EXPECT_EQ(doc["pages"][0]["sourceIndex"], 0);
  EXPECT_NE(doc["pages"][0]["sourceText"].get<std::string>().find("Hello Vector"),
            std::string::npos);

  const std::string page_asset = doc["pages"][0]["sourceAssetId"];
  const json png = core.call(
      {{"op", "get_asset"}, {"documentId", imported["id"]}, {"assetId", page_asset}});
  EXPECT_EQ(png["mime"], "image/png");
  EXPECT_GT(png["size"].get<int>(), 1000);

  const json rendered = core.call({{"op", "render_book_pages_svg"},
                                   {"documentId", imported["id"]},
                                   {"pageIndexes", {0, 1}}});
  ASSERT_TRUE(rendered["failures"].empty());
  ASSERT_EQ(rendered["pages"].size(), 2u);
  for (const auto& page : rendered["pages"]) {
    const std::string svg = page["svg"];
    EXPECT_EQ(svg.rfind("<svg", 0), 0u);
    EXPECT_NE(svg.find("<path"), std::string::npos);
    EXPECT_EQ(svg.find("<use xlink:href=\"#font_"), std::string::npos);
    EXPECT_GT(svg.size(), 1000u);
    EXPECT_EQ(page["width"].get<double>(), 300.0);
    EXPECT_EQ(page["height"].get<double>(), 400.0);
  }
}

TEST(Core, RasterBookRejectsVectorPageRequests) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "raster.pdf";
  write_vector_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});

  // Simulates documents imported before vector support (no marker) and the
  // explicit raster fallback for encrypted/unsupported PDFs.
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  doc["bookSource"]["vector"] = "raster";
  core.call({{"op", "save_document"}, {"document", doc}});

  const auto request_vector_page = [&] {
    core.call({{"op", "render_book_pages_svg"},
               {"documentId", imported["id"]},
               {"pageIndexes", {0}}});
  };
  EXPECT_THROW(request_vector_page(), std::runtime_error);
  const json reopened = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  EXPECT_EQ(reopened["pages"][0]["sourceAssetId"],
            doc["pages"][0]["sourceAssetId"]);
  EXPECT_EQ(reopened["bookSource"]["vector"], "raster");
}

#ifdef MEOWO_HAS_MUPDF
TEST(Core, ExportBookPdfPreservesVectorGeometryAndDropsTextLayer) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "geometry.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  const json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  ASSERT_EQ(doc["pages"].size(), 2u);
  const double width = doc["pages"][0]["width"].get<double>();
  const double height = doc["pages"][0]["height"].get<double>();

  const fs::path out = temp.path / "geometry-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0}}});
  EXPECT_EQ(result["exportedPages"], json::array({1}));
  EXPECT_EQ(result["vectorPages"], json::array({1}));
  EXPECT_TRUE(result["fallbackPages"].empty());
  ASSERT_TRUE(fs::exists(out));

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  EXPECT_EQ(fz_count_pages(ctx, out_doc), 1);
  fz_page* page = fz_load_page(ctx, out_doc, 0);
  ASSERT_NE(page, nullptr);
  const fz_rect bounds = fz_bound_page(ctx, page);
  EXPECT_NEAR(bounds.x1 - bounds.x0, width, 0.5);
  EXPECT_NEAR(bounds.y1 - bounds.y0, height, 0.5);

  pdf_document* out_pdf = pdf_specifics(ctx, out_doc);
  ASSERT_NE(out_pdf, nullptr);
  pdf_obj* page_obj = pdf_lookup_page_obj(ctx, out_pdf, 0);
  ASSERT_NE(page_obj, nullptr);
  const fz_rect media = pdf_dict_get_rect(ctx, page_obj, PDF_NAME(MediaBox));
  const fz_rect crop = pdf_dict_get_rect(ctx, page_obj, PDF_NAME(CropBox));
  EXPECT_NEAR(media.x1, 400.0, 0.01);
  EXPECT_NEAR(media.y1, 300.0, 0.01);
  EXPECT_NEAR(crop.x0, 20.0, 0.01);
  EXPECT_NEAR(crop.y0, 30.0, 0.01);
  EXPECT_NEAR(crop.x1, 380.0, 0.01);
  EXPECT_NEAR(crop.y1, 270.0, 0.01);
  EXPECT_EQ(pdf_dict_get_int(ctx, page_obj, PDF_NAME(Rotate)), 90);

  const std::string extracted = stext_text(ctx, page);
  EXPECT_EQ(extracted.find("GEOMETRY_SECRET"), std::string::npos);
  pdf_obj* resources = pdf_dict_get(ctx, page_obj, PDF_NAME(Resources));
  ASSERT_NE(resources, nullptr);
  EXPECT_FALSE(pdf_dict_get(ctx, resources, PDF_NAME(Font)));

  const std::string content = pdf_stream_text(ctx, page_obj);
  EXPECT_NE(content.find(" m"), std::string::npos);
  EXPECT_NE(content.find(" l"), std::string::npos);
  EXPECT_NE(content.find("S\n"), std::string::npos);

  // Visual comparison also guards against double-applying crop/rotation.
  fz_document* source_doc = fz_open_document(ctx, pdf.string().c_str());
  ASSERT_NE(source_doc, nullptr);
  fz_page* source_page = fz_load_page(ctx, source_doc, 0);
  ASSERT_NE(source_page, nullptr);
  fz_pixmap* source_pix =
      fz_new_pixmap_from_page(ctx, source_page, fz_identity, fz_device_rgb(ctx), 0);
  fz_pixmap* export_pix =
      fz_new_pixmap_from_page(ctx, page, fz_identity, fz_device_rgb(ctx), 0);
  ASSERT_NE(source_pix, nullptr);
  ASSERT_NE(export_pix, nullptr);
  ASSERT_EQ(source_pix->w, export_pix->w);
  ASSERT_EQ(source_pix->h, export_pix->h);
  long long difference = 0;
  const size_t samples = static_cast<size_t>(source_pix->w) * source_pix->h * 3;
  for (int y = 0; y < source_pix->h; ++y) {
    const unsigned char* a = source_pix->samples + y * source_pix->stride;
    const unsigned char* b = export_pix->samples + y * export_pix->stride;
    for (int x = 0; x < source_pix->w * 3; ++x) {
      difference += std::abs(static_cast<int>(a[x]) - static_cast<int>(b[x]));
    }
  }
  EXPECT_LT(static_cast<double>(difference) / samples, 3.0);
  fz_drop_pixmap(ctx, source_pix);
  fz_drop_pixmap(ctx, export_pix);
  fz_drop_page(ctx, source_page);
  fz_drop_document(ctx, source_doc);

  fz_drop_page(ctx, page);
  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);
}

TEST(Core, ExportBookPdfWritesInkAndHighlighterAsPaths) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "ink.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  doc["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "ink_test"},
       {"type", "stroke"},
       {"points", json::array({json::array({30, 30, 1.0}),
                              json::array({200, 200, 0.6}),
                              json::array({300, 100, 0.8})})},
       {"color", "#FF0000"},
       {"width", 4.0},
       {"highlighter", false},
       {"opacity", 1.0}});
  doc["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "highlighter_test"},
       {"type", "stroke"},
       {"points", json::array({json::array({20, 20, 1.0}),
                              json::array({300, 300, 1.0})})},
       {"color", "#FFF000"},
       {"width", 12.0},
       {"highlighter", true},
       {"opacity", 1.0}});
  core.call({{"op", "save_document"}, {"document", doc}});

  const fs::path out = temp.path / "ink-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0}}});
  EXPECT_TRUE(result["fallbackPages"].empty());

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  pdf_document* out_pdf = pdf_specifics(ctx, out_doc);
  ASSERT_NE(out_pdf, nullptr);
  pdf_obj* page_obj = pdf_lookup_page_obj(ctx, out_pdf, 0);
  ASSERT_NE(page_obj, nullptr);
  pdf_obj* resources = pdf_dict_get(ctx, page_obj, PDF_NAME(Resources));
  ASSERT_NE(resources, nullptr);
  pdf_obj* extgstates = pdf_dict_get(ctx, resources, PDF_NAME(ExtGState));
  ASSERT_TRUE(pdf_is_dict(ctx, extgstates));
  bool multiply = false;
  bool alpha_seen = false;
  for (int i = 0; i < pdf_dict_len(ctx, extgstates); ++i) {
    pdf_obj* value = pdf_dict_get(ctx, extgstates, pdf_dict_get_key(ctx, extgstates, i));
    if (!pdf_is_dict(ctx, value)) continue;
    pdf_obj* blend = pdf_dict_get(ctx, value, PDF_NAME(BM));
    if (blend && std::string(pdf_to_name(ctx, blend)) == "Multiply") {
      multiply = true;
      const double alpha = pdf_dict_get_real(ctx, value, PDF_NAME(ca));
      EXPECT_NEAR(alpha, 0.32, 0.02);
      alpha_seen = true;
    }
  }
  EXPECT_TRUE(multiply);
  EXPECT_TRUE(alpha_seen);
  const std::string content = pdf_stream_text(ctx, page_obj);
  EXPECT_NE(content.find("RG"), std::string::npos);
  EXPECT_NE(content.find(" l\n"), std::string::npos);
  EXPECT_NE(content.find("S\n"), std::string::npos);

  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);
}

TEST(Core, ExportBookPdfKeepsOverlayAndInkOrientation) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "orientation.pdf";
  write_vector_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  doc["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "orientation_ink"},
       {"type", "stroke"},
       {"points", json::array({json::array({20, 230, 1.0}),
                              json::array({120, 230, 1.0})})},
       {"color", "#00FF00"},
       {"width", 8.0},
       {"highlighter", false},
       {"opacity", 1.0}});
  core.call({{"op", "save_document"}, {"document", doc}});

  const fs::path overlay_dir = temp.path / "orientation-overlays";
  fs::create_directories(overlay_dir);
  {
    std::ofstream overlay(overlay_dir / "overlay-0.png", std::ios::binary);
    overlay.write(reinterpret_cast<const char*>(kTopRedBottomBluePng),
                  sizeof(kTopRedBottomBluePng));
  }
  const fs::path out = temp.path / "orientation-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0}},
                                 {"overlayDir", overlay_dir.string()}});
  EXPECT_EQ(result["vectorPages"], json::array({1}));

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  fz_page* page = fz_load_page(ctx, out_doc, 0);
  ASSERT_NE(page, nullptr);
  fz_pixmap* pix =
      fz_new_pixmap_from_page(ctx, page, fz_identity, fz_device_rgb(ctx), 0);
  ASSERT_NE(pix, nullptr);
  const auto pixel = [&](int x, int y, int* r, int* g, int* b) {
    const unsigned char* p = pix->samples + y * pix->stride + x * 3;
    *r = p[0];
    *g = p[1];
    *b = p[2];
  };
  int r = 0, g = 0, b = 0;
  // The overlay image must stay upright: red on top, blue at the bottom.
  pixel(pix->w / 2, 8, &r, &g, &b);
  EXPECT_GT(r, 180);
  EXPECT_LT(g, 80);
  EXPECT_LT(b, 80);
  pixel(pix->w / 2, pix->h - 8, &r, &g, &b);
  EXPECT_LT(r, 80);
  EXPECT_LT(g, 80);
  EXPECT_GT(b, 180);
  // The green ink is in the same display coordinate space and must not be
  // vertically inverted.
  pixel(60, 230, &r, &g, &b);
  EXPECT_LT(r, 100);
  EXPECT_GT(g, 150);
  EXPECT_LT(b, 100);

  fz_drop_pixmap(ctx, pix);
  fz_drop_page(ctx, page);
  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);
}

TEST(Core, ExportBookPdfFallbackBitmapKeepsOrientation) {
  TempDir temp;
  Core core(temp.path);
  const fs::path png = temp.path / "orientation.png";
  {
    std::ofstream out(png, std::ios::binary);
    out.write(reinterpret_cast<const char*>(kTopRedBottomBluePng),
              sizeof(kTopRedBottomBluePng));
  }
  const json imported =
      core.call({{"op", "import_pdf_pages"},
                 {"title", "orientation raster"},
                 {"pages", json::array({json{{"path", png.string()},
                                             {"width", 300.0},
                                             {"height", 400.0}}})}});
  const fs::path out = temp.path / "orientation-fallback.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0}}});
  EXPECT_EQ(result["fallbackPages"].size(), 1u);

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(doc, nullptr);
  fz_page* page = fz_load_page(ctx, doc, 0);
  ASSERT_NE(page, nullptr);
  fz_pixmap* pix =
      fz_new_pixmap_from_page(ctx, page, fz_identity, fz_device_rgb(ctx), 0);
  ASSERT_NE(pix, nullptr);
  const unsigned char* top =
      pix->samples + 8 * pix->stride + (pix->w / 2) * 3;
  const unsigned char* bottom =
      pix->samples + (pix->h - 8) * pix->stride + (pix->w / 2) * 3;
  EXPECT_GT(top[0], 180);
  EXPECT_LT(top[1], 80);
  EXPECT_LT(top[2], 80);
  EXPECT_LT(bottom[0], 80);
  EXPECT_LT(bottom[1], 80);
  EXPECT_GT(bottom[2], 180);

  fz_drop_pixmap(ctx, pix);
  fz_drop_page(ctx, page);
  fz_drop_document(ctx, doc);
  fz_drop_context(ctx);
}

TEST(Core, ExportBookPdfKeepsNoteInkUpright) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "note-orientation.pdf";
  write_vector_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  json note = {{"id", "page_note_orientation"},
               {"isNotePage", true},
               {"width", 123.0},
               {"height", 456.0},
               {"layers", json::array({json{{"id", "layer_note_orientation"},
                                            {"name", "note"},
                                            {"visible", true},
                                            {"locked", false},
                                            {"opacity", 1.0},
                                            {"elements", json::array()}}})},
               {"body", nullptr}};
  note["layers"][0]["elements"].push_back(
      {{"id", "note_ink_orientation"},
       {"type", "stroke"},
       {"points", json::array({json::array({20, 20, 1.0}),
                              json::array({120, 20, 1.0})})},
       {"color", "#00FF00"},
       {"width", 8.0},
       {"highlighter", false},
       {"opacity", 1.0}});
  doc["pages"].push_back(note);
  core.call({{"op", "save_document"}, {"document", doc}});

  const fs::path out = temp.path / "note-orientation-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {static_cast<int>(doc["pages"].size()) - 1}}});
  EXPECT_EQ(result["exportedPages"], json::array({3}));

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  fz_page* page = fz_load_page(ctx, out_doc, 0);
  ASSERT_NE(page, nullptr);
  fz_pixmap* pix =
      fz_new_pixmap_from_page(ctx, page, fz_identity, fz_device_rgb(ctx), 0);
  ASSERT_NE(pix, nullptr);
  const auto pixel = [&](int x, int y, int* r, int* g, int* b) {
    const unsigned char* p = pix->samples + y * pix->stride + x * 3;
    *r = p[0];
    *g = p[1];
    *b = p[2];
  };
  int r = 0, g = 0, b = 0;
  pixel(60, 20, &r, &g, &b);
  EXPECT_LT(r, 100);
  EXPECT_GT(g, 150);
  EXPECT_LT(b, 100);
  pixel(60, pix->h - 20, &r, &g, &b);
  EXPECT_GT(r, 200);
  EXPECT_GT(g, 200);
  EXPECT_GT(b, 200);

  fz_drop_pixmap(ctx, pix);
  fz_drop_page(ctx, page);
  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);
}

TEST(Core, ProbeBookReportsPageCountWithoutImporting) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "probe.pdf";
  write_vector_pdf(pdf);
  const json probe = core.call({{"op", "probe_book"},
                                {"sourcePath", pdf.string()}});
  EXPECT_EQ(probe["pageCount"], 2);
  EXPECT_EQ(probe["encrypted"], false);
  EXPECT_EQ(core.call({{"op", "list_documents"}})["items"].size(), 0u);
}

TEST(Core, ImportBookWritesProgressAndHasNoPageLimit) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "progress.pdf";
  write_vector_pdf(pdf);
  const fs::path progress = temp.path / "import-progress.json";
  const json imported = core.call({{"op", "import_pdf"},
                                   {"sourcePath", pdf.string()},
                                   {"progressPath", progress.string()}});
  EXPECT_EQ(imported["pages"], 2);
  ASSERT_TRUE(fs::exists(progress));
  std::ifstream in(progress);
  const json value = json::parse(in);
  EXPECT_EQ(value["phase"], "saving");
  EXPECT_EQ(value["completed"], value["total"]);
  EXPECT_GE(value["total"].get<int>(), 3);
}

TEST(Core, ExportBookPdfUsesPaperSizeForNotePagesAndHonorsRanges) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "notes.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  const double paper_width = doc["paper"]["width"].get<double>();
  const double paper_height = doc["paper"]["height"].get<double>();
  json note = {{"id", "page_note_test"},
               {"isNotePage", true},
               {"width", 123.0},
               {"height", 456.0},
               {"layers", json::array({json{{"id", "layer_note_test"},
                                            {"name", "note"},
                                            {"visible", true},
                                            {"locked", false},
                                            {"opacity", 1.0},
                                            {"elements", json::array()}}})},
               {"body", nullptr}};
  note["layers"][0]["elements"].push_back(
      {{"id", "note_ink"},
       {"type", "stroke"},
       {"points", json::array({json::array({10, 10, 1.0}),
                              json::array({100, 100, 1.0})})},
       {"color", "#000000"},
       {"width", 2.0},
       {"highlighter", false},
       {"opacity", 1.0}});
  auto pages = doc["pages"];
  pages.insert(pages.begin() + 1, note);
  doc["pages"] = pages;
  core.call({{"op", "save_document"}, {"document", doc}});

  const fs::path overlay_dir = temp.path / "overlays";
  fs::create_directories(overlay_dir);
  const unsigned char overlay_png[] = {
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
      0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92, 0xef, 0x00, 0x00, 0x00,
      0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  };
  {
    std::ofstream overlay(overlay_dir / "overlay-1.png", std::ios::binary);
    overlay.write(reinterpret_cast<const char*>(overlay_png),
                  sizeof(overlay_png));
  }

  const fs::path out = temp.path / "notes-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0, 1, 2}},
                                 {"overlayDir", overlay_dir.string()}});
  EXPECT_EQ(result["exportedPages"], json::array({1, 2, 3}));
  EXPECT_TRUE(result["fallbackPages"].empty());

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  EXPECT_EQ(fz_count_pages(ctx, out_doc), 3);
  pdf_document* out_pdf = pdf_specifics(ctx, out_doc);
  pdf_obj* note_obj = pdf_lookup_page_obj(ctx, out_pdf, 1);
  const fz_rect note_media = pdf_dict_get_rect(ctx, note_obj, PDF_NAME(MediaBox));
  EXPECT_NEAR(note_media.x1, paper_width, 0.01);
  EXPECT_NEAR(note_media.y1, paper_height, 0.01);
  const std::string note_content = pdf_stream_text(ctx, note_obj);
  EXPECT_NE(note_content.find(" l\n"), std::string::npos);
  pdf_obj* note_resources = pdf_dict_get(ctx, note_obj, PDF_NAME(Resources));
  ASSERT_NE(note_resources, nullptr);
  EXPECT_TRUE(
      pdf_is_dict(ctx, pdf_dict_get(ctx, note_resources, PDF_NAME(XObject))));
  fz_page* note_page = fz_load_page(ctx, out_doc, 1);
  ASSERT_NE(note_page, nullptr);
  fz_pixmap* note_pix =
      fz_new_pixmap_from_page(ctx, note_page, fz_identity, fz_device_rgb(ctx), 0);
  ASSERT_NE(note_pix, nullptr);
  const int sample_x = static_cast<int>(paper_width / 2);
  const int sample_y = static_cast<int>(paper_height / 2);
  const unsigned char* pixel =
      note_pix->samples + sample_y * note_pix->stride + sample_x * 3;
  EXPECT_GT(pixel[0], 200);
  EXPECT_LT(pixel[1], 60);
  EXPECT_LT(pixel[2], 60);
  fz_drop_pixmap(ctx, note_pix);
  fz_drop_page(ctx, note_page);
  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);

  const fs::path page_out = temp.path / "page-out.pdf";
  const json single = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", page_out.string()},
                                 {"pageIndexes", {2}}});
  EXPECT_EQ(single["exportedPages"], json::array({3}));
  fz_context* ctx2 = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx2, nullptr);
  fz_register_document_handlers(ctx2);
  fz_document* single_doc = fz_open_document(ctx2, page_out.string().c_str());
  ASSERT_NE(single_doc, nullptr);
  EXPECT_EQ(fz_count_pages(ctx2, single_doc), 1);
  pdf_document* single_pdf = pdf_specifics(ctx2, single_doc);
  pdf_obj* single_obj = pdf_lookup_page_obj(ctx2, single_pdf, 0);
  const fz_rect single_media =
      pdf_dict_get_rect(ctx2, single_obj, PDF_NAME(MediaBox));
  EXPECT_NEAR(single_media.x1, 500.0, 0.01);
  EXPECT_NEAR(single_media.y1, 700.0, 0.01);
  fz_drop_document(ctx2, single_doc);
  fz_drop_context(ctx2);
}

TEST(Core, ExportBookPdfFallsBackToPagePngAndReportsIt) {
  TempDir temp;
  Core core(temp.path);
  const fs::path png = temp.path / "page.png";
  {
    std::ofstream out(png, std::ios::binary);
    const unsigned char bytes[] = {
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
        0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
        0x00, 0x05, 0xfe, 0x02, 0xfe, 0x0d, 0xef, 0x46, 0xb8, 0x00, 0x00, 0x00,
        0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    };
    out.write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
  }
  const json imported = core.call({{"op", "import_pdf_pages"},
                                   {"title", "raster book"},
                                   {"pages", json::array({json{{"path", png.string()},
                                                               {"width", 300.0},
                                                               {"height", 400.0}}})}});
  const fs::path out = temp.path / "fallback-out.pdf";
  const json result = core.call({{"op", "export_book_pdf"},
                                 {"documentId", imported["id"]},
                                 {"targetPath", out.string()},
                                 {"pageIndexes", {0}}});
  EXPECT_EQ(result["exportedPages"], json::array({1}));
  EXPECT_EQ(result["vectorPages"], json::array());
  ASSERT_EQ(result["fallbackPages"].size(), 1u);
  EXPECT_EQ(result["fallbackPages"][0]["pageNumber"], 1);
  EXPECT_EQ(result["fallbackPages"][0]["reason"], "missing_book_source");

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  ASSERT_NE(ctx, nullptr);
  fz_register_document_handlers(ctx);
  fz_document* out_doc = fz_open_document(ctx, out.string().c_str());
  ASSERT_NE(out_doc, nullptr);
  pdf_document* out_pdf = pdf_specifics(ctx, out_doc);
  pdf_obj* page_obj = pdf_lookup_page_obj(ctx, out_pdf, 0);
  const fz_rect media = pdf_dict_get_rect(ctx, page_obj, PDF_NAME(MediaBox));
  EXPECT_NEAR(media.x1, 300.0, 0.01);
  EXPECT_NEAR(media.y1, 400.0, 0.01);
  pdf_obj* resources = pdf_dict_get(ctx, page_obj, PDF_NAME(Resources));
  EXPECT_TRUE(pdf_is_dict(ctx, pdf_dict_get(ctx, resources, PDF_NAME(XObject))));
  fz_drop_document(ctx, out_doc);
  fz_drop_context(ctx);
}

TEST(Core, ExportBookPdfFallsBackForEncryptedAndEpubSources) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "encrypted-source.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  json doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  doc["bookSource"]["encrypted"] = true;
  core.call({{"op", "save_document"}, {"document", doc}});
  const json encrypted = core.call({{"op", "export_book_pdf"},
                                    {"documentId", imported["id"]},
                                    {"targetPath", (temp.path / "encrypted.pdf").string()},
                                    {"pageIndexes", {0}}});
  EXPECT_EQ(encrypted["vectorPages"], json::array());
  ASSERT_EQ(encrypted["fallbackPages"].size(), 1u);
  EXPECT_EQ(encrypted["fallbackPages"][0]["reason"],
            "encrypted_pdf_no_password");

  doc = core.call({{"op", "open_document"}, {"id", imported["id"]}});
  doc["bookSource"]["encrypted"] = false;
  doc["bookSource"]["mime"] = "application/epub+zip";
  core.call({{"op", "save_document"}, {"document", doc}});
  const json epub = core.call({{"op", "export_book_pdf"},
                               {"documentId", imported["id"]},
                               {"targetPath", (temp.path / "epub.pdf").string()},
                               {"pageIndexes", {0}}});
  EXPECT_EQ(epub["vectorPages"], json::array());
  ASSERT_EQ(epub["fallbackPages"].size(), 1u);
  EXPECT_EQ(epub["fallbackPages"][0]["reason"], "epub_fixed_page");
}

TEST(Core, ExportBookPdfRequiresExplicitOverwrite) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "overwrite.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  const fs::path target = temp.path / "overwrite-out.pdf";
  core.call({{"op", "export_book_pdf"},
             {"documentId", imported["id"]},
             {"targetPath", target.string()},
             {"pageIndexes", {0}}});
  EXPECT_THROW(core.call({{"op", "export_book_pdf"},
                          {"documentId", imported["id"]},
                          {"targetPath", target.string()},
                          {"pageIndexes", {0}}}),
               std::runtime_error);
  const json overwritten = core.call({{"op", "export_book_pdf"},
                                      {"documentId", imported["id"]},
                                      {"targetPath", target.string()},
                                      {"pageIndexes", {0}},
                                      {"overwrite", true}});
  EXPECT_FALSE(overwritten["cancelled"].get<bool>());
  EXPECT_TRUE(fs::exists(target));
  EXPECT_THROW(
      core.call({{"op", "export_book_pdf"},
                 {"documentId", imported["id"]},
                 {"targetPath",
                  (temp.path / "documents" / (imported["id"].get<std::string>() + ".meowo"))
                      .string()},
                 {"pageIndexes", {0}},
                 {"overwrite", true}}),
      std::runtime_error);
}

TEST(Core, ExportBookPdfHonorsCancelAndWritesProgress) {
  TempDir temp;
  Core core(temp.path);
  const fs::path pdf = temp.path / "cancel.pdf";
  write_geometry_pdf(pdf);
  const json imported = core.call({{"op", "import_pdf"}, {"sourcePath", pdf.string()}});
  const fs::path target = temp.path / "cancel-out.pdf";
  const fs::path cancel = temp.path / "cancel.flag";
  std::ofstream(cancel) << "1";
  const json cancelled = core.call({{"op", "export_book_pdf"},
                                    {"documentId", imported["id"]},
                                    {"targetPath", target.string()},
                                    {"pageIndexes", {0}},
                                    {"cancelPath", cancel.string()}});
  EXPECT_TRUE(cancelled["cancelled"].get<bool>());
  EXPECT_FALSE(fs::exists(target));

  fs::remove(cancel);
  const fs::path progress = temp.path / "progress.json";
  const json done = core.call({{"op", "export_book_pdf"},
                               {"documentId", imported["id"]},
                               {"targetPath", target.string()},
                               {"pageIndexes", {0}},
                               {"progressPath", progress.string()}});
  EXPECT_FALSE(done["cancelled"].get<bool>());
  ASSERT_TRUE(fs::exists(progress));
  std::ifstream in(progress);
  std::stringstream buffer;
  buffer << in.rdbuf();
  const json status = json::parse(buffer.str());
  EXPECT_EQ(status["phase"], "done");
  EXPECT_EQ(status["completed"], 1);
  EXPECT_EQ(status["total"], 1);
}
#endif

TEST(Core, AssetRoundTrip) {
  TempDir temp;
  Core core(temp.path);
  const json doc = core.call({{"op", "create_document"},
                              {"title", "附件"},
                              {"kind", "paged"}});
  const std::string id = doc["id"];
  const json asset = core.call({{"op", "add_asset"},
                                {"documentId", id},
                                {"name", "hello.txt"},
                                {"mime", "text/plain"},
                                {"data", "aGVsbG8="}});
  EXPECT_EQ(asset["size"], 5);
  const json loaded = core.call({{"op", "get_asset"},
                                 {"documentId", id},
                                 {"assetId", asset["id"]}});
  EXPECT_EQ(loaded["base64"], "aGVsbG8=");
  const json reopened = core.call({{"op", "open_document"}, {"id", id}});
  ASSERT_EQ(reopened["assets"].size(), 1u);
  EXPECT_EQ(reopened["assets"][0]["name"], "hello.txt");
}

TEST(Core, AssetReferenceProtection) {
  TempDir temp;
  Core core(temp.path);
  const json doc = core.call({{"op", "create_document"},
                              {"title", "附件引用"},
                              {"kind", "paged"}});
  const std::string id = doc["id"];
  const json asset = core.call({{"op", "add_asset"},
                                {"documentId", id},
                                {"name", "note.txt"},
                                {"mime", "text/plain"},
                                {"data", "aGVsbG8="}});
  const std::string assetId = asset["id"];
  json payload = core.call({{"op", "open_document"}, {"id", id}});
  payload["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "attachment_test"},
       {"type", "attachment"},
       {"assetId", assetId},
       {"name", "note.txt"},
       {"mime", "text/plain"}});
  core.call({{"op", "save_document"}, {"document", payload}});

  const json listed = core.call({{"op", "list_assets"}, {"documentId", id}});
  ASSERT_EQ(listed["assets"].size(), 1u);
  EXPECT_TRUE(listed["assets"][0]["referenced"]);
  EXPECT_EQ(listed["assets"][0]["referenceCount"], 1);
  EXPECT_THROW(core.call({{"op", "delete_asset"},
                          {"documentId", id},
                          {"assetId", assetId}}),
               std::runtime_error);

  payload = core.call({{"op", "open_document"}, {"id", id}});
  payload["pages"][0]["layers"][0]["elements"].clear();
  core.call({{"op", "save_document"}, {"document", payload}});
  core.call({{"op", "delete_asset"}, {"documentId", id}, {"assetId", assetId}});
  const json after = core.call({{"op", "list_assets"}, {"documentId", id}});
  EXPECT_TRUE(after["assets"].empty());
}

TEST(Core, SearchFindsTextAndTitle) {
  TempDir temp;
  Core core(temp.path);
  core.call({{"op", "create_document"}, {"title", "物理实验"}, {"kind", "paged"}});
  const json doc = core.call({{"op", "create_document"}, {"title", "其他"}, {"kind", "paged"}});
  json opened = core.call({{"op", "open_document"}, {"id", doc["id"]}});
  opened["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "txt"}, {"type", "text"}, {"markdown", "量子力学笔记"}});
  core.call({{"op", "save_document"}, {"document", opened}});
  const json found = core.call({{"op", "search"}, {"query", "量子"}});
  ASSERT_EQ(found["items"].size(), 1u);
  EXPECT_EQ(found["items"][0]["title"], "其他");
  const json by_title = core.call({{"op", "search"}, {"query", "物理"}});
  ASSERT_EQ(by_title["items"].size(), 1u);
}

TEST(Core, ExportsDocumentCopy) {
  TempDir temp;
  Core core(temp.path);
  const json doc = core.call({{"op", "create_document"}, {"title", "导出"}, {"kind", "paged"}});
  const fs::path target = temp.path / "copy.meowo";
  core.call({{"op", "export_document"},
             {"id", doc["id"]},
             {"targetPath", target.string()}});
  EXPECT_TRUE(fs::exists(target));
}

TEST(Core, RejectsConcurrentWorkspaceOpen) {
  TempDir temp;
  char* error = nullptr;
  const uint64_t first = meowo_workspace_open(temp.path.string().c_str(), &error);
  ASSERT_NE(first, 0u);
  meowo_free(error);
  error = nullptr;

  const uint64_t second = meowo_workspace_open(temp.path.string().c_str(), &error);
  EXPECT_EQ(second, 0u);
  ASSERT_NE(error, nullptr);
  EXPECT_NE(std::string(error).find("另一个"), std::string::npos);
  meowo_free(error);
  error = nullptr;

  meowo_workspace_close(first);
  const uint64_t third = meowo_workspace_open(temp.path.string().c_str(), &error);
  EXPECT_NE(third, 0u);
  meowo_free(error);
  if (third) meowo_workspace_close(third);
}
