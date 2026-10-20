# PDF 真矢量页背景交付报告

- 状态：Completed（画布矢量页）；PDF/PNG 导出仍为位图
- 日期：2026-10-20
- 计划：[`pdf-vector-fidelity.md`](../plans/pdf-vector-fidelity.md)
- 关联：[`2026-10-20-alpha4-mupdf.md`](2026-10-20-alpha4-mupdf.md)

## 1. 结果

PDF 书籍页不再固定使用 120 dpi PNG。非加密 PDF 导入时会探测 MuPDF SVG 输出；成功后在文档中记录 `bookSource.vector = "svg"`。编辑时按当前页 ±1 从 `book_source` 原 PDF 生成逐页 SVG，`flutter_svg` 解析为 `ui.Picture`，由 `BookBackgroundPainter` 绘制在独立 `RepaintBoundary` 中。缩放时直接重放矢量路径，文字和线条保持清晰。

PNG 快照仍然保留并继续作为：

- 加密 PDF、EPUB、旧文档（无 `vector` 字段）的背景；
- SVG 解析失败、单页超出限制、非字形引用过多的逐页回退；
- 页面选择器/缩略图与 PDF/PNG 导出的来源。

## 2. 关键实现

### 2.1 C++ 核心

- `mupdf_import.{h,cpp}`
  - 新增 `render_pdf_pages_svg(pdfBytes, pageIndexes)`，每页输出独立 SVG buffer。
  - 使用 `fz_new_document_writer_with_buffer(ctx, buffer, "svg", "text=path")`，文字转为精确路径，不依赖设备字体。
  - `flatten_font_uses` 把 MuPDF 的字形 `<use xlink:href="#font_*">` 内联为带原 `transform` 的 `<path>`，规避 flutter_svg 每个文档最多 1000 次 `<use>` 展开的硬限制。
  - 单页 SVG 上限 24 MiB；剩余非字形 `<use>` 超过 800 时判定该页不支持，回退 PNG。
  - `MuPdfResult.encrypted` 标记需要密码的文档；同时修复 `fz_needs_password` 在认证成功后仍返回 true 导致加密 PDF 即使密码正确也被拒绝的旧问题，认证结果改以 `fz_authenticate_password` 返回值为准。
- `core.cpp`
  - 新增 op `render_book_pages_svg`：一次最多 8 页，读取 `book_source`、打开 MuPDF、返回 `{pages, failures}`；不写入新资产。
  - 导入时对非加密 PDF 探测第 1 页；写入 `bookSource.vector` 与 `bookSource.encrypted`。
  - 新增 `read_asset_bytes`，避免通过 base64 中转读取原 PDF。

### 2.2 Flutter

- 新依赖 `flutter_svg: 2.3.0`（MIT，精确固定；间接依赖 `vector_graphics*` 为 BSD-3-Clause）。`pubspec.lock` 已提交。
- `lib/book_vector.dart`：SVG 解析、`ui.Picture` 缓存、淘汰、失败标记。
- `lib/app_state.dart`：`renderBookPagesSvg` 在 `Isolate.run` 中调用核心，避免阻塞 UI。
- `lib/editor_page.dart`：当前页 ±1 异步预取；仅对 `kind == book`、`bookSource.vector == "svg"`、带 `sourceIndex` 的 PDF 源页请求；文档切换/快速翻页用 generation 防串页。
- `lib/canvas_view.dart`：`BookBackgroundPainter` 独立绘制纸张 + 矢量/PNG；主画布 painter 不再重复背景，笔迹重绘不会重放数千条字形路径。
- `lib/page_turn.dart`：翻页预览也接收矢量缓存，已加载页在过渡中保持清晰。
- 旧 PNG 路径、批注层、缩略图、导出、搜索、自动保存、撤销/重做均未改变接口。

## 3. 调查证据

### 3.1 MuPDF SVG 可用

原型直接链接 MuPDF 1.26.3：

- `fz_new_document_writer_with_buffer(ctx, buf, "svg", "text=path")` 可以写入内存，单页一个 writer。
- 样例 PDF 第 1 页：43,827 字节 SVG；CUPS test page：481,942 字节，含 17 个 `<use>`、裁剪路径；Flutter 渲染与 MuPDF PNG 观感一致。
- 文本页（UM1718 第 21 页）：686,346 字节、6,298 个 `<use>`；flutter_svg 直接报错：`SVG contains too many nested reference expansions`。

### 3.2 字形内联后可用

同一 UM1718 页面内联后：

- 2,931,816 字节，0 个 `<use>`，4,923 个 `<path>`；
- flutter_svg 在 debug/JIT 测试环境解析约 425 ms；
- 渲染结果与 MuPDF 输出的文字、分页线、页脚一致。

核心批量输出实测（50 页 UM1718 节选，965 KiB PDF）：

| 页面 | 耗时（含读取源、打开 PDF、SVG 输出与内联） | SVG 大小 |
|---|---|---|
| 0 | 0.109 s | 2.17 MB |
| 1 | 0.078 s | 1.23 MB |
| 20 | 0.148 s | 2.91 MB |
| 40 | 0.076 s | 1.24 MB |

说明：按需生成不需要把 SVG 写入文档；500 页书籍不会增加数 GB 存储。耗时在后台 isolate，不阻塞笔迹输入。

## 4. 测试与构建

- `scripts/test_all.sh`：
  - CTest 1/1，10 个 gtest 用例通过（新增 PDF 矢量导入/回退用例）。
  - `flutter analyze` clean。
  - Flutter/Dart 86 个测试全部通过（含新增 8 个矢量/加密/重绘用例）。
- 新增核心测试：
  - `PdfImportKeepsRasterFallbackAndRendersVectorPages`：导入 → `vector == "svg"` → 页 0/1 SVG 输出、无 `font_` `<use>`、PNG 资产仍在。
  - `RasterBookRejectsVectorPageRequests`：旧/回退文档拒绝矢量请求且 PNG 引用不变。
- 新增 Flutter 测试：
  - `test/book_vector_test.dart`：解析、坏 SVG 回退、矢量覆盖 PNG、缺失矢量回退、8 倍缩放边界清晰。
  - `test/pdf_vector_ui_test.dart`：真实 PDF 导入后编辑器中出现已解析矢量背景（后台 isolate）。
  - `test/core_test.dart`：PDF 导入矢量标记 + SVG op；EPUB 保持 `raster` 且拒绝矢量。
- Linux release：`flutter build linux --release` 成功；10 秒冒烟 `exit 124`（超时正常退出，无崩溃/异常堆栈）。
- Android arm64 release：`scripts/build_android_apk.sh` 成功，APK 32,195,525 bytes，SHA256 `af32f58e6737aafaa84f0bcce900aa6c58b60357378d3f5ca7da19ca48d3bfbe`。
- 未在真实 Android 设备上做手写笔帧率/内存验收。

## 5. 格式兼容

- 新增可选字段：`bookSource.vector`（`"svg"`/`"raster"`）与 `bookSource.encrypted`（bool）。
- 旧文档没有 `vector` 时按 `"raster"`，继续显示 PNG。
- 不新增逐页 SVG 资产；`book_page` PNG 与 `book_source` 原文件均保留。
- 加密 PDF 的密码仍不持久化；导入成功也只走 PNG。

## 6. 未完成/限制

- 画布是真矢量；`导出 PDF`/`导出 PNG` 仍通过 `renderPagePng` 生成 2x 位图。把 SVG 直接嵌入导出 PDF 需要新的 PDF 矢量写入路径，本轮未做。
- flutter_svg 对极端 SVG 特性（部分滤镜/混合模式）支持有限；当前依靠逐页解析失败或 `<use>` 上限回退 PNG，不做视觉差异自动检测。
- 大文本页 SVG 可达 2–3 MB，解析在 debug/JIT 约数百毫秒；release 构建与后台预取已缓解，但低端 Android 真机仍需测量。
- 没有对旧文档自动补生成矢量；用户重新导入 PDF 才获得 `vector` 标记。
- 未实现 PDF 文本选择/搜索 UI 的改动；原有 `sourceText` 全文搜索保持不变。

## 7. 实现提交

- `f479f35`（`feat(book): render PDF pages as on-demand vector backgrounds`）。
- `2ac1476`（`fix(book): repaint vector backgrounds when assets arrive`）：补上 PNG/SVG 晚到时的背景重绘、翻页过渡期间矢量 Picture 的延迟释放，以及 48 MiB 批量上限。

## 8. 复现命令

```bash
scripts/test_all.sh
scripts/build_linux_app.sh
timeout 10 apps/meowo/build/linux/x64/release/bundle/meowo
scripts/build_android_apk.sh
```
