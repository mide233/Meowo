# 报告：书页缩小回中

- 状态：Completed
- 日期：2026-10-20
- Agent/负责人：subagent（OpenCode / DeepSeek V4.1 Flash）
- 关联计划：`docs/agent/plans/editor-paged-zoom-out-centering.md`
- 关联需求：`04-ux-interaction-spec.md` §12.1/§12.2
- 关联风险：缩放回中影响放大焦点手感；无极画布误用回中；翻页触发条件回归

## 1. 摘要

修复书页/书籍缩小时页面停在随机偏移的问题。缩小进入 1.0–1.5 倍适合页面区间后，偏移从正常焦点缩放结果逐步插值到居中位置，到最小缩放时精确回到初始的居中适合页面位置。滚轮与双指捏合共用同一规则；放大仍以指针/手势中心为焦点。无极画布保持 10%–800% 缩放与自由平移，相册翻页仍只在高亮 fit + 手工具下触发。

## 2. 范围

- 修改：`apps/meowo/lib/canvas_view.dart`。
  - 新增 `pagedCenteredOffset`、`pagedCenterPull`、`kPagedCenterPullStartZoom`。
  - `_zoomAt` 与 `_updateViewGesture` 在缩小路径应用回中插值。
  - 初始 fit 使用同一居中 helper。
  - 双指反向缩放时重建 gesture baseline，避免回中/焦点路径切换跳变。
- 测试：新增 `apps/meowo/test/paged_zoom_test.dart`。
- 文档：`docs/agent/04-ux-interaction-spec.md`、本计划、本报告、操作日志。
- 未改：`page_turn.dart`、`editor_page.dart`、`.meowo` 格式、C++ 核心、FFI/ABI、导入管线、版本号、发布产物清单。

## 3. 完成内容

### 3.1 居中 helper 与回中进度

- `pagedCenteredOffset(viewport, pageSize, scale)` 返回当前缩放下的居中 top-left：
  `((viewport.w - page.w*scale)/2, (viewport.h - page.h*scale)/2)`。
- 初始 fit 直接使用该 helper，`_viewportSize` / `_pageSize` 由 `LayoutBuilder` 每次构建更新。
- `pagedCenterPull(zoom)` 在 `[kPagedMinZoom, kPagedCenterPullStartZoom]` 即 `[1.0, 1.5]` 内线性从 1 降到 0：
  - `zoom <= 1.0` → 1（完全居中）；
  - `1.0 < zoom < 1.5` → 部分回中；
  - `zoom >= 1.5` → 0（正常焦点行为）。

### 3.2 滚轮缩放

- `_zoomAt` 先按原公式计算焦点偏移，再在 `factor < 1` 且为 paged/book 时调用 `_pagedOffsetForZoomOut`。
- `_pagedOffsetForZoomOut` 将焦点偏移与当前缩放下的居中偏移做 `Offset.lerp`；`pull == 1` 时直接返回居中偏移，避免浮点误差。
- 放大（`factor >= 1`）不调用回中 helper，焦点世界坐标保持不动。

### 3.3 双指缩放

- `_updateViewGesture` 根据 `nextZoom < _zoom` 判断本次是否为缩小，缩小路径应用同一回中 helper。
- 两指反向（缩小后放大或放大后缩小）时，用当前 `_offset` / `_zoom` / 中点 / 距离重建 baseline；反向那一帧不额外移动，下一帧按新方向继续，避免在回中与焦点路径之间跳变。
- 双指平移与 fit 下移动页面的既有行为未改。

### 3.4 无极画布与翻页

- `_pagedOffsetForZoomOut` 在 `_isInfinite` 时直接返回焦点偏移；无极仍执行 10%–800% clamp 与逻辑边界 clamp。
- `pageTurnController.canStart` 仍由 `tool == 'hand' && _atFitZoom` 设置；fit 时页面由同一 helper 居中，翻页起点不回归。
- 相册翻页、相邻页预览、页码选择器、绘制/选择/中键平移未改。

## 4. 未完成/偏差

- 回中跟随缩放输入连续插值，没有额外的时长动画；若一次滚轮/捏合事件从 1.5 以上直接跨到 1.0，剩余位移会在该帧完成。这是输入步长导致，不是“最后一帧突然吸附”的实现缺陷。
- fit 下双指平移仍可临时移动页面；未改变既有交互，下一次缩小到最小缩放时会重新精确居中。
- 未做真实 Android 触摸、手写笔或桌面触控板手感验收。
- 未新增无极相机的持久化或行为变更。

## 5. 验证与证据

### 自动化

```bash
./scripts/test_all.sh
```

结果：

- CTest `1/1` 通过（8 个 gtest case）；
- `flutter analyze`：No issues found；
- Flutter/Dart：`60/60` 通过（原 54 + 新增 6）。

新增 `paged_zoom_test.dart` 用例：

- `paged centered offset follows viewport and fit scale`：helper 与回中进度边界；
- `paged wheel zoom-in keeps the focus point anchored`：滚轮放大焦点世界坐标不动；
- `paged pinch zoom-in keeps the gesture focus anchored`：双指放大焦点不跳；
- `paged wheel zoom-out eases to the centered fit position`：放大→平移→多次缩小，中间帧逐步接近中心，最终 `36 px` 边距、`728×728` 页面、中心误差 `< 0.001 px`；
- `paged pinch zoom-out eases to the centered fit position`：捏合缩小同样逐步回中并精确落位；
- `infinite zoom-out keeps free panning instead of centering`：无极缩到 10% 后无页面框、偏移未被强制居中，且仍可继续自由平移。

### 构建与冒烟

```bash
./scripts/build_linux_app.sh
```

结果：`apps/meowo/build/linux/x64/release/bundle/meowo` 构建成功。

```bash
timeout 8s apps/meowo/build/linux/x64/release/bundle/meowo
```

结果：进程运行至 8 秒超时（exit 124），无崩溃；日志仅有 Impeller 后端与光标主题环境警告。

```bash
./scripts/build_android_apk.sh
```

结果：Android arm64 release APK 构建成功，`apps/meowo/build/app/outputs/flutter-apk/app-release.apk`（31,703,753 bytes / 31.7 MB）。未安装到真机/模拟器。

## 6. 文档更新

- `docs/agent/04-ux-interaction-spec.md` §12.2 增加书页/书籍缩小回中描述，明确放大保持焦点、无极不适用。
- 新增本计划与报告；`.meowo-agent/operation-log.md` 追加记录（已忽略）。

## 7. 风险与遗留

- 回中区间 1.0–1.5 是体验参数，集中在 `canvas_view.dart` 的 `kPagedCenterPullStartZoom`；真机手感验收后可能需要微调。
- 单次大跨度缩小仍会在单帧跨过回中区间；若未来需要平滑时长动画，应在不破坏焦点放大的前提下单独设计。
- 未覆盖真实设备上的双指反向缩放、触控板捏合与手写笔手势。
- fit 下双指平移与回中的交互边界依赖“下一次缩小”触发；若产品要求 fit 时禁止平移，需要另行修改。

## 8. 结论与下一步

- 满足 owner 要求：缩小过程中逐步约束到居中 fit，最小缩放精确居中；放大焦点行为与无极画布行为保持不变。
- 建议后续在 Android 平板与桌面触控板上做一次缩放/捏合手感验收，必要时只调整 `kPagedCenterPullStartZoom`。
