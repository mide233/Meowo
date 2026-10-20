# PDF 真矢量导出计划

- 状态：Completed（2026-10-20）
- 目标：喵书籍导出的 PDF 不再把整页渲染为 2× 位图。源 PDF 页、笔迹与荧光笔保持矢量；文本框/Markdown、图片、附件图标以约 300 DPI 透明叠加层栅格化；逐页回退 PNG 并在报告中列出。
- 关联：[`pdf-vector-fidelity.md`](pdf-vector-fidelity.md)、[`02-technical-architecture.md`](../02-technical-architecture.md)、[`03-document-format.md`](../03-document-format.md)、[`04-ux-interaction-spec.md`](../04-ux-interaction-spec.md)、[`12-final-1.0-baseline.md`](../12-final-1.0-baseline.md)。

## 1. 背景与约束

画布已使用 MuPDF 按需 SVG 作为显示桥（`render_book_pages_svg`），但 SVG 不适合作为 PDF 导出中间格式：它丢失 PDF 页面盒/旋转元数据，也不能直接复用 MuPDF PDF writer。导出必须：

- 压平、静态，不生成可编辑 PDF 注释，不保留可选中源文字层；
- 源页、笔迹、荧光笔矢量；文本/图片/附件图标可栅格；
- 保留源页 MediaBox/CropBox/Rotate/UserUnit；笔记页使用书籍纸张尺寸；无额外边距；
- 默认整本书，可选当前页/自定义范围；
- 逐页回退，不因单页失败中止整本；
- 后台执行、进度、页间取消、软容量/时间提示；
- 文件名 `<书名>-annotated-YYYYMMDD.pdf`，始终弹保存位置，显式覆盖确认。

## 2. 设计

### 2.1 分层

```text
Dart/Flutter                         C++/MuPDF
────────────                         ─────────
range/filename/save/overwrite  ──▶  export_book_pdf
render overlay PNG (300 DPI)   ──▶  - 打开 book_source PDF
progress/cancel files          ◀──▶  - 源页：文本转轮廓 + 绘制路径/图像
report dialog                  ◀──  - 写入笔迹/荧光笔 PDF 路径
                                     - 叠加透明 PNG
                                     - 逐页 PNG 回退
                                     - pdf_save_document
```

### 2.2 C++：源页矢量重建

- `pdf_create_document` 创建目标 PDF。
- 对每个源页：
  - `fz_load_page` + `pdf_page_transform` 取得 cropbox 与显示 CTM。
  - 用 `pdf_new_pdf_device`（topctm = 逆页 CTM）把 `fz_run_page_contents` 重放进内容流。
  - 通过自定义 `FlattenDevice` 拦截 `fill_text` / `stroke_text` / `clip_text`：用 `fz_outline_glyph` 将每个字形转为路径，再转发给 PDF device。这样文字仍是矢量，但不产生字体/文本对象，也不保留 `/ActualText`。
  - 复制源页 MediaBox/CropBox/BleedBox/TrimBox/ArtBox/Rotate/UserUnit 到新页；内容/资源使用重建结果，不复制源注释。
  - 追加笔迹/荧光笔：在页面显示坐标写入 PDF 路径，外层 `cm = 逆页CTM × 页面缩放`；荧光笔使用 `/BM /Multiply` 与 `ca=0.32×layer×element`。
  - 追加 Dart 生成的透明 PNG：作为图像 XObject，按整页显示矩形放置。
- 笔记页：按书籍 `paper.width/height` 创建空白页，写笔迹 + 叠加 PNG。
- 回退页：按文档页显示尺寸创建页面，先绘已有 `book_page` PNG，再绘笔迹 + 叠加 PNG。旋转/裁切已烘焙进 PNG，视觉尺寸一致，但不保留 PDF 级 CropBox/Rotate 元数据。
- 单页失败：丢弃未插入的页，改用回退路径；报告原因。
- 输出先写临时文件，成功后由 `core.cpp` 原子改名到目标；失败/取消删除临时文件。

### 2.3 取消与进度

C ABI 同步，采用文件协议：

- 请求可带 `progressPath`、`cancelPath`。
- C++ 每页开始/结束原子写 `{phase, completed, total, pageNumber}`。
- 每页开始检查取消文件；取消后返回 `{cancelled:true}` 并删除临时输出。
- Dart 在 worker isolate 调用核心，主 isolate 每 200 ms 轮询进度文件；叠加层准备阶段在 UI isolate 逐页渲染并检查取消标志。
- 诚实限制：单页内部与最终 `pdf_save_document` 不可中断。

### 2.4 Flutter：叠加层与交互

- `renderBookOverlayPng`：透明背景，只画可见图层的 text/image/attachment（以及 body 文本），不画纸张、源页、笔迹、选择框。目标 300 DPI；单边 ≤8192 px、总像素 ≤3200 万。
- 按页加载所需图片资产，渲染后立即释放 `ui.Image`，避免 500 页整本驻留内存。
- 导出范围：全部（默认）/ 当前页 / 自定义 `1-3, 5`；解析后排序去重并校验。
- 文件名：`annotatedPdfFileName`；保存位置始终由系统对话框选择；已存在时额外弹覆盖确认。
- 估算：源 PDF 大小按选中源页比例 + 1.5 MB/页叠加层；>200 MB 或 >2 分钟仅软提示。
- 结果对话框列出已导出页码（压缩为区间）、PNG 回退页与原因、警告。

## 3. 请求/响应（不进入持久化格式）

```json
{
  "op": "export_book_pdf",
  "documentId": "doc_...",
  "targetPath": "/path/out.pdf",
  "pageIndexes": [0, 1, 2],
  "overlayDir": "/tmp/meowo-pdf-export-.../",
  "progressPath": "/tmp/.../progress.json",
  "cancelPath": "/tmp/.../cancel.flag",
  "overwrite": true
}
```

```json
{
  "path": "/path/out.pdf",
  "exportedPages": [1, 2, 3],
  "vectorPages": [1, 3],
  "fallbackPages": [
    {"pageNumber": 2, "reason": "missing_book_source", "detail": "..."}
  ],
  "warnings": [],
  "bytes": 123456,
  "cancelled": false
}
```

`overlayDir` 中按文档页索引命名 `overlay-<documentPageIndex>.png`；不存在则跳过。

## 4. 回退原因

| reason | 场景 |
|---|---|
| `missing_book_source` | 旧文档/资产缺失，没有可用原始 PDF |
| `epub_fixed_page` | EPUB 固定页（导入快照为 PNG） |
| `encrypted_pdf_no_password` | 加密 PDF，密码未持久化 |
| `source_not_pdf` | bookSource 不是 PDF |
| `source_page_out_of_range` / `missing_source_index` | 页面映射损坏 |
| `vector_render_failed` | 源页重放/字形轮廓化失败 |
| `missing_page_bitmap` | 连 PNG 回退也不可用（仍输出空白页并警告） |

## 5. 验收

- C++：源页几何/旋转/crop 保留；输出无可选中文字；视觉与源页逐像素近似；笔迹/荧光笔路径与 multiply ExtGState；页码范围；笔记页纸张尺寸；PNG 回退报告；取消/进度。
- Dart：文件名、范围解析、报告压缩、叠加层仅含栅格元素、估算软提示、进度解析、FFI 导出集成、加密回退。
- `scripts/test_all.sh`、Linux release、Android arm64 构建。
- 更新 `04`、`09`、`12` 与交付报告。

## 6. 已知限制

- 同一图层内“笔迹 → 文本/图片”的原始交错 z 序不保证；栅格叠加层统一位于该页矢量笔迹之上。
- 源页文字转轮廓后文件可能变大；>200 MB 只提示不阻止。
- Type3/无法轮廓化的字形使该页回退 PNG。
- 取消仅按页生效；最终保存不可中断。
- 需真机验证大 PDF 内存、300 DPI 叠加层耗时与 Android SAF 保存路径。
