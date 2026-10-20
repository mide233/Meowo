# 报告：无极画布真正无界化（Infinite Canvas）

- 状态：Completed（自动化与构建通过；真机手势未验证）
- 日期：2026-10-20
- Agent/负责人：subagent（OpenCode / DeepSeek V4.1 Flash）
- 关联计划：`docs/agent/plans/infinite-canvas.md`
- 关联需求：`12-final-1.0-baseline.md` §3.1/§3.2/§9；`04-ux-interaction-spec.md` §2.5/§8.2/§8.4/§12.1/§12.2
- 关联决策：Q-038
- 关联风险：100,000 pt 坐标精度/性能、导出分辨率上限、`page_body` 动态测高、真机手势

## 1. 摘要

无极文档已从“固定 1600×1200 页面 + 适应页面”改为真正无界的视口画布：无极分支使用视口大小的 `CustomPaint`，世界坐标通过 `_offset`/`_zoom` 映射，可平移到旧页面矩形之外，平移仅在约 ±100,000 pt 逻辑边界处夹取。连续纸张背景与横线/点阵/方格在视口空间绘制并裁剪，无固定页框；书页/书籍路径、纸张背景、页面栏、翻页和页码选择器保持原行为。新增“回到原点/适应内容”，无极文本框/图片/附件落在可见视口中心；PNG/PDF 导出按内容包围盒 + 32 pt 留白裁切。自动化与 Linux/Android arm64 构建均通过。

实现提交：`8f5894276a9774f4c19896ed31294e06cfc3d26c`（`feat(canvas): make infinite documents genuinely unbounded`）。

## 2. 范围

修改：

- `apps/meowo/lib/canvas_view.dart`：无极视口分支、世界变换、相机命令、背景、命中测试、PNG 导出。
- `apps/meowo/lib/editor_page.dart`：工具栏相机入口、视口中心插入、无极页面栏、PNG/PDF 导出分支。
- `apps/meowo/lib/ink_ops.dart`：逻辑边界、内容检测/包围盒、空画布回退视口。
- `apps/meowo/test/infinite_canvas_test.dart`：新增 9 个测试。

文档：`docs/agent/04-ux-interaction-spec.md`、`docs/agent/12-final-1.0-baseline.md`、计划、本报告、操作日志。

未修改：核心 C++、FFI/ABI、`.meowo` 格式、MuPDF 导入、附件面板、页面选择器与翻页逻辑。

## 3. 完成内容

### 3.1 无界视口

- 无极文档不再创建按页面尺寸放大的 `Positioned + CustomPaint`；直接返回视口尺寸的 `CustomPaint`，不存在 100k 点巨型画布分配。
- 世界到屏幕：`screen = offset + world * zoom`；无极初始缩放 100%。缩放范围 10%–800%。
- 逻辑边界 `kInfiniteCanvasBounds = ±100,000 pt`；平移、滚轮缩放、双指手势和初始 fit 后统一夹取，保证可见视口不整体移出边界。
- 旧 1600×1200 页面宽高不再参与无极平移、绘制、文本框宽度或导出范围。

### 3.2 背景与渲染

- 无极背景为连续纸张色 `#FFFCF5`；横线 28 pt、方格/点阵 24 pt 锚定世界原点，在屏幕/视口空间绘制，仅遍历可见视口内的线/点；屏幕间距小于 6 px 时淡出。
- 无极不绘制页面边框、页阴影或固定页矩形；书页/书籍继续使用原有 `_paintPaper`、源页贴图和页框阴影。
- 笔迹、荧光笔、文本、图片、附件统一在世界变换下绘制；无极对远离视口的元素按保守包围盒 + 最大边余量跳过，旋转图片和文本溢出不会因裁剪误消失。
- 选中框、套索、进行中的笔迹仍在世界坐标绘制，线宽/控制点按 `1/scale` 保持屏幕尺寸。

### 3.3 相机与交互

- `CanvasViewState` 增加只读查询：`scale`、`viewOffset`、`visibleWorldRect`、`visibleWorldCenter`、`worldToScreen`、`screenToWorld`、`pagePixelRect`。
- 增加 `resetToOrigin()` 与 `fitContent()`；工具轨在无极文档显示“回到原点”“适应内容”，书页/书籍继续显示“适应页面”。
- 无极初始视图：有可见内容时适应内容（屏幕边距 48 pt）；空白文档原点位于屏幕 `(64, 64)`、缩放 100%。
- 鼠标滚轮以指针为中心缩放；手工具/中键平移；双指手势；笔/触摸绘制路径未改。无极不传入页面滑动回调。
- 无极字段“文本框”在当前可见视口中心创建 360×160 文本框；图片与附件也放在视口中心附近。`page_body` 仍锚定在原点附近（48,48，宽 720），不参与常规选择拖动。
- 无极底部页面栏隐藏上一页/下一页/插入页/删除页/页码选择器，仅显示“无极画布”和逻辑范围；书页/书籍页面栏行为未改。

### 3.4 命中、变换与撤销

- 无极点击命中先把屏幕坐标转为世界坐标；负坐标文本/笔迹可点击、套索选择、拖动、缩放、擦除和编辑。
- 书页点击仍使用页局部坐标；无极与书页分支分离，避免 “减去 offset” 造成书页回归。
- 无极 CanvasView 使用 `GlobalKey<CanvasViewState>` 以支持工具栏命令；书页不使用该 key，避免 240 ms 翻页过渡期间新旧页同时持有同一 GlobalKey。
- 撤销/重做仍保存整个文档 JSON；画布页 ID 不变，CanvasView State 未重建，元素与相机均保留。

### 3.5 导出

- `infiniteContentBounds()`：汇总所有可见图层元素与非空 `page_body`，外扩 32 pt；空画布回退 `Rect.fromLTWH(0, 0, 1000, 700)`。隐藏图层不导出；内容不与逻辑边界相交，避免静默裁掉遗留越界数据。
- 旋转图片使用保守对角线包围盒，可能增加留白但不会裁切。
- `renderInfiniteCanvasPng()`：按内容区域以 1:1 世界坐标渲染，视口偏移取 `-region.topLeft`；输出单边 ≤4096 px、总像素约 ≤1200 万，超限等比降采样而非裁切。
- 无极 PNG 文件名使用 `<标题>-canvas.png`，提示“按内容裁切”；无极 PDF 页面尺寸取内容区域，单边超过 14400 pt 时等比缩小。书页/书籍 PNG/PDF 路径保持原实现。

## 4. 未完成/偏差

- 无极相机不跨会话持久化：重开文档有内容则适应内容，空白则回到原点。`04` 原“回到上次相机”目标未实现。
- 无极 `page_body` 高度仍固定 1600 pt，依赖既有溢出角标；动态测高未实现（`04` 已标注当前限制）。
- 元素可见性只做保守包围盒跳过，没有 R-tree/分块/空间索引；远距离大量元素仍可能产生绘制调用。
- 100,000 pt 边界的视觉精度与交互性能未做真实压测；自动化只覆盖数千 pt 与边界夹取。
- 导出面积超限时等比降低分辨率，不裁内容；超大画布可能因此像素密度不足。未实现分块 PNG/矢量 PDF。
- 旋转图片导出使用对角线包围盒，空白边距偏大。
- 未在 Android 真机/模拟器上验证触摸、手写笔、双指缩放与中键/触控板行为；Linux 只做启动冒烟。

## 5. 验证与证据

### 自动化

```bash
./scripts/test_all.sh
```

结果：

- CTest `1/1` 通过（内部 8 个 gtest case）。
- `flutter analyze`：`No issues found!`
- Flutter/Dart 测试：`43/43` 通过（原有 34 + 新增 9）。

新增测试覆盖：

| 测试 | 验证点 |
|---|---|
| `infinite viewport pans beyond the old fixed page rectangle` | 画布尺寸等于视口 800×800；平移到旧 1600×1200 之外；不抛异常 |
| `infinite panning clamps to the logical bounds` | 缩放到 10% 后大幅平移，视口不越出 ±100,000 pt |
| `pen strokes can be placed at negative world coordinates` | 原点附近落笔得到负世界坐标 |
| `negative-coordinate element can be selected and moved` | 负坐标文本命中、拖动差量正确 |
| `paged documents still use the fitted page rectangle` | 500 pt 页 fit 为 728 px、居中 36 px；仍使用页尺寸 CustomPaint |
| `infinite toolbar resets to origin and fits content` | 两个工具栏入口存在；书页“适应页面”不出现；原点 (64,64)；远内容可 fit |
| `infinite text boxes are created at the view center` | 文本框中心与当前可见视口中心一致 |
| `infinite export crops to content with padding` | 包围盒覆盖 −600/−400 与 2000/1500；PNG 宽高等于导出区域 |
| `infinite content bounds fall back to a documented viewport` | 空画布回退 1000×700 |

### 构建

```bash
./scripts/build_linux_app.sh
```

结果：`apps/meowo/build/linux/x64/release/bundle/meowo` 构建成功；bundle 约 68 MB。

```bash
timeout 8s apps/meowo/build/linux/x64/release/bundle/meowo
```

结果：运行至超时（exit 124），无崩溃；仅有环境光标主题警告 `Unable to load from the cursor theme`。

```bash
./scripts/build_android_apk.sh
```

结果：Android arm64 release APK 构建成功：`apps/meowo/build/app/outputs/flutter-apk/app-release.apk`，31,703,753 bytes（Gradle 显示 31.7 MB），SHA256 `ba1639933d85f418942bfe980e368493d59c605c6d65b6b792582ba9002bdc47`。

### 手工/设备

| 设备 | OS | 构建 | 场景 | 结果 |
|---|---|---|---|---|
| 开发机 | Linux（Wayland） | release bundle | 启动 8 秒 | 未崩溃；未做交互验收 |
| Android 真机/模拟器 | — | arm64 release APK | 平移/缩放/手写/导出 | 未安装、未验证 |

## 6. 文档更新

- `docs/agent/04-ux-interaction-spec.md`：无极画布视觉/背景、文本框与图片/附件落点、`page_body` 当前高度限制、页面栏、相机/边界/工具栏、导出裁切与分辨率上限。
- `docs/agent/12-final-1.0-baseline.md`：§9 无极导出规则；OQ-008 备注无限画布裁切已实现。
- `docs/agent/plans/infinite-canvas.md`：计划与完成记录。
- `.meowo-agent/operation-log.md`：本次操作记录。

## 7. 风险与遗留

- 100,000 pt 边界只做了逻辑/自动化验证，未做真机视觉与性能压测；Skia 在极端坐标下的文本/图片质量需后续确认。
- 无极相机不持久化，用户重开文档会重新 fit/回原点；若需保持阅读位置，应单独设计文档级 camera 字段（会触及格式与兼容性）。
- `page_body` 固定高度导致长正文依赖溢出角标；动态测高需要文本布局测量与导出/搜索一致性设计。
- 导出降采样上限保证“不失败/不裁内容”，但不保证超大画布的可读性；后续应提供分块导出或矢量 PDF。
- 未验证 Android 真机触摸/手写笔/系统返回手势；Linux release 仅启动冒烟。

## 8. 结论与下一步

满足本次改造的可观察目标：无极文档不再受固定页面矩形限制，负/远坐标元素可交互，背景无页框，相机入口与导出裁切可用，书页/书籍行为未回归。自动化 43/43、CTest 8 个 case、analyze、Linux release 与 Android arm64 release APK 均通过。

建议下一步：

1. 在 Android 真机/平板验证双指缩放、手写笔、负坐标落笔与工具栏可达性。
2. 对 100,000 pt 边界和数千元素做视觉/性能压测，必要时引入分块/空间索引。
3. 设计无极相机持久化与 `page_body` 动态测高。
4. 为超大画布导出增加分块或矢量方案，替代单纯降采样。
