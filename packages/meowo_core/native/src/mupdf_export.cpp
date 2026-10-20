#include "mupdf_export.h"

#include <mupdf/fitz.h>
#include <mupdf/pdf.h>

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace meowo {
namespace {

constexpr const char* kFallbackVectorFailed = "vector_render_failed";
constexpr const char* kFallbackMissingBitmap = "missing_page_bitmap";
constexpr const char* kFallbackSourceUnavailable = "source_unavailable";

std::string catch_message(fz_context* ctx) {
  const char* message = fz_caught_message(ctx);
  return message ? message : "未知错误";
}

bool cancel_requested(const std::string& path) {
  if (path.empty()) return false;
  std::error_code ec;
  return fs::exists(path, ec);
}

void write_progress(const std::string& path, const char* phase, int completed,
                    int total, int page_number) {
  if (path.empty()) return;
  try {
    const json value{{"phase", phase},
                     {"completed", completed},
                     {"total", total},
                     {"pageNumber", page_number}};
    const fs::path target(path);
    const fs::path temp = target.string() + ".tmp";
    {
      std::ofstream out(temp, std::ios::binary | std::ios::trunc);
      if (!out) return;
      const std::string text = value.dump();
      out.write(text.data(), static_cast<std::streamsize>(text.size()));
      out.flush();
      if (!out) return;
    }
    std::error_code ec;
    fs::remove(target, ec);
    fs::rename(temp, target, ec);
  } catch (...) {
    // Progress reporting must never break the export itself.
  }
}

void append_matrix(fz_context* ctx, fz_buffer* buffer, fz_matrix matrix) {
  fz_append_printf(ctx, buffer, "%g %g %g %g %g %g cm\n", matrix.a, matrix.b,
                   matrix.c, matrix.d, matrix.e, matrix.f);
}

double apply_pressure_curve(double pressure,
                            const std::vector<std::pair<double, double>>& curve) {
  const double value = std::clamp(pressure, 0.0, 1.0);
  if (curve.size() < 2) return value;
  for (size_t i = 1; i < curve.size(); ++i) {
    const auto [ax, ay] = curve[i - 1];
    const auto [bx, by] = curve[i];
    if (value <= bx) {
      const double span = bx - ax;
      if (std::abs(span) < 0.000001) return std::clamp(by, 0.0, 1.0);
      const double t = (value - ax) / span;
      return std::clamp(ay + (by - ay) * t, 0.0, 1.0);
    }
  }
  return std::clamp(curve.back().second, 0.0, 1.0);
}

void append_circle(fz_context* ctx, fz_buffer* buffer, double x, double y,
                   double radius) {
  constexpr double k = 0.5522847498307936;
  const double c = radius * k;
  fz_append_printf(ctx, buffer, "%g %g m\n", x + radius, y);
  fz_append_printf(ctx, buffer, "%g %g %g %g %g %g c\n", x + radius, y + c,
                   x + c, y + radius, x, y + radius);
  fz_append_printf(ctx, buffer, "%g %g %g %g %g %g c\n", x - c, y + radius,
                   x - radius, y + c, x - radius, y);
  fz_append_printf(ctx, buffer, "%g %g %g %g %g %g c\n", x - radius, y - c,
                   x - c, y - radius, x, y - radius);
  fz_append_printf(ctx, buffer, "%g %g %g %g %g %g c\n", x + c, y - radius,
                   x + radius, y - c, x + radius, y);
  fz_append_string(ctx, buffer, "f\n");
}

struct PathAppend {
  fz_context* ctx = nullptr;
  fz_path* path = nullptr;
};

void path_moveto(fz_context*, void* arg, float x, float y) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_moveto(state->ctx, state->path, x, y);
}
void path_lineto(fz_context*, void* arg, float x, float y) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_lineto(state->ctx, state->path, x, y);
}
void path_curveto(fz_context*, void* arg, float x1, float y1, float x2,
                  float y2, float x3, float y3) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_curveto(state->ctx, state->path, x1, y1, x2, y2, x3, y3);
}
void path_closepath(fz_context*, void* arg) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_closepath(state->ctx, state->path);
}
void path_quadto(fz_context*, void* arg, float x1, float y1, float x2,
                 float y2) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_quadto(state->ctx, state->path, x1, y1, x2, y2);
}
void path_curvetov(fz_context*, void* arg, float x2, float y2, float x3,
                   float y3) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_curvetov(state->ctx, state->path, x2, y2, x3, y3);
}
void path_curvetoy(fz_context*, void* arg, float x1, float y1, float x3,
                   float y3) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_curvetoy(state->ctx, state->path, x1, y1, x3, y3);
}
void path_rectto(fz_context*, void* arg, float x1, float y1, float x2,
                 float y2) {
  PathAppend* state = static_cast<PathAppend*>(arg);
  fz_rectto(state->ctx, state->path, x1, y1, x2, y2);
}

const fz_path_walker kCopyPathWalker{
    path_moveto, path_lineto,  path_curveto, path_closepath,
    path_quadto, path_curvetov, path_curvetoy, path_rectto,
};

void append_path_copy(fz_context* ctx, fz_path* target, fz_path* source) {
  PathAppend state{ctx, target};
  fz_walk_path(ctx, source, &kCopyPathWalker, &state);
}

// A device that forwards every PDF-producing operation to an inner PDF device
// while turning text into glyph outlines. This is what removes the source text
// layer from the exported PDF: the result contains only paths and images.
struct FlattenDevice {
  fz_device super;
  fz_device* target = nullptr;
  int unsupported = 0;
};

FlattenDevice* flatten_cast(fz_device* dev) {
  return reinterpret_cast<FlattenDevice*>(dev);
}

void flatten_close(fz_context* ctx, fz_device* dev) {
  FlattenDevice* self = flatten_cast(dev);
  if (self->target) fz_close_device(ctx, self->target);
}
void flatten_drop(fz_context* ctx, fz_device* dev) {
  FlattenDevice* self = flatten_cast(dev);
  if (self->target) fz_drop_device(ctx, self->target);
  self->target = nullptr;
}
void flatten_fill_path(fz_context* ctx, fz_device* dev, const fz_path* path,
                       int even_odd, fz_matrix ctm, fz_colorspace* cs,
                       const float* color, float alpha, fz_color_params cp) {
  fz_fill_path(ctx, flatten_cast(dev)->target, path, even_odd, ctm, cs, color,
               alpha, cp);
}
void flatten_stroke_path(fz_context* ctx, fz_device* dev, const fz_path* path,
                         const fz_stroke_state* stroke, fz_matrix ctm,
                         fz_colorspace* cs, const float* color, float alpha,
                         fz_color_params cp) {
  fz_stroke_path(ctx, flatten_cast(dev)->target, path, stroke, ctm, cs, color,
                 alpha, cp);
}
void flatten_clip_path(fz_context* ctx, fz_device* dev, const fz_path* path,
                       int even_odd, fz_matrix ctm, fz_rect scissor) {
  fz_clip_path(ctx, flatten_cast(dev)->target, path, even_odd, ctm, scissor);
}
void flatten_clip_stroke_path(fz_context* ctx, fz_device* dev,
                              const fz_path* path,
                              const fz_stroke_state* stroke, fz_matrix ctm,
                              fz_rect scissor) {
  fz_clip_stroke_path(ctx, flatten_cast(dev)->target, path, stroke, ctm,
                      scissor);
}

template <typename Callback>
void for_each_glyph(fz_context* ctx, FlattenDevice* self, const fz_text* text,
                    fz_matrix ctm, Callback&& callback) {
  fz_text_span* span = text ? text->head : nullptr;
  fz_var(span);
  for (; span;
       span = span->next) {
    if (!span->font) continue;
    fz_matrix tm = span->trm;
    for (int i = 0; i < span->len; ++i) {
      const fz_text_item* item = &span->items[i];
      if (item->gid < 0) continue;
      tm.e = item->x;
      tm.f = item->y;
      const fz_matrix trm = fz_concat(tm, ctm);
      fz_path* path = fz_outline_glyph(ctx, span->font, item->gid, trm);
      if (!path) {
        self->unsupported = 1;
        continue;
      }
      fz_try(ctx) { callback(path); }
      fz_always(ctx) { fz_drop_path(ctx, path); }
      fz_catch(ctx) { fz_rethrow(ctx); }
    }
  }
}

void flatten_fill_text(fz_context* ctx, fz_device* dev, const fz_text* text,
                       fz_matrix ctm, fz_colorspace* cs, const float* color,
                       float alpha, fz_color_params cp) {
  FlattenDevice* self = flatten_cast(dev);
  for_each_glyph(ctx, self, text, ctm, [&](fz_path* path) {
    fz_fill_path(ctx, self->target, path, 0, fz_identity, cs, color, alpha,
                 cp);
  });
}
void flatten_stroke_text(fz_context* ctx, fz_device* dev, const fz_text* text,
                         const fz_stroke_state* stroke, fz_matrix ctm,
                         fz_colorspace* cs, const float* color, float alpha,
                         fz_color_params cp) {
  FlattenDevice* self = flatten_cast(dev);
  for_each_glyph(ctx, self, text, ctm, [&](fz_path* path) {
    fz_stroke_path(ctx, self->target, path, stroke, fz_identity, cs, color,
                   alpha, cp);
  });
}
void flatten_clip_text(fz_context* ctx, fz_device* dev, const fz_text* text,
                       fz_matrix ctm, fz_rect scissor) {
  FlattenDevice* self = flatten_cast(dev);
  fz_path* combined = fz_new_path(ctx);
  fz_try(ctx) {
    for_each_glyph(ctx, self, text, ctm, [&](fz_path* path) {
      append_path_copy(ctx, combined, path);
    });
    fz_clip_path(ctx, self->target, combined, 0, fz_identity, scissor);
  }
  fz_always(ctx) { fz_drop_path(ctx, combined); }
  fz_catch(ctx) { fz_rethrow(ctx); }
}
void flatten_clip_stroke_text(fz_context* ctx, fz_device* dev,
                              const fz_text* text,
                              const fz_stroke_state* stroke, fz_matrix ctm,
                              fz_rect scissor) {
  FlattenDevice* self = flatten_cast(dev);
  fz_path* combined = fz_new_path(ctx);
  fz_try(ctx) {
    for_each_glyph(ctx, self, text, ctm, [&](fz_path* path) {
      append_path_copy(ctx, combined, path);
    });
    fz_clip_stroke_path(ctx, self->target, combined, stroke, fz_identity,
                        scissor);
  }
  fz_always(ctx) { fz_drop_path(ctx, combined); }
  fz_catch(ctx) { fz_rethrow(ctx); }
}
void flatten_ignore_text(fz_context*, fz_device*, const fz_text*, fz_matrix) {}

void flatten_fill_shade(fz_context* ctx, fz_device* dev, fz_shade* shade,
                        fz_matrix ctm, float alpha, fz_color_params cp) {
  fz_fill_shade(ctx, flatten_cast(dev)->target, shade, ctm, alpha, cp);
}
void flatten_fill_image(fz_context* ctx, fz_device* dev, fz_image* image,
                        fz_matrix ctm, float alpha, fz_color_params cp) {
  fz_fill_image(ctx, flatten_cast(dev)->target, image, ctm, alpha, cp);
}
void flatten_fill_image_mask(fz_context* ctx, fz_device* dev, fz_image* image,
                             fz_matrix ctm, fz_colorspace* cs,
                             const float* color, float alpha,
                             fz_color_params cp) {
  fz_fill_image_mask(ctx, flatten_cast(dev)->target, image, ctm, cs, color,
                     alpha, cp);
}
void flatten_clip_image_mask(fz_context* ctx, fz_device* dev, fz_image* image,
                             fz_matrix ctm, fz_rect scissor) {
  fz_clip_image_mask(ctx, flatten_cast(dev)->target, image, ctm, scissor);
}
void flatten_pop_clip(fz_context* ctx, fz_device* dev) {
  fz_pop_clip(ctx, flatten_cast(dev)->target);
}
void flatten_begin_mask(fz_context* ctx, fz_device* dev, fz_rect area,
                        int luminosity, fz_colorspace* cs, const float* bc,
                        fz_color_params cp) {
  fz_begin_mask(ctx, flatten_cast(dev)->target, area, luminosity, cs, bc, cp);
}
void flatten_end_mask(fz_context* ctx, fz_device* dev, fz_function* fn) {
  fz_end_mask_tr(ctx, flatten_cast(dev)->target, fn);
}
void flatten_begin_group(fz_context* ctx, fz_device* dev, fz_rect area,
                         fz_colorspace* cs, int isolated, int knockout,
                         int blendmode, float alpha) {
  fz_begin_group(ctx, flatten_cast(dev)->target, area, cs, isolated, knockout,
                 blendmode, alpha);
}
void flatten_end_group(fz_context* ctx, fz_device* dev) {
  fz_end_group(ctx, flatten_cast(dev)->target);
}
int flatten_begin_tile(fz_context* ctx, fz_device* dev, fz_rect area,
                       fz_rect view, float xstep, float ystep, fz_matrix ctm,
                       int id) {
  return fz_begin_tile_id(ctx, flatten_cast(dev)->target, area, view, xstep,
                          ystep, ctm, id);
}
void flatten_end_tile(fz_context* ctx, fz_device* dev) {
  fz_end_tile(ctx, flatten_cast(dev)->target);
}
void flatten_render_flags(fz_context* ctx, fz_device* dev, int set, int clear) {
  fz_render_flags(ctx, flatten_cast(dev)->target, set, clear);
}
void flatten_set_default_colorspaces(fz_context* ctx, fz_device* dev,
                                     fz_default_colorspaces* cs) {
  fz_set_default_colorspaces(ctx, flatten_cast(dev)->target, cs);
}
void flatten_begin_layer(fz_context* ctx, fz_device* dev, const char* name) {
  fz_begin_layer(ctx, flatten_cast(dev)->target, name);
}
void flatten_end_layer(fz_context* ctx, fz_device* dev) {
  fz_end_layer(ctx, flatten_cast(dev)->target);
}
// Structure/metatext can carry /ActualText, which would reintroduce a
// selectable text layer. A flattened export intentionally drops both.
void flatten_begin_structure(fz_context*, fz_device*, fz_structure, const char*,
                             int) {}
void flatten_end_structure(fz_context*, fz_device*) {}
void flatten_begin_metatext(fz_context*, fz_device*, fz_metatext, const char*) {}
void flatten_end_metatext(fz_context*, fz_device*) {}

fz_device* new_flatten_device(fz_context* ctx, fz_device* target) {
  FlattenDevice* dev = fz_new_derived_device(ctx, FlattenDevice);
  dev->target = fz_keep_device(ctx, target);
  dev->unsupported = 0;
  dev->super.close_device = flatten_close;
  dev->super.drop_device = flatten_drop;
  dev->super.fill_path = flatten_fill_path;
  dev->super.stroke_path = flatten_stroke_path;
  dev->super.clip_path = flatten_clip_path;
  dev->super.clip_stroke_path = flatten_clip_stroke_path;
  dev->super.fill_text = flatten_fill_text;
  dev->super.stroke_text = flatten_stroke_text;
  dev->super.clip_text = flatten_clip_text;
  dev->super.clip_stroke_text = flatten_clip_stroke_text;
  dev->super.ignore_text = flatten_ignore_text;
  dev->super.fill_shade = flatten_fill_shade;
  dev->super.fill_image = flatten_fill_image;
  dev->super.fill_image_mask = flatten_fill_image_mask;
  dev->super.clip_image_mask = flatten_clip_image_mask;
  dev->super.pop_clip = flatten_pop_clip;
  dev->super.begin_mask = flatten_begin_mask;
  dev->super.end_mask = flatten_end_mask;
  dev->super.begin_group = flatten_begin_group;
  dev->super.end_group = flatten_end_group;
  dev->super.begin_tile = flatten_begin_tile;
  dev->super.end_tile = flatten_end_tile;
  dev->super.render_flags = flatten_render_flags;
  dev->super.set_default_colorspaces = flatten_set_default_colorspaces;
  dev->super.begin_layer = flatten_begin_layer;
  dev->super.end_layer = flatten_end_layer;
  dev->super.begin_structure = flatten_begin_structure;
  dev->super.end_structure = flatten_end_structure;
  dev->super.begin_metatext = flatten_begin_metatext;
  dev->super.end_metatext = flatten_end_metatext;
  return reinterpret_cast<fz_device*>(dev);
}

void add_extgstate(fz_context* ctx, pdf_document* doc, pdf_obj* gstates,
                   const std::string& name, double alpha, bool multiply) {
  pdf_obj* state = pdf_new_dict(ctx, doc, 4);
  pdf_dict_put(ctx, state, PDF_NAME(Type), PDF_NAME(ExtGState));
  pdf_dict_put_real(ctx, state, PDF_NAME(ca), alpha);
  pdf_dict_put_real(ctx, state, PDF_NAME(CA), alpha);
  if (multiply) pdf_dict_put(ctx, state, PDF_NAME(BM), PDF_NAME(Multiply));
  pdf_dict_puts_drop(ctx, gstates, name.c_str(), state);
}

void ensure_resource_dict(fz_context* ctx, pdf_document* doc,
                          pdf_obj* resources, pdf_obj* key, pdf_obj** out) {
  pdf_obj* dict = pdf_dict_get(ctx, resources, key);
  if (!pdf_is_dict(ctx, dict)) {
    dict = pdf_new_dict(ctx, doc, 0);
    pdf_dict_put_drop(ctx, resources, key, dict);
  }
  *out = dict;
}

void append_strokes(fz_context* ctx, pdf_document* doc, pdf_obj* resources,
                    fz_buffer* content, const std::vector<ExportStroke>& strokes) {
  if (strokes.empty()) return;
  pdf_obj* extgstates = nullptr;
  ensure_resource_dict(ctx, doc, resources, PDF_NAME(ExtGState), &extgstates);
  std::unordered_map<std::string, std::string> names;
  fz_append_string(ctx, content, "q\n1 J\n1 j\n");
  for (const ExportStroke& stroke : strokes) {
    if (stroke.points.empty() || !(stroke.width > 0.0)) continue;
    const double alpha =
        stroke.highlighter ? std::clamp(0.32 * stroke.opacity, 0.0, 1.0)
                           : std::clamp(stroke.opacity, 0.0, 1.0);
    if (alpha <= 0.0) continue;
    char key[64];
    std::snprintf(key, sizeof(key), "%.4f/%d", alpha,
                  stroke.highlighter ? 1 : 0);
    std::string name;
    const auto found = names.find(key);
    if (found != names.end()) {
      name = found->second;
    } else {
      name = "GS" + std::to_string(names.size());
      names.emplace(key, name);
      add_extgstate(ctx, doc, extgstates, name, alpha, stroke.highlighter);
    }
    const double r = ((stroke.rgb >> 16) & 0xff) / 255.0;
    const double g = ((stroke.rgb >> 8) & 0xff) / 255.0;
    const double b = (stroke.rgb & 0xff) / 255.0;
    fz_append_printf(ctx, content, "q /%s gs %g %g %g RG %g %g %g rg\n",
                     name.c_str(), r, g, b, r, g, b);
    if (stroke.points.size() == 1) {
      const auto& point = stroke.points.front();
      const double pressure =
          apply_pressure_curve(point.pressure, stroke.pressureCurve);
      const double radius = stroke.width * (0.45 + pressure * 0.85) * 0.5;
      append_circle(ctx, content, point.x, point.y, radius);
      fz_append_string(ctx, content, "Q\n");
      continue;
    }
    for (size_t i = 1; i < stroke.points.size(); ++i) {
      const auto& start = stroke.points[i - 1];
      const auto& end = stroke.points[i];
      const double p = apply_pressure_curve(end.pressure, stroke.pressureCurve);
      const double p0 =
          apply_pressure_curve(start.pressure, stroke.pressureCurve);
      const double pressure = std::clamp((p + p0) / 2.0, 0.05, 1.0);
      const double width = stroke.width * (0.45 + pressure * 0.85);
      fz_append_printf(ctx, content, "%g w\n%g %g m\n%g %g l\nS\n", width,
                       start.x, start.y, end.x, end.y);
    }
    fz_append_string(ctx, content, "Q\n");
  }
  fz_append_string(ctx, content, "Q\n");
}

bool append_image(fz_context* ctx, pdf_document* doc, pdf_obj* resources,
                  fz_buffer* content, const std::string& png,
                  fz_matrix image_matrix, std::string* error = nullptr) {
  if (png.empty()) return false;
  fz_buffer* encoded = nullptr;
  fz_image* image = nullptr;
  pdf_obj* image_ref = nullptr;
  pdf_obj* xobjects = nullptr;
  bool ok = false;
  fz_var(encoded);
  fz_var(image);
  fz_var(image_ref);
  fz_var(ok);
  fz_try(ctx) {
    encoded = fz_new_buffer_from_copied_data(
        ctx, reinterpret_cast<const unsigned char*>(png.data()), png.size());
    image = fz_new_image_from_buffer(ctx, encoded);
    if (!image) fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法解码叠加位图");
    image_ref = pdf_add_image(ctx, doc, image);
    ensure_resource_dict(ctx, doc, resources, PDF_NAME(XObject), &xobjects);
    char name[32];
    std::snprintf(name, sizeof(name), "Im%d", pdf_dict_len(ctx, xobjects));
    pdf_dict_puts(ctx, xobjects, name, image_ref);
    fz_append_printf(ctx, content, "q\n");
    append_matrix(ctx, content, image_matrix);
    fz_append_printf(ctx, content, "/%s Do\nQ\n", name);
    ok = true;
  }
  fz_always(ctx) {
    if (image_ref) pdf_drop_obj(ctx, image_ref);
    if (image) fz_drop_image(ctx, image);
    if (encoded) fz_drop_buffer(ctx, encoded);
  }
  fz_catch(ctx) {
    // The caller decides whether a missing overlay is fatal or a warning.
    if (error) *error = catch_message(ctx);
    ok = false;
  }
  return ok;
}

void append_page_overlays(fz_context* ctx, pdf_document* doc,
                          pdf_obj* resources, fz_buffer* content,
                          const BookExportPage& page, fz_matrix outer,
                          double display_width, double display_height,
                          std::vector<std::string>& warnings) {
  fz_append_string(ctx, content, "q\n");
  append_matrix(ctx, content, outer);
  append_strokes(ctx, doc, resources, content, page.strokes);
  if (!page.overlayPath.empty()) {
    std::error_code ec;
    std::string bytes;
    if (fs::exists(page.overlayPath, ec)) {
      std::ifstream in(page.overlayPath, std::ios::binary);
      if (in) {
        bytes.assign(std::istreambuf_iterator<char>(in),
                     std::istreambuf_iterator<char>());
      }
    }
    if (!bytes.empty()) {
      const fz_matrix placement{static_cast<float>(display_width), 0, 0,
                                static_cast<float>(-display_height), 0,
                                static_cast<float>(display_height)};
      std::string image_error;
      if (!append_image(ctx, doc, resources, content, bytes, placement,
                        &image_error)) {
        warnings.push_back("第 " + std::to_string(page.pageNumber) +
                           " 页文字/图片叠加层无法嵌入: " + image_error);
      }
    }
  }
  fz_append_string(ctx, content, "Q\n");
}

void copy_page_attributes(fz_context* ctx, pdf_document* output,
                          pdf_obj* source_page, pdf_obj* target_page) {
  static pdf_obj* const kBoxes[] = {
      PDF_NAME(MediaBox), PDF_NAME(CropBox),  PDF_NAME(BleedBox),
      PDF_NAME(TrimBox),  PDF_NAME(ArtBox),
  };
  for (pdf_obj* key : kBoxes) {
    pdf_obj* value = pdf_dict_get_inheritable(ctx, source_page, key);
    if (value) {
      pdf_dict_put_rect(ctx, target_page, key, pdf_to_rect(ctx, value));
    }
  }
  const int rotate =
      pdf_dict_get_inheritable_int(ctx, source_page, PDF_NAME(Rotate));
  if (rotate != 0) {
    pdf_dict_put_int(ctx, target_page, PDF_NAME(Rotate), rotate);
  }
  const float user_unit =
      pdf_dict_get_inheritable_real(ctx, source_page, PDF_NAME(UserUnit));
  if (user_unit > 0 && std::abs(user_unit - 1.0f) > 0.00001f) {
    pdf_dict_put_real(ctx, target_page, PDF_NAME(UserUnit), user_unit);
  }
  // Page-level transparency groups affect blending of the flattened content.
  pdf_obj* group = pdf_dict_get(ctx, source_page, PDF_NAME(Group));
  if (group) {
    pdf_dict_put_drop(ctx, target_page, PDF_NAME(Group),
                      pdf_graft_object(ctx, output, group));
  }
}

}  // namespace

BookExportResult build_book_pdf(const BookExportRequest& request) {
  BookExportResult result;
  const int total = static_cast<int>(request.pages.size());
  if (total <= 0) {
    result.error = "没有可导出的页面";
    return result;
  }
  if (cancel_requested(request.cancelPath)) {
    result.cancelled = true;
    return result;
  }

  fz_context* ctx = fz_new_context(nullptr, nullptr, FZ_STORE_DEFAULT);
  if (!ctx) {
    result.error = "无法创建 MuPDF 上下文";
    return result;
  }
  fz_register_document_handlers(ctx);

  fz_document* source_doc = nullptr;
  fz_stream* source_stream = nullptr;
  pdf_document* source_pdf = nullptr;
  pdf_document* output = nullptr;
  bool source_usable = !request.sourcePdf.empty();
  std::string source_error;
  if (request.sourceEncrypted) {
    source_usable = false;
    source_error = "encrypted_pdf_no_password";
  }

  fz_var(source_doc);
  fz_var(source_stream);
  fz_var(source_pdf);
  fz_var(output);
  fz_var(source_usable);

  fz_try(ctx) {
    if (source_usable) {
      source_stream = fz_open_memory(
          ctx, reinterpret_cast<const unsigned char*>(request.sourcePdf.data()),
          request.sourcePdf.size());
      source_doc = fz_open_document_with_stream(ctx, "application/pdf",
                                                source_stream);
      fz_drop_stream(ctx, source_stream);
      source_stream = nullptr;
      if (!source_doc) {
        source_usable = false;
        source_error = "source_open_failed";
      } else if (fz_needs_password(ctx, source_doc)) {
        source_usable = false;
        source_error = "encrypted_pdf_no_password";
      } else {
        source_pdf = pdf_specifics(ctx, source_doc);
        if (!source_pdf) {
          source_usable = false;
          source_error = "source_not_pdf";
        }
      }
    }
    output = pdf_create_document(ctx);
    if (!output) fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法创建 PDF 写入器");
  }
  fz_catch(ctx) {
    result.error = catch_message(ctx);
    if (source_stream) fz_drop_stream(ctx, source_stream);
    if (source_doc) fz_drop_document(ctx, source_doc);
    if (output) pdf_drop_document(ctx, output);
    fz_drop_context(ctx);
    return result;
  }

  write_progress(request.progressPath, "exporting", 0, total, 0);

  int i = 0;
  fz_var(i);
  for (i = 0; i < total; ++i) {
    if (cancel_requested(request.cancelPath)) {
      result.cancelled = true;
      break;
    }
    const BookExportPage& page = request.pages[static_cast<size_t>(i)];
    bool fallback = page.forceFallback || page.notePage ||
                    !source_usable || page.sourceIndex < 0;
    std::string fallback_reason = page.fallbackReason;
    std::string fallback_detail = page.fallbackDetail;
    if (!page.notePage && page.sourceIndex < 0 && fallback_reason.empty()) {
      fallback_reason = kFallbackSourceUnavailable;
    }
    if (!page.notePage && !source_usable && fallback_reason.empty()) {
      fallback_reason = source_error.empty() ? kFallbackSourceUnavailable
                                             : source_error;
    }
    if (!page.notePage && page.forceFallback && fallback_reason.empty()) {
      fallback_reason = kFallbackSourceUnavailable;
    }

    bool inserted = false;
    fz_var(inserted);
    if (!fallback) {
      // Build the vector source page. The page is only inserted after every
      // step succeeds so a failure can be replaced by the PNG fallback.
      fz_page* source_page = nullptr;
      pdf_obj* resources = nullptr;
      fz_buffer* content = nullptr;
      fz_device* pdf_device = nullptr;
      fz_device* flatten = nullptr;
      pdf_obj* source_page_obj = nullptr;
      pdf_obj* output_page = nullptr;
      pdf_obj* output_ref = nullptr;
      fz_matrix page_ctm = fz_identity;
      fz_rect display_bounds = fz_empty_rect;
      bool unsupported = false;
      std::string vector_error;
      fz_var(source_page);
      fz_var(resources);
      fz_var(content);
      fz_var(pdf_device);
      fz_var(flatten);
      fz_var(output_page);
      fz_var(output_ref);
      fz_var(page_ctm);
      fz_var(display_bounds);
      fz_var(unsupported);

      fz_try(ctx) {
        source_page = fz_load_page(ctx, source_doc, page.sourceIndex);
        if (!source_page) fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法加载源页面");
        pdf_page* source_pdf_page = pdf_page_from_fz_page(ctx, source_page);
        if (!source_pdf_page) fz_throw(ctx, FZ_ERROR_ARGUMENT, "源页面不是 PDF");
        display_bounds = fz_bound_page(ctx, source_page);
        fz_rect crop_box = fz_empty_rect;
        pdf_page_transform(ctx, source_pdf_page, &crop_box, &page_ctm);
        if (!(display_bounds.x1 > display_bounds.x0) ||
            !(display_bounds.y1 > display_bounds.y0)) {
          fz_throw(ctx, FZ_ERROR_ARGUMENT, "源页面尺寸无效");
        }
        const fz_matrix inverse = fz_invert_matrix(page_ctm);
        resources = pdf_new_dict(ctx, output, 4);
        content = fz_new_buffer(ctx, 4096);
        pdf_device =
            pdf_new_pdf_device(ctx, output, inverse, resources, content);
        flatten = new_flatten_device(ctx, pdf_device);
        fz_run_page_contents(ctx, source_page, flatten, fz_identity, nullptr);
        fz_close_device(ctx, flatten);
        unsupported = flatten_cast(flatten)->unsupported;
        fz_drop_device(ctx, flatten);
        flatten = nullptr;
        pdf_device = nullptr;
        if (unsupported) {
          fz_throw(ctx, FZ_ERROR_ARGUMENT,
                   "页面包含无法转为轮廓的文字，已回退位图");
        }

        const double page_width =
            page.width > 0 ? page.width : display_bounds.x1 - display_bounds.x0;
        const double page_height = page.height > 0
                                       ? page.height
                                       : display_bounds.y1 - display_bounds.y0;
        const double sx =
            page_width > 0
                ? (display_bounds.x1 - display_bounds.x0) / page_width
                : 1.0;
        const double sy =
            page_height > 0
                ? (display_bounds.y1 - display_bounds.y0) / page_height
                : 1.0;
        const fz_matrix outer =
            fz_concat(inverse, fz_scale(static_cast<float>(sx),
                                        static_cast<float>(sy)));
        append_page_overlays(ctx, output, resources, content, page, outer,
                             display_bounds.x1 - display_bounds.x0,
                             display_bounds.y1 - display_bounds.y0,
                             result.warnings);

        source_page_obj = pdf_lookup_page_obj(ctx, source_pdf, page.sourceIndex);
        if (!source_page_obj) {
          fz_throw(ctx, FZ_ERROR_ARGUMENT, "无法读取源页面对象");
        }
        output_page = pdf_new_dict(ctx, output, 8);
        pdf_dict_put(ctx, output_page, PDF_NAME(Type), PDF_NAME(Page));
        copy_page_attributes(ctx, output, source_page_obj, output_page);
        pdf_dict_put_drop(ctx, output_page, PDF_NAME(Resources), resources);
        resources = nullptr;
        pdf_dict_put_drop(ctx, output_page, PDF_NAME(Contents),
                          pdf_add_stream(ctx, output, content, nullptr, 1));
        output_ref = pdf_add_object_drop(ctx, output, output_page);
        output_page = nullptr;
        pdf_insert_page(ctx, output, -1, output_ref);
        inserted = true;
      }
      fz_always(ctx) {
        if (flatten) {
          fz_drop_device(ctx, flatten);
          flatten = nullptr;
          pdf_device = nullptr;
        }
        if (pdf_device) fz_drop_device(ctx, pdf_device);
        if (content) fz_drop_buffer(ctx, content);
        if (resources) pdf_drop_obj(ctx, resources);
        if (output_ref) pdf_drop_obj(ctx, output_ref);
        if (output_page) pdf_drop_obj(ctx, output_page);
        if (source_page) fz_drop_page(ctx, source_page);
      }
      fz_catch(ctx) {
        vector_error = catch_message(ctx);
      }
      if (inserted) {
        result.vectorPages.push_back(page.pageNumber);
        result.exportedPages.push_back(page.pageNumber);
        write_progress(request.progressPath, "exporting", i + 1, total,
                       page.pageNumber);
        continue;
      }
      fallback = true;
      fallback_reason = kFallbackVectorFailed;
      fallback_detail = vector_error;
    }

    // Raster fallback (also used for note pages when no vector source exists).
    pdf_obj* resources = pdf_new_dict(ctx, output, 4);
    fz_buffer* content = fz_new_buffer(ctx, 4096);
    pdf_obj* page_obj = nullptr;
    bool page_ok = false;
    std::string raster_error;
    double display_width = page.width > 0 ? page.width : 595.276;
    double display_height = page.height > 0 ? page.height : 841.89;
    fz_var(resources);
    fz_var(content);
    fz_var(page_obj);
    fz_var(page_ok);
    fz_var(display_width);
    fz_var(display_height);
    const double sx =
        page.width > 0 ? display_width / page.width : 1.0;
    const double sy =
        page.height > 0 ? display_height / page.height : 1.0;
    const fz_matrix outer = fz_scale(static_cast<float>(sx),
                                     static_cast<float>(sy));

    if (!page.notePage && page.loadFallbackPng) {
      std::string png;
      try {
        png = page.loadFallbackPng();
      } catch (const std::exception& e) {
        fallback_detail = e.what();
      }
      if (!png.empty()) {
        const fz_matrix placement{static_cast<float>(display_width), 0, 0,
                                  static_cast<float>(-display_height), 0,
                                  static_cast<float>(display_height)};
        std::string image_error;
        if (!append_image(ctx, output, resources, content, png, placement,
                          &image_error)) {
          result.warnings.push_back("第 " + std::to_string(page.pageNumber) +
                                    " 页 PNG 回退位图无法嵌入: " +
                                    image_error);
        }
      } else {
        fallback_reason = kFallbackMissingBitmap;
        result.warnings.push_back("第 " + std::to_string(page.pageNumber) +
                                  " 页缺少 PNG 回退位图");
      }
    }

    fz_try(ctx) {
      append_page_overlays(ctx, output, resources, content, page, outer,
                           display_width, display_height, result.warnings);
      page_obj = pdf_new_dict(ctx, output, 6);
      pdf_dict_put(ctx, page_obj, PDF_NAME(Type), PDF_NAME(Page));
      pdf_dict_put_rect(ctx, page_obj, PDF_NAME(MediaBox),
                        fz_make_rect(0, 0, static_cast<float>(display_width),
                                     static_cast<float>(display_height)));
      pdf_dict_put_drop(ctx, page_obj, PDF_NAME(Resources), resources);
      resources = nullptr;
      pdf_dict_put_drop(ctx, page_obj, PDF_NAME(Contents),
                        pdf_add_stream(ctx, output, content, nullptr, 1));
      pdf_obj* ref = pdf_add_object_drop(ctx, output, page_obj);
      page_obj = nullptr;
      pdf_insert_page(ctx, output, -1, ref);
      pdf_drop_obj(ctx, ref);
      page_ok = true;
    }
    fz_always(ctx) {
      if (page_obj) pdf_drop_obj(ctx, page_obj);
      if (content) fz_drop_buffer(ctx, content);
      if (resources) pdf_drop_obj(ctx, resources);
    }
    fz_catch(ctx) {
      raster_error = catch_message(ctx);
    }
    if (!page_ok) {
      result.error = "第 " + std::to_string(page.pageNumber) +
                     " 页写入失败: " + raster_error;
      result.ok = false;
      break;
    }
    if (!page.notePage) {
      BookExportFallback entry;
      entry.pageNumber = page.pageNumber;
      entry.reason = fallback_reason.empty() ? kFallbackSourceUnavailable
                                             : fallback_reason;
      entry.detail = fallback_detail;
      result.fallbackPages.push_back(entry);
    }
    result.exportedPages.push_back(page.pageNumber);
    write_progress(request.progressPath, "exporting", i + 1, total,
                   page.pageNumber);
  }

  if (result.cancelled) {
    write_progress(request.progressPath, "cancelled",
                   static_cast<int>(result.exportedPages.size()), total, 0);
  } else if (result.error.empty()) {
    write_progress(request.progressPath, "saving", total, total, 0);
    pdf_write_options options = pdf_default_write_options;
    options.do_compress = 1;
    options.do_garbage = 1;
    fz_try(ctx) {
      pdf_save_document(ctx, output, request.targetPath.c_str(), &options);
      result.ok = true;
    }
    fz_catch(ctx) {
      result.error = "保存 PDF 失败: " + catch_message(ctx);
      result.ok = false;
    }
    if (result.ok) {
      std::error_code ec;
      result.outputBytes = fs::file_size(request.targetPath, ec);
      if (ec) result.outputBytes = 0;
      write_progress(request.progressPath, "done", total, total, 0);
    }
  }

  if (output) pdf_drop_document(ctx, output);
  if (source_doc) fz_drop_document(ctx, source_doc);
  fz_drop_context(ctx);
  return result;
}

}  // namespace meowo
