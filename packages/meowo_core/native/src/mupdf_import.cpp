#include "mupdf_import.h"

#include <mupdf/fitz.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace meowo {
namespace {

constexpr float kRenderDpi = 120.0f;
constexpr float kPointsPerInch = 72.0f;
constexpr float kMaxRenderPixels = 5000.0f;
constexpr int kMetaBuffer = 512;

void lookup_metadata(fz_context* ctx, fz_document* doc, const char* key, char* out,
                     int out_size) {
  if (!out || out_size <= 0) return;
  out[0] = '\0';
  const int n = fz_lookup_metadata(ctx, doc, key, out, out_size);
  if (n < 0) out[0] = '\0';
  out[out_size - 1] = '\0';
}

}  // namespace

MuPdfResult render_with_mupdf(const std::string& sourcePath,
                              const std::string& outputDir,
                              const std::string& password,
                              int maxPages) {
  MuPdfResult result;
  result.version = FZ_VERSION;

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  if (!ctx) {
    result.error = "无法创建 MuPDF 上下文";
    return result;
  }

  fz_document* doc = nullptr;
  fz_page* page = nullptr;
  fz_pixmap* pix = nullptr;
  fz_stext_page* stext = nullptr;
  fz_buffer* text_buffer = nullptr;
  int pageCount = 0;
  char title[kMetaBuffer]{};
  char author[kMetaBuffer]{};
  char format[kMetaBuffer]{};

  fz_var(doc);
  fz_var(page);
  fz_var(pix);
  fz_var(stext);
  fz_var(text_buffer);
  fz_var(pageCount);

  fz_try(ctx) {
    fz_register_document_handlers(ctx);
    doc = fz_open_document(ctx, sourcePath.c_str());
    if (!doc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "MuPDF 无法打开文档");

    if (fz_needs_password(ctx, doc)) {
      const bool authenticated =
          !password.empty() && fz_authenticate_password(ctx, doc, password.c_str());
      if (!authenticated || fz_needs_password(ctx, doc)) {
        fz_throw(ctx, FZ_ERROR_ARGUMENT, "文档已加密，需要正确的密码");
      }
    }

    if (fz_is_document_reflowable(ctx, doc)) {
      // Fixed A4 snapshot; the original EPUB is retained as a source asset.
      fz_layout_document(ctx, doc, 595.276f, 841.89f, 12.0f);
    }

    pageCount = fz_count_pages(ctx, doc);
    if (pageCount <= 0) fz_throw(ctx, FZ_ERROR_ARGUMENT, "文档没有可渲染页面");
    if (maxPages > 0 && pageCount > maxPages) {
      fz_throw(ctx, FZ_ERROR_ARGUMENT, "首版单次最多导入 500 页");
    }

    result.pages.reserve(static_cast<size_t>(pageCount));
    for (int i = 0; i < pageCount; ++i) {
      page = fz_load_page(ctx, doc, i);
      if (!page) fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法加载页面");
      const fz_rect bounds = fz_bound_page(ctx, page);
      const float width = bounds.x1 - bounds.x0;
      const float height = bounds.y1 - bounds.y0;
      if (!(width > 0.0f) || !(height > 0.0f)) {
        fz_throw(ctx, FZ_ERROR_ARGUMENT, "页面尺寸无效");
      }

      const float dpiScale = kRenderDpi / kPointsPerInch;
      const float pixelCapScale = kMaxRenderPixels / std::max(width, height);
      const float scale = std::min(dpiScale, pixelCapScale);
      const fz_matrix ctm = fz_scale(scale, scale);
      pix = fz_new_pixmap_from_page(ctx, page, ctm, fz_device_rgb(ctx), 0);
      if (!pix) fz_throw(ctx, FZ_ERROR_ARGUMENT, "页面渲染失败");

      char pngPath[4096]{};
      char textPath[4096]{};
      std::snprintf(pngPath, sizeof(pngPath), "%s/page-%04d.png",
                    outputDir.c_str(), i + 1);
      std::snprintf(textPath, sizeof(textPath), "%s/page-%04d.txt",
                    outputDir.c_str(), i + 1);
      fz_save_pixmap_as_png(ctx, pix, pngPath);

      stext = fz_new_stext_page_from_page(ctx, page, nullptr);
      if (stext) {
        text_buffer = fz_new_buffer_from_stext_page(ctx, stext);
        if (text_buffer) fz_save_buffer(ctx, text_buffer, textPath);
      }

      result.pages.push_back(
          {static_cast<double>(width), static_cast<double>(height)});

      if (text_buffer) {
        fz_drop_buffer(ctx, text_buffer);
        text_buffer = nullptr;
      }
      if (stext) {
        fz_drop_stext_page(ctx, stext);
        stext = nullptr;
      }
      fz_drop_pixmap(ctx, pix);
      pix = nullptr;
      fz_drop_page(ctx, page);
      page = nullptr;
    }

    result.pageCount = pageCount;
    lookup_metadata(ctx, doc, FZ_META_INFO_TITLE, title, sizeof(title));
    lookup_metadata(ctx, doc, FZ_META_INFO_AUTHOR, author, sizeof(author));
    lookup_metadata(ctx, doc, FZ_META_FORMAT, format, sizeof(format));
  }
  fz_always(ctx) {
    if (text_buffer) fz_drop_buffer(ctx, text_buffer);
    if (stext) fz_drop_stext_page(ctx, stext);
    if (pix) fz_drop_pixmap(ctx, pix);
    if (page) fz_drop_page(ctx, page);
  }
  fz_catch(ctx) {
    result.error = fz_caught_message(ctx);
    result.ok = false;
  }

  if (doc) fz_drop_document(ctx, doc);
  fz_drop_context(ctx);

  if (result.error.empty()) {
    result.ok = true;
    result.title = title;
    result.author = author;
    result.format = format;
  }
  return result;
}

}  // namespace meowo
