# 编辑器工具分离、页面缩略图与缩放指示

- 状态：Completed
- 阶段：Alpha 后续（1.0 前体验修正）
- 负责人/Agent：subagent（OpenCode / DeepSeek V4.1 Flash）
- 创建日期：2026-10-20
- 最后更新：2026-10-20
- 关联需求：`04-ux-interaction-spec.md` §5.3、§7、§8.4、§12.1、§12.2
- 关联决策：现有 `select` 组合工具拆分；无极画布不再支持 `page_body`
- 关联风险：选择工具拆分影响翻页/撤销/图层守卫；缩略图渲染阻塞 UI；缩略图缓存过期；窄屏底栏溢出

## 1. 目标

1. 工具轨提供两个独立工具：
   - **指针**：点击选择单个对象；可拖动/缩放已选对象；不直接打开文本或图片编辑器。
   - **框选**：拖拽空白执行自由套索/矩形选择；同样显示控制点和选择操作栏；不直接打开编辑器。
2. 无极画布（`kind == 'infinite'`）不再创建或渲染正文（`page_body`），只支持文本框；已有正文数据保持不变，书页/书籍继续支持正文。
3. 文本框和图片只能通过“选择操作栏”的编辑按钮进入现有编辑器；仅单选文本/图片时显示该按钮，多选不显示。指针点击和套索/矩形选择都不得直接弹出编辑器。
4. 页码选择器使用真实的页面缩略图：
   - 复用 `renderPagePng` / `MeowoCanvasPainter`；
   - 异步、按页 id 缓存、独立占位，不阻塞选择器；
   - 保留当前页高亮、页码/页类型标签和点击跳转；
   - 仅书页/书籍，无极画布不显示页码选择器。
5. 底栏始终显示当前缩放百分比（100%、150%、10% 等）：
   - 滚轮/双指缩放实时更新；
   - 适应页面、回到原点、适应内容后同步更新；
   - 无极与书页/书籍都显示；窄屏不溢出。

## 2. 非目标

- 不实现 PDF 矢量保真导出（独立任务）。
- 不新增多选编辑、旋转把手、键盘微移等未要求的选择能力。
- 不删除或迁移已有无极 `page_body` 数据；不改变 `.meowo` schema。
- 不改变相册翻页规则（手工具 + fit、相邻页、阻尼边缘）、撤销/重做页码保持、隐藏/锁定图层守卫、中键平移、滚轮/双指缩放回中。
- 不改变导入、附件、图层、PDF/PNG 导出管线的既有语义（除无极正文不再参与渲染/内容包围盒）。

## 3. 背景与现状

- `editor_page.dart` 只有一个 `select` 工具：CanvasView 的点击回调会直接打开文本/图片编辑器，拖拽空白执行套索/矩形选择。
- 无极画布通过 `page_body` 渲染固定原点正文，且“正文”工具仍出现；`hasInfiniteContent` / `infiniteContentBounds` 也会把正文算入内容。
- `_PagePickerSheet` 使用 `_PagePickerPaperPainter` 绘制纸张背景，卡片明确标注“非实时缩略图”。
- `CanvasViewState` 的 `_zoom` 只在内部使用；编辑器底栏没有缩放状态。
- `MeowoCanvasPainter` 已能绘制页面/正文/图层/图片，`renderPagePng` 已用于 PDF 导出。

## 4. 方案

### 4.1 工具拆分与选择

- 新增工具 id `pointer`（指针）与 `select`（框选）；工具轨分别显示，互不切换。
- `CanvasView`：
  - `pointer` 仅处理点击选中（`onElementTap`）与已有选区的移动/四角缩放；
  - `select` 处理空白处套索/矩形选择与已有选区的移动/缩放；
  - 增加 `onSelectionCleared`，指针点击空白时清空选择（点在选区范围内保留）；
  - 选择范围继续跳过隐藏/锁定图层。
- `EditorPage`：
  - 指针点击只写入单选 `_selectedIds`，不切工具、不打开编辑器；
  - 套索/矩形只更新选择集合；
  - 选择操作栏新增“编辑”按钮，仅当恰好单选 `text`/`image` 时出现，调用现有 Markdown/图片编辑器；
  - 多选不显示单对象编辑按钮；附件等既有入口保持可用。

### 4.2 无极正文停用

- 工具轨仅对非无极文档显示“正文”工具；`_editBody` 对无极直接返回提示。
- `MeowoCanvasPainter` 在 `kind == 'infinite'` 时跳过 `page_body` 绘制。
- `hasInfiniteContent` 与 `infiniteContentBounds` 忽略 `page_body`，避免适应内容/导出把不可见正文算入。
- 不修改/删除页面中的 `body` 字段；书页、书籍路径不变。

### 4.3 页面缩略图

- 新增 `page_thumbnail.dart`：
  - `PageThumbnailCache`：按 page id 缓存 `Uint8List`，合并并发请求，`clear()` 使旧请求结果失效；
  - `PageThumbnail`：异步加载、占位/失败状态、`Image.memory` 展示。
- `EditorPage`：
  - 维护缩略图缓存；内容变更/撤销/重做/切换文档时清空；
  - 加载时按需读取该页图片（`_imagesForPage`），调用 `renderPagePng`，最长边约 300 px；
  - 页码选择器把异步 loader 传入卡片。
- `_PagePickerSheet` 保留网格、当前页高亮、页码/源页/笔记页标签和点击跳转；卡片独立加载缩略图。

### 4.4 缩放百分比

- `CanvasView` 接受可选 `ValueNotifier<double>? zoomNotifier`，在缩放/重置/fit 后（post-frame）发布 `_zoom`。
- `EditorPage` 创建并释放 notifier；底栏用 `ValueListenableBuilder` 显示 `(_zoom * 100).round()%`。
- 书页/书籍 `_zoom` 是相对 fit 的 1.0–8.0；无极是绝对 0.1–8.0，均符合百分比语义。
- 底栏窄屏隐藏次要尺寸文案，保留页码、导航和缩放。

## 5. 任务拆分

| # | 任务 | 产出 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 拆分指针/框选工具 | toolbar + CanvasView + 选择栏 | 两个 tooltip 独立；指针点击单选；框选拖拽选择；均显示控制点/操作栏 | Done |
| 2 | 单对象编辑入口 | 选择栏编辑按钮 | 单选文本/图片显示；多选不显示；点击/套索不弹编辑器 | Done |
| 3 | 无极停用正文 | 工具隐藏、绘制跳过、内容包围盒忽略 | 无极无正文工具；已有 body 数据保留且不渲染 | Done |
| 4 | 真实页面缩略图 | `page_thumbnail.dart` + picker | 异步占位、缓存、当前页高亮、点击跳转、无阻塞 | Done |
| 5 | 缩放百分比 | notifier + 底栏 | 滚轮/双指/适应页面/回到原点/适应内容实时更新；窄屏不溢出 | Done |
| 6 | 测试与构建 | 单元/Widget 测试、analyze、test_all、Linux/Android 构建 | 全部通过并记录 | Done |
| 7 | 文档与提交 | UX 规范、计划、报告、操作日志、commit | 文档同步，提交在 `dev-agent` | Done |

## 6. 测试与验收

- `flutter analyze`：无问题。
- `./scripts/test_all.sh`：CTest + Flutter/Dart 全部通过。
- 新增/更新测试覆盖：
  - 指针点击不触发编辑器回调，框选/矩形不触发点击单选；
  - 单选文本/图片显示编辑按钮，多选不显示；
  - 无极隐藏正文工具、正文数据保留、body-only 页面不算内容；
  - 缩略图缓存去重/清理，缩略图占位与异步完成；
  - 页码选择器仍可点击跳转；
  - 底栏缩放文本随滚轮/fit 更新，书页与无极都有。
- Linux release 构建；Android arm64 release APK 构建。

## 7. 风险与依赖

| 风险 | 触发 | 缓解 |
|---|---|---|
| 选择工具拆分回归翻页/移动 | 手工具/指针分支混淆 | 只新增 `pointer` 分支；`hand` 逻辑不变；运行 page_turn/selection 回归 |
| 缩略图渲染卡顿 | 一次打开很多页/大图 | 仅可见卡片懒加载；最长边 300 px；按页缓存；异步 `toImage` |
| 缓存显示旧内容 | 编辑后重开选择器 | 所有内容变更、撤销/重做、切换文档清空缓存 |
| 窄屏底栏溢出 | 430 dp 宽度 | 保留 compact 逻辑，缩放固定窄宽度，隐藏次要尺寸文本；phone_layout 测试 |
| 无极 body 数据丢失 | 误清理/重建页面 | 只改渲染和入口，不写 `body`；保留数据测试 |

## 8. 进度记录

| 日期 | 状态 | 说明 |
|---|---|---|
| 2026-10-20 | In Progress | 计划创建，开始实现。 |
| 2026-10-20 | Completed | 五项需求实现并通过 `scripts/test_all.sh`（CTest 1/1、Flutter 78/78、analyze clean）、Linux release 与 Android arm64 release APK 构建；报告见 `reports/2026-10-20-tools-thumbnails-zoom.md`。 |

## 9. 结果

- 工具拆分为“指针/框选”，单对象编辑只从选择操作栏进入。
- 无极停用正文入口与渲染，历史 body 保留；书页/书籍不变。
- 页码选择器改为异步真实缩略图，按页 id 缓存并显示占位。
- 底栏实时显示缩放百分比，覆盖滚轮、双指、适应页面、回到原点、适应内容与窄屏。
- 证据与遗留见 `docs/agent/reports/2026-10-20-tools-thumbnails-zoom.md`。
