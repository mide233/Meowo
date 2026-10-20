# 报告：编辑器工具分离、页面缩略图与缩放指示

- 状态：Completed
- 日期：2026-10-20
- Agent/负责人：subagent（OpenCode / DeepSeek V4.1 Flash）
- 关联计划：`docs/agent/plans/editor-tools-thumbnails-zoom.md`
- 关联需求：`04-ux-interaction-spec.md` §5.1、§5.3、§7.1、§8.2、§8.4、§12.1、§12.2
- 关联风险：选择工具拆分回归、缩略图阻塞/缓存过期、窄屏底栏溢出

## 1. 摘要

本任务完成五项 owner 修正：指针与框选成为两个独立工具；无极画布停用正文但保留历史数据；文本框/图片只能从选择操作栏的编辑按钮进入既有编辑器；页码选择器改为异步真实缩略图；底栏实时显示缩放百分比。相册翻页、撤销/重做页码保持、隐藏/锁定图层守卫、中键平移、滚轮/双指缩放与回中规则保持不变。

## 2. 范围

- 修改：
  - `apps/meowo/lib/canvas_view.dart`
  - `apps/meowo/lib/editor_page.dart`
  - `apps/meowo/lib/ink_ops.dart`
  - 新增 `apps/meowo/lib/page_thumbnail.dart`
- 测试：
  - 更新 `selection_test.dart`、`infinite_canvas_test.dart`、`page_navigation_test.dart`
  - 新增 `editor_selection_test.dart`、`page_thumbnail_test.dart`、`zoom_indicator_test.dart`
- 文档：`04-ux-interaction-spec.md`、本计划、本报告、忽略的 `.meowo-agent/operation-log.md`。
- 未改：C++ 核心、FFI/ABI、`.meowo` schema、导入管线、PDF 矢量导出、相册翻页算法。

## 3. 完成内容

### 3.1 指针与框选工具

- 工具轨新增独立 `pointer`（指针）与 `select`（框选）：
  - 指针点击选择单个最上层可见、未锁定元素；点击空白取消选择（控制点除外）；可拖动选区内部/四角控制点移动缩放。
  - 框选在空白拖拽自由套索或矩形选择；同样支持移动/缩放；点击不再直接选中对象。
- 选择范围仍跳过隐藏/锁定图层；两种工具共享选择包围盒与控制点，并显示选择操作栏。
- 切换到手/笔/荧光笔/橡皮/文本等工具时清空选择；指针/框选之间保留选择。

### 3.2 单对象编辑入口

- 选择操作栏新增“编辑”按钮，仅当恰好单选 `text` 或 `image` 时显示。
- 文本按钮打开既有 Markdown 编辑对话框；图片按钮打开既有图片编辑器；多选不显示该按钮。
- 指针点击、套索/矩形选择都不再直接弹出文本或图片编辑器。
- 单选附件时保留“打开附件”操作入口，避免失去原有附件查看能力。

### 3.3 无极正文停用

- 无极文档工具轨隐藏“正文”，`_editBody` 对无极直接返回提示。
- `MeowoCanvasPainter` 在 `kind == 'infinite'` 时跳过 `page_body` 绘制。
- `hasInfiniteContent` / `infiniteContentBounds` 忽略 `page_body`，所以旧正文不会再影响“适应内容”/导出包围盒。
- 页面中的 `body` 字段不删除、不改写；书页/书籍继续显示正文工具并渲染正文。

### 3.4 真实页面缩略图

- 新增 `PageThumbnailCache`：按 page id 缓存 PNG、合并并发请求、`clear()` 用 generation 使旧渲染结果失效。
- 新增 `PageThumbnail`：独立异步加载、纸张占位、失败图标、`Image.memory` 展示。
- 页码选择器每张卡片按需调用 `renderPagePng`，最长边约 300 px；可见卡片各自加载，不等待全部页面。
- 保留当前页高亮、“源 X/源页/笔记页”标签、页码与点击跳转；选择器关闭后缓存保留，编辑/撤销/重做/切换文档时清空。
- 无极画布仍没有页码选择器。

### 3.5 缩放百分比

- `CanvasView` 新增可选 `zoomNotifier`，在缩放/重置/fit 后 post-frame 发布相对缩放（书页/书籍）或绝对缩放（无极）。
- 底栏 `_ZoomIndicator` 用 `ValueListenableBuilder` 显示 `round(zoom * 100)%`。
- 覆盖滚轮、双指、适应页面、回到原点、适应内容；书页/书籍以 fit 为 100%，无极以世界 100% 为基准。
- 窄屏（<760 dp）隐藏顶栏保存文字/撤销重做按钮（菜单仍可访问）与底栏次要尺寸文案；底栏保留页码、导航和缩放。

## 4. 未完成/偏差

- 缩略图在 UI isolate 上按需读取/解码该页图片；超大图片或多页同时滚动时可能有短暂 CPU 峰值，但不会阻塞选择器打开或等待全部页面。
- 未在 Android 真机/桌面触控板验证缩略图滚动流畅度与双指缩放手感。
- 未实现 PDF 矢量保真（按 owner 说明为独立任务）。
- 无极旧正文数据保留但不可见；未提供迁移/清理入口（按需求不删除）。

## 5. 验证与证据

### 自动化

```bash
./scripts/test_all.sh
```

结果：

- CTest `1/1` 通过（8 个 gtest case）；
- `flutter analyze`：No issues found；
- Flutter/Dart：`78/78` 通过（原 60 + 新增/更新 18）。

新增/更新覆盖：

- 指针点击单选、框选点击不直接选对象、指针空白拖动不套索、指针空白点击清空、指针拖动选区；
- 编辑器单选文本显示编辑按钮且不直接弹窗、点击编辑打开既有对话框；矩形多选显示“已选 2”且无编辑按钮；单选图片显示图片编辑按钮；
- 无极隐藏正文工具、旧 body 保留且不渲染；无极 body-only 页面不计内容/包围盒；书页保留正文工具；
- 缩略图缓存去重、清理失效、占位→图片切换、真实页面低分辨率渲染；
- 页码选择器含真实缩略图组件并可跳转；
- 书页滚轮/双指/适应页面缩放文字；无极滚轮/适应内容/回到原点；360 dp 窄屏无溢出。

### 构建与冒烟

```bash
./scripts/build_linux_app.sh
```

结果：`apps/meowo/build/linux/x64/release/bundle/meowo` 构建成功。

```bash
timeout 8s apps/meowo/build/linux/x64/release/bundle/meowo
```

结果：运行至 8 秒超时（exit 124），无崩溃；仅 Impeller 后端与光标主题环境警告。

```bash
./scripts/build_android_apk.sh
```

结果：Android arm64 release APK 构建成功，`apps/meowo/build/app/outputs/flutter-apk/app-release.apk`，`31,703,809 bytes`（31.7 MB），SHA256 `aa954f0e00e974480663c26c52a7feed20d564f5486b94da872b96f5d46f9f92`。未安装真机。

## 6. 文档更新

- `04-ux-interaction-spec.md`：工具轨/快捷键拆分、§7.1 指针与框选、§8.1/8.2 编辑入口、§8.4 无极停用正文、§12.1 真实缩略图与底栏缩放。
- 新增本计划与报告；`.meowo-agent/operation-log.md` 追加记录（已忽略）。
- 未更新 `01-functional-requirements.md`：本次是既有交互细化，不新增产品级能力范围。

## 7. 风险与遗留

- 缩略图缓存按 page id，任何 `_mutate` 会清空全部缩略图；编辑后首次重开选择器需要重新生成，换取不显示旧内容的正确性。
- 缩略图渲染复用 `_imagesForPage`，会为每张缩略图重新加载/解码图片；后续可改为共享图片缓存或 isolate，但当前按需加载已避免一次性阻塞。
- 指针/框选共享同一套控制点；未实现 Shift 多选、边中点单轴缩放或旋转把手（原规范中的后续能力）。
- 附件不再通过单击画布直接打开，改为选择后“打开附件”按钮；这是选择语义统一后的有意行为变化。
- 未验证真实设备上的长按/双击习惯；需求明确禁止点击直接编辑，因此未保留双击编辑快捷路径。

## 8. 结论与下一步

- 五项 owner 需求均已实现并有自动化覆盖；既有翻页、撤销/重做页码、图层守卫、中键平移、缩放回中行为未回归。
- 建议后续在 Android 平板/桌面触控板做一次缩略图滚动与捏合缩放手感验收；若需要，可将图片资产解码移入后台 isolate。
