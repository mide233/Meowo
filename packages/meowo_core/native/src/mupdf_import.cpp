#include "mupdf_import.h"

#include <mupdf/fitz.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <unordered_map>

namespace meowo {
namespace {

constexpr float kRenderDpi = 120.0f;
constexpr float kPointsPerInch = 72.0f;
constexpr float kMaxRenderPixels = 5000.0f;
constexpr int kMetaBuffer = 512;
// A single page is returned through JSON/FFI; keep the transfer bounded.
constexpr size_t kMaxSvgBytes = 24ull * 1024ull * 1024ull;
constexpr size_t kMaxBatchSvgBytes = 48ull * 1024ull * 1024ull;
// vector_graphics_compiler rejects documents with more than 1000 <use>
// expansions. Font glyph references are inlined below; anything left is
// treated as unsupported so the caller keeps the PNG snapshot.
constexpr int kMaxUnresolvedUseRefs = 800;

std::string attr_value(const std::string& tag, const std::string& name) {
  const std::string needle = " " + name + "=\"";
  const size_t start = tag.find(needle);
  if (start == std::string::npos) return {};
  const size_t value_start = start + needle.size();
  const size_t end = tag.find('"', value_start);
  if (end == std::string::npos) return {};
  return tag.substr(value_start, end - value_start);
}

void erase_attr(std::string& tag, const std::string& name) {
  const std::string needle = " " + name + "=\"";
  const size_t start = tag.find(needle);
  if (start == std::string::npos) return;
  const size_t value_start = start + needle.size();
  const size_t end = tag.find('"', value_start);
  if (end == std::string::npos) return;
  tag.erase(start, end - start + 1);
}

// MuPDF emits text as <path id="font_x_y"> definitions plus one <use> per
// glyph. Flutter's SVG parser expands every <use> and refuses pages with more
// than 1000 of them, so inline font glyphs as transformed <path> elements.
// Image/pattern <use> nodes are left intact (and capped below).
bool flatten_font_uses(const std::string& svg, std::string& out, std::string& error) {
  std::unordered_map<std::string, std::string> font_paths;
  size_t scan = 0;
  while ((scan = svg.find("<path", scan)) != std::string::npos) {
    const size_t end = svg.find("/>", scan);
    if (end == std::string::npos) break;
    const std::string tag = svg.substr(scan, end - scan + 2);
    const std::string id = attr_value(tag, "id");
    if (id.rfind("font_", 0) == 0) {
      const std::string d = attr_value(tag, "d");
      if (!d.empty()) font_paths.emplace(id, d);
    }
    scan = end + 2;
  }

  out.clear();
  out.reserve(svg.size() + svg.size() / 2);
  size_t pos = 0;
  while (true) {
    const size_t use = svg.find("<use", pos);
    if (use == std::string::npos) {
      out.append(svg, pos, std::string::npos);
      break;
    }
    const size_t end = svg.find("/>", use);
    if (end == std::string::npos) {
      out.append(svg, pos, std::string::npos);
      break;
    }
    out.append(svg, pos, use - pos);
    const std::string tag = svg.substr(use, end - use + 2);
    std::string href = attr_value(tag, "xlink:href");
    if (href.empty()) href = attr_value(tag, "href");
    if (!href.empty() && href.front() == '#') href.erase(0, 1);
    const auto font = font_paths.find(href);
    if (font == font_paths.end()) {
      out.append(tag);
    } else {
      std::string attrs = tag.substr(4, tag.size() - 6);
      erase_attr(attrs, "xlink:href");
      erase_attr(attrs, "href");
      erase_attr(attrs, "data-text");
      while (!attrs.empty() && attrs.back() == ' ') attrs.pop_back();
      out.append("<path");
      out.append(attrs);
      out.append(" d=\"");
      out.append(font->second);
      out.append("\"/>");
    }
    pos = end + 2;
    if (out.size() > kMaxSvgBytes) {
      error = "页面矢量内容过大";
      return false;
    }
  }

  int remaining_uses = 0;
  scan = 0;
  while ((scan = out.find("<use", scan)) != std::string::npos) {
    ++remaining_uses;
    scan += 4;
  }
  if (remaining_uses > kMaxUnresolvedUseRefs) {
    error = "页面矢量引用过多，已回退位图";
    return false;
  }
  if (out.size() > kMaxSvgBytes) {
    error = "页面矢量内容过大";
    return false;
  }
  return true;
}

void render_pdf_page_svg(fz_context* ctx, fz_document* doc, int page_index,
                         MuPdfVectorPage& result) {
  result.pageIndex = page_index;
  fz_page* page = nullptr;
  fz_buffer* buffer = nullptr;
  fz_document_writer* writer = nullptr;
  std::string raw_svg;
  bool rendered = false;
  fz_var(page);
  fz_var(buffer);
  fz_var(writer);
  fz_var(rendered);
  fz_var(raw_svg);

  fz_try(ctx) {
    page = fz_load_page(ctx, doc, page_index);
    if (!page) fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法加载页面");
    const fz_rect bounds = fz_bound_page(ctx, page);
    result.width = bounds.x1 - bounds.x0;
    result.height = bounds.y1 - bounds.y0;
    if (!(result.width > 0.0) || !(result.height > 0.0)) {
      fz_throw(ctx, FZ_ERROR_ARGUMENT, "页面尺寸无效");
    }

    buffer = fz_new_buffer(ctx, 64 * 1024);
    writer = fz_new_document_writer_with_buffer(ctx, buffer, "svg", "text=path");
    fz_device* device = fz_begin_page(ctx, writer, bounds);
    fz_run_page(ctx, page, device, fz_identity, nullptr);
    fz_end_page(ctx, writer);
    fz_close_document_writer(ctx, writer);
    writer = nullptr;

    unsigned char* data = nullptr;
    const size_t length = fz_buffer_storage(ctx, buffer, &data);
    if (!data || length == 0) fz_throw(ctx, FZ_ERROR_ARGUMENT, "页面矢量输出为空");
    raw_svg.assign(reinterpret_cast<const char*>(data), length);
    rendered = true;
  }
  fz_catch(ctx) {
    result.ok = false;
    result.svg.clear();
    result.error = fz_caught_message(ctx);
  }

  if (writer) fz_drop_document_writer(ctx, writer);
  if (buffer) fz_drop_buffer(ctx, buffer);
  if (page) fz_drop_page(ctx, page);
  if (!rendered) return;

  try {
    std::string flattened;
    std::string flatten_error;
    if (!flatten_font_uses(raw_svg, flattened, flatten_error)) {
      result.ok = false;
      result.error = flatten_error;
      return;
    }
    result.svg = std::move(flattened);
    result.ok = true;
  } catch (const std::exception& e) {
    result.ok = false;
    result.error = e.what();
  }
}

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
      result.encrypted = true;
      // fz_needs_password remains true after successful authentication; the
      // return value of fz_authenticate_password is the authoritative result.
      if (password.empty() ||
          fz_authenticate_password(ctx, doc, password.c_str()) == 0) {
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

std::vector<MuPdfVectorPage> render_pdf_pages_svg(
    const std::string& pdfBytes, const std::vector<int>& pageIndexes) {
  std::vector<MuPdfVectorPage> results(pageIndexes.size());
  for (size_t i = 0; i < pageIndexes.size(); ++i) {
    results[i].pageIndex = pageIndexes[i];
  }
  if (pdfBytes.empty()) {
    for (auto& page : results) page.error = "书籍源文件为空";
    return results;
  }

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  if (!ctx) {
    for (auto& page : results) page.error = "无法创建 MuPDF 上下文";
    return results;
  }

  fz_document* doc = nullptr;
  fz_stream* stream = nullptr;
  fz_var(doc);
  fz_var(stream);

  fz_try(ctx) {
    fz_register_document_handlers(ctx);
    stream = fz_open_memory(ctx, reinterpret_cast<const unsigned char*>(pdfBytes.data()),
                            pdfBytes.size());
    doc = fz_open_document_with_stream(ctx, "application/pdf", stream);
    fz_drop_stream(ctx, stream);
    stream = nullptr;
    if (!doc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "MuPDF 无法打开 PDF");
    if (fz_needs_password(ctx, doc)) {
      fz_throw(ctx, FZ_ERROR_ARGUMENT, "文档已加密，保留位图页面");
    }
    const int page_count = fz_count_pages(ctx, doc);
    size_t total_svg_bytes = 0;
    bool batch_full = false;
    for (auto& result : results) {
      if (batch_full) {
        result.error = "批量矢量内容过大";
        continue;
      }
      if (result.pageIndex < 0 || result.pageIndex >= page_count) {
        result.error = "页面序号超出范围";
        continue;
      }
      render_pdf_page_svg(ctx, doc, result.pageIndex, result);
      if (result.ok) {
        total_svg_bytes += result.svg.size();
        if (total_svg_bytes > kMaxBatchSvgBytes) {
          result.ok = false;
          result.svg.clear();
          result.error = "批量矢量内容过大";
          batch_full = true;
        }
      }
    }
  }
  fz_catch(ctx) {
    const std::string message = fz_caught_message(ctx);
    for (auto& result : results) {
      if (!result.ok && result.error.empty()) result.error = message;
    }
  }

  if (stream) fz_drop_stream(ctx, stream);
  if (doc) fz_drop_document(ctx, doc);
  fz_drop_context(ctx);
  return results;
}

}  // namespace meowo
