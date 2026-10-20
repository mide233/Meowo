# PDF 真矢量页背景计划

- 状态：Completed（2026-10-20）
- 目标：PDF 书籍页不再固定为 120 dpi PNG 快照；保留原 PDF，按页从 MuPDF 生成 SVG，在 Flutter 画布中以矢量重绘，任意缩放保持清晰。
- 关联：[`mupdf-integration.md`](mupdf-integration.md)、[`02-technical-architecture.md`](../02-technical-architecture.md)、[`03-document-format.md`](../03-document-format.md)。

## 1. 背景

当前 `mupdf_import.cpp` 在导入时把每页渲染为 `page-%04d.png`（120 dpi），`core.cpp` 保存为 `book_page` 资产，`MeowoCanvasPainter` 仅绘制 `ui.Image`。放大到 200% 以上后文字和线条出现明显插值模糊。原 PDF 已作为 `book_source` 资产保存，具备按需重新渲染的数据基础。

## 2. 调查与证据

### 2.1 MuPDF SVG 输出

MuPDF 1.26.3 的 `svg` document writer 可用：

```cpp
fz_buffer* buffer = fz_new_buffer(ctx, 64 * 1024);
fz_document_writer* writer =
    fz_new_document_writer_with_buffer(ctx, buffer, "svg", "text=path");
fz_device* device = fz_begin_page(ctx, writer, fz_bound_page(ctx, page));
fz_run_page(ctx, page, device, fz_identity, nullptr);
fz_end_page(ctx, writer);
fz_close_document_writer(ctx, writer);
```

- 单页写入内存 buffer 可行；每个 writer 只能写一页。
- 默认 `text=path` 把字形输出为精确路径，避免设备字体缺失导致排版变化。
- 实测样例 PDF 第 1 页：43,827 字节 SVG；CUPS test page：481,942 字节，包含 17 个 `<use>` 与裁剪路径，Flutter 渲染与 MuPDF PNG 逐像素观感一致。

### 2.2 Flutter SVG 渲染器的硬限制

`flutter_svg 2.3.0` → `vector_graphics_compiler 1.3.2` 在 `resolver.dart` 中限制每个文档最多 1000 次 `<use>` 展开（防 DoS）。MuPDF 对每个字形输出一个 `<use xlink:href="#font_x_y">`：

- UM1718 第 21 页：6,298 个 `<use>`，flutter_svg 直接报错 `SVG contains too many nested reference expansions`。
- 因此不能把 MuPDF SVG 原样交给 flutter_svg。

### 2.3 字形内联

在 C++ 侧把 `font_*` 的 `<use>` 替换为带原 `transform` 的 `<path d="...">`：

- UM1718 第 21 页：2,931,816 字节，0 个 `<use>`；flutter_svg 解析约 425 ms（debug/JIT 测试环境），绘制结果与 MuPDF 输出一致。
- 若仍有超过 800 个非字形 `<use>`（如极端图片平铺/图案），判定该页不支持矢量并保留 PNG，避免反复触发解析失败。
- 单页 SVG 上限 24 MiB；超出则失败并回退 PNG。

## 3. 方案

1. **按需渲染，不保存逐页 SVG**：`book_source` 已含原 PDF；新增核心 op `render_book_pages_svg`，一次最多 8 页，在 worker isolate 中读取源 PDF、打开 MuPDF、输出并内联字形。避免 500 页书籍把数 GB SVG 写入文档。
2. **文档能力标记**：导入时对非加密 PDF 探测第 1 页；成功则 `bookSource.vector = "svg"`，否则 `"raster"`。加密 PDF 记录 `encrypted: true`，永不请求矢量（密码不持久化）。EPUB 保持 `"raster"`。
3. **Flutter 缓存与绘制**：`BookVectorCache` 解析并缓存当前页 ±1 的 `ui.Picture`；`BookBackgroundPainter` 在独立 `RepaintBoundary` 中绘制矢量页，避免笔迹每帧重放数千条路径。无矢量时继续绘制原 PNG。
4. **回退**：旧文档无标记、加密 PDF、EPUB、SVG 解析失败、单页失败或超限时全部保留 PNG；不改变既有文档可读性。
5. **保持只读背景**：批注、图层、页面选择器、导出、搜索、自动保存、撤销/重做、翻页路径不变。

## 4. 数据格式变更

`bookSource` 新增可选字段：

```json
{
  "vector": "svg" | "raster",
  "encrypted": false
}
```

- 旧文档没有 `vector` 字段时按 `"raster"` 处理。
- 不新增资产，不改变 `book_page` / `book_source` 的 id 或页坐标。
- `book_page` PNG 始终保留，作为回退和缩略图来源。

## 5. 验收

- C++ 测试覆盖 PDF 导入、`vector` 标记、按页 SVG 输出、字形内联、PNG 回退和旧文档拒绝矢量请求。
- Flutter 测试覆盖 SVG 解析、矢量覆盖 PNG、缺失矢量回退、8 倍缩放下背景边界仍清晰，以及真实 PDF 导入后 UI 中出现已解析的矢量背景。
- `scripts/test_all.sh`、Linux release 冒烟、Android arm64 APK 构建通过（环境允许时）。
- 更新 02/03/04/12 文档与交付报告。

## 6. 风险与后续

- 复杂 PDF 的 SVG 可能较大，解析/绘制成本高于位图；已限制单页 24 MiB、批量 8 页，并在后台 isolate 解析。
- 极端图案/平铺页可能超过 flutter_svg 的 `<use>` 限制；已按页回退 PNG。
- SVG 导出到 PDF 仍未实现（导出仍为 2x 位图），本轮只保证画布显示为真矢量背景。
- 尚未在真实 Android 手写笔设备上测帧率与内存；需真机验收。
