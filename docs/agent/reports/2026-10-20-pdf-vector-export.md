# PDF 真矢量导出交付报告

- 状态：Completed（2026-10-20）
- 计划：[`pdf-vector-export.md`](../plans/pdf-vector-export.md)
- 关联：[`2026-10-20-pdf-vector-fidelity.md`](2026-10-20-pdf-vector-fidelity.md)、[`04-ux-interaction-spec.md`](../04-ux-interaction-spec.md)、[`09-decisions-and-open-questions.md`](../09-decisions-and-open-questions.md)、[`12-final-1.0-baseline.md`](../12-final-1.0-baseline.md)

## 1. 结果

喵书籍的 PDF 导出已从“整页 2× 位图”改为压平矢量 PDF：

- 原始 PDF 源页由 MuPDF PDF writer 重建，保留 MediaBox/CropBox/BleedBox/TrimBox/ArtBox/Rotate/UserUnit 与页面级 `/Group`；源内容中的文字通过自定义设备转为字形轮廓，因此输出**没有可选中文字层**，也不复制源注释。
- 笔迹与荧光笔写成 PDF 路径；荧光笔使用 `/BM /Multiply` 与 0.32×图层×元素透明度。
- 文本框/Markdown、图片、附件图标由 Flutter 渲染为透明 PNG（目标 300 DPI，单边 ≤8192 px、总像素 ≤3200 万），C++ 作为整页图像 XObject 叠加；附件内容不嵌入。
- 插入的 Meowo 笔记页使用书籍 `paper` 尺寸创建空白页，再写笔迹/叠加层；没有额外页边距。
- 逐页回退到已有 `book_page` PNG：加密 PDF、EPUB 固定页、缺少 `book_source` 的旧文档、源页索引损坏、字形无法轮廓化或单页写入失败都只影响该页，不中止整本。回退页按文档显示尺寸栅格化，旋转/裁切已烘焙进 PNG，视觉尺寸一致，但不再保留 PDF 级 CropBox/Rotate 元数据。
- 导出报告返回并展示 `exportedPages`、`vectorPages`、`fallbackPages`（页码 + 原因 + 详情）与 `warnings`。

## 2. 关键实现

### 2.1 C++ 核心

- 新增 `packages/meowo_core/native/src/mupdf_export.{h,cpp}` 与核心 op `export_book_pdf`。
- `build_book_pdf`：
  - 一次打开 `book_source` PDF，`pdf_create_document` 创建输出。
  - 每个源页用 `pdf_page_transform` 得到页面 CTM；用 `pdf_new_pdf_device`（topctm = 逆页 CTM）重放 `fz_run_page_contents`。
  - `FlattenDevice` 拦截 `fill_text`/`stroke_text`/`clip_text`，`fz_outline_glyph` 转路径；同时丢弃 structure/metatext，避免 `/ActualText` 重新引入文字层。
  - 复制页面盒/旋转/UserUnit 与 `/Group`；不复制源页面注释。
  - 追加笔迹/荧光笔 PDF 内容流；追加 Dart 叠加 PNG（`pdf_add_image`）。
  - 回退页按文档显示尺寸创建页面，先绘 PNG，再绘笔迹/叠加层。
  - 先写 `<target>.part-<random>`，成功后由 `core.cpp` 原子改名；失败/取消删除临时文件；目标已存在且未显式 `overwrite:true` 时拒绝。
- 进度/取消文件协议：每页写 `{phase, completed, total, pageNumber}`；每页开始检查取消文件。`phase` 包含 `exporting`、`saving`、`done`、`cancelled`。

### 2.2 Flutter

- 新增 `lib/pdf_export.dart`：文件名、范围解析/压缩、叠加层判定、估算、进度模型、回退原因文案。
- `lib/canvas_view.dart`：`MeowoCanvasPainter.overlayOnly` 跳过纸张/源页/笔迹/选择框；`renderBookOverlayPng` 以 300 DPI + 像素上限输出透明 PNG。
- `lib/app_state.dart`：`exportBookPdf` 在 `Isolate.run` 中调用核心，避免阻塞 UI。
- `lib/editor_page.dart`：
  - 喵书籍走新导出流程；书页/无极继续使用原 `pdf` 包栅格导出。
  - 导出前 `_flushSave`，确保核心读取到最新批注。
  - 整本（默认）/当前页/自定义范围；文件名 `<书名>-annotated-YYYYMMDD.pdf`；始终系统保存位置对话框；目标存在时二次确认覆盖。
  - 进度对话框：叠加层准备（root isolate 逐页）、核心写入、保存；取消按钮写取消文件。
  - >200 MB 或 >2 分钟软提示，可继续。
  - 完成对话框列出已导出页、PNG 回退页与原因、警告。

## 3. 测试与构建

### 3.1 C++

`ctest`：17 个 gtest 全部通过。新增/覆盖：

- `ExportBookPdfPreservesVectorGeometryAndDropsTextLayer`：400×300 MediaBox、CropBox [20 30 380 270]、Rotate 90；导出后页面盒/旋转一致；`stext` 提取不到 `GEOMETRY_SECRET`；资源无 `/Font`；内容流有路径；导出页与源页 72 dpi 渲染平均通道差 <3.0。
- `ExportBookPdfWritesInkAndHighlighterAsPaths`：内容流有颜色/路径/描边；ExtGState 有 `/BM /Multiply` 与约 0.32 alpha。
- `ExportBookPdfUsesPaperSizeForNotePagesAndHonorsRanges`：源页 + 笔记页 + 源页共 3 页；笔记页 MediaBox 等于书籍纸张；单页范围只输出第 2 源页；叠加 PNG 作为 XObject 嵌入并在页面中心渲染为红色。
- `ExportBookPdfFallsBackToPagePngAndReportsIt`：无 `bookSource` 的 `import_pdf_pages` 书籍输出 1 页 PNG，报告 `missing_book_source`，页面有 XObject。
- `ExportBookPdfFallsBackForEncryptedAndEpubSources`：`bookSource.encrypted=true` 返回 `encrypted_pdf_no_password`；EPUB 源返回 `epub_fixed_page`；两者都无 `vectorPages`。
- `ExportBookPdfRequiresExplicitOverwrite`：默认拒绝覆盖，显式 `overwrite:true` 成功；目标等于当前 `.meowo` 文件时即使 `overwrite:true` 也拒绝。
- `ExportBookPdfHonorsCancelAndWritesProgress`：取消文件返回 `cancelled` 且不产出文件；进度文件最终为 `done/1/1`。
- Dart `core_test.dart` 的加密 PDF 用例额外验证导出 `fallbackPages.reason == encrypted_pdf_no_password` 且无 `vectorPages`。

### 3.2 Flutter/Dart

`flutter analyze` clean；`flutter test` 95 个用例全部通过。新增：

- `test/pdf_export_test.dart`：
  - 文件名清理与日期；范围解析/排序/越界/空项；页码区间压缩。
  - 仅 text/image/attachment 触发栅格叠加；隐藏层不算。
  - 200 MB/2 分钟估算软提示。
  - 进度 JSON 防御性解析。
  - 叠加 PNG 在 144 dpi 下排除纸张与笔迹、包含文字；透明角落 alpha=0。
  - 真实核心集成：导入 PDF → 添加文本 → Dart 渲染 `overlay-0.png` → `export_book_pdf` → 输出包含 `/Subtype/Image` 且无回退。

### 3.3 构建

- Linux release：`scripts/build_linux_app.sh` 成功；10 秒冒烟 `exit 124`（超时正常），无崩溃/异常堆栈。
- Android arm64 release：`scripts/build_android_apk.sh` 成功；APK 32,342,981 bytes；SHA256 `c9bddf6c2775ee59c2d3900866498122403f8c5d492dc852d0c0c93e377d85b6`。

## 4. 限制与未完成

- 同一图层内“笔迹 ↔ 文本/图片”的交错 z 序不保证：该页栅格叠加层统一位于矢量笔迹之上。
- 取消按页生效；单页源页重放、单页叠加层渲染与最终 `pdf_save_document` 不可中断。UI 在取消后会等待当前页/保存完成。
- 300 DPI 叠加层必须由 Flutter root isolate 渲染（`dart:ui` 限制），因此叠加层准备阶段在 UI isolate 逐页执行；核心 PDF 组装在 worker isolate。进度与页间取消可用，但单页 PNG 编码仍可能造成短时卡顿。
- Type3 字体或无法由 FreeType 轮廓化的字形会使该页回退 PNG；不做 OCR，也不保留源文字。
- 源页 `/Group` 已复制，但极端 PDF 特性（滤镜、特殊混合/图案）仍可能因 MuPDF 重放产生细微差异；未做视觉差异自动检测。
- 未在真实 Android 设备验证大 PDF 内存、300 DPI 叠加耗时、SAF 保存路径与外部 PDF 查看器兼容性。需手工验收：
  - 500 页混合尺寸 PDF 整本导出；
  - 加密 PDF/EPUB/旧文档回退报告；
  - Android 保存到 SAF、覆盖确认；
  - 用系统 PDF 查看器检查旋转/crop、荧光笔 multiply、文字/图片叠加对齐。

## 5. 实现提交

- `dd75251`（`feat(pdf): export books with true vector source pages`）。
- `265709b`（`fix(pdf): refuse to overwrite the active document`）：目标路径等于当前 `.meowo` 文件时拒绝导出，避免覆盖文档。

## 6. 复现命令

```bash
scripts/test_all.sh
scripts/build_linux_app.sh
timeout 10 apps/meowo/build/linux/x64/release/bundle/meowo
scripts/build_android_apk.sh
```

手工导出路径：打开喵书籍 → 右上角导出菜单 → “导出 PDF” → 选择范围 → 选择保存位置 → 查看进度/报告。

## 7. 2026-10-20 复检修复

本轮修复 owner 反馈的 13 项问题，主要变更：

- 导出方向：回退 PNG 与笔记页/EPUB 使用统一 Y 翻转；修复 PDF 源页叠加层、回退页、笔记页的上下颠倒。
- 导出正确性：笔记页 JSON `null` 字段安全读取；导出报告使用实际文档页码。
- 普通书页/无极画布：PDF 笔迹改为矢量绘制；文字、图片仍走栅格叠加层。
- 导入：取消 500 页硬限制，超过 500 页先提示；新增 `probe_book` 与导入进度文件；批量写资产、96 DPI 渲染、缩略图串行化。
- 背景与 UI：导入源页白底；工具栏图标更新；切文档时延迟释放 native 图像。

验证（本机临时 MuPDF 1.27 运行库；仓库内 Android 1.26.3 静态库需在完整构建环境复验）：

- CTest：22/22 通过（新增方向、笔记页、回退位图、probe 测试）。
- Flutter/Dart：95/95 通过；`flutter analyze` 无问题。
- Linux release 已重新构建；6 秒冒烟启动正常（超时退出，无崩溃）。
- Android arm64 APK 未重新生成：当前 `.tools/mupdf` 的 1.26.3 源文件/arm64 静态库不完整；本次只能用临时 MuPDF 1.27 Linux 运行库验证。需恢复完整 MuPDF 1.26.3 arm64 构建后再产出 APK。
