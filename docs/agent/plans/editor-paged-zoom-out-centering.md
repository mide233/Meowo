# 计划：书页缩小回中

- 状态：Completed
- 阶段：1.0 Alpha 体验修正
- 负责人/Agent：subagent（OpenCode / DeepSeek V4.1 Flash）
- 创建日期：2026-10-20
- 最后更新：2026-10-20
- 关联需求：`04-ux-interaction-spec.md` §12.1/§12.2
- 关联风险：缩放回中可能改变放大焦点手感；无极画布误用回中；翻页触发条件回归

## 1. 目标

1. 书页/书籍从放大状态缩小时，页面偏移不再停在随机位置。
2. 在接近最小缩放（适合页面）时，把偏移从正常的焦点缩放结果逐步插值到居中位置。
3. 到达 `kPagedMinZoom` 时精确回到初始的居中适合页面位置。
4. 放大仍保持指针/双指中心焦点行为，不触发回中。
5. 无极画布保持 10%–800% 缩放和自由平移，不强制居中。
6. 相册翻页仍只在适合页面 + 手工具下触发，且 fit 时页面居中。

## 2. 非目标

- 不改变书页/书籍的最小缩放值（仍为 1.0 倍适合页面）。
- 不改变无极画布的边界、缩放范围、相机或“回到原点/适应内容”。
- 不增加缩放动画或惯性；回中跟随连续缩放事件插值。
- 不改变翻页手势、阈值、相邻页预览或编辑器页面切换流程。
- 不改变 `.meowo` 格式、C++ 核心、FFI/ABI、导入管线或版本号。

## 3. 背景与现状

- `_zoomAt` 与 `_updateViewGesture` 都以焦点为锚点计算新偏移。
- 书页缩放下限为 `kPagedMinZoom = 1.0`，但缩放事件被 clamp 后，焦点公式仍保留放大时的随机偏移。
- 因此用户缩小到 fit 时，页面虽然大小正确，位置可能偏出视口或停在角落。
- 初次打开页面时已有居中 fit 偏移，但没有可复用的集中 helper，也没有在缩小过程中约束偏移。

## 4. 方案

### 4.1 居中偏移 helper

- 新增 `pagedCenteredOffset(viewport, pageSize, scale)`，按当前视口、页面尺寸和缩放返回居中 top-left。
- 初始 fit 与缩放回中共同使用该 helper；`_viewportSize` / `_pageSize` 在每次 `LayoutBuilder` 构建时更新，避免使用过期布局尺寸。
- 新增 `pagedCenterPull(zoom)`：在 `kPagedMinZoom = 1.0` 到 `kPagedCenterPullStartZoom = 1.5` 之间线性返回 0–1，1.0 时精确为 1。

### 4.2 滚轮缩放

- `_zoomAt` 继续先按焦点计算 `focusOffset`。
- 仅当本次是缩小（`factor < 1`）且为 paged/book 时，按 `pagedCenterPull(newZoom)` 将 `focusOffset` 与当前缩放下的居中偏移做 `Offset.lerp`。
- `pull == 1` 时直接返回居中偏移，保证最小缩放精确居中。
- 放大路径不调用回中 helper，保持焦点不动。

### 4.3 双指缩放

- `_updateViewGesture` 使用同一 helper。
- 根据 `nextZoom < _zoom` 判断本次更新是否为缩小；缩小路径应用回中，放大路径保持焦点公式。
- 两指反向（先缩小后放大）时以当前相机重新建立 gesture baseline，避免从旧的 base offset 跳回未回中位置。
- 双指平移仍可在 fit 下移动页面；下一次缩小到最小缩放时会重新精确居中。

### 4.4 无极画布与翻页

- `_pagedOffsetForZoomOut` 在 `_isInfinite` 时直接返回焦点偏移；无极逻辑、边界 clamp 和 10%–800% 范围不变。
- `pageTurnController.canStart` 仍为手工具 + `_atFitZoom`；fit 时 offset 由同一 helper 保证居中，翻页起点位置不变。

## 5. 任务拆分

| # | 任务 | 产出 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 居中偏移与回中进度 helper | `canvas_view.dart` | 初始 fit 和最小缩放位置一致 | 完成 |
| 2 | 滚轮缩小回中 | `_zoomAt` | 多次缩小逐步接近居中，最终精确 | 完成 |
| 3 | 双指缩小回中 | `_updateViewGesture` | 捏合缩小同样回中，放大焦点不跳 | 完成 |
| 4 | 无极与翻页回归 | `canvas_view.dart` | 无极自由平移；翻页仍仅 fit+hand | 完成 |
| 5 | 测试 | `paged_zoom_test.dart` | 滚轮/捏合/放大焦点/无极 | 完成 |
| 6 | 文档与构建 | 计划、报告、UX 规范 | analyze/test/build 通过 | 完成 |

## 6. 测试与验收

- 自动化：
  - `flutter analyze`
  - `flutter test`
  - `./scripts/test_all.sh`
- 重点用例：
  - 滚轮放大后平移到随机位置，再多次缩小；中间缩放帧逐步接近中心，最小缩放精确为 36 px 边距、728 px 页面；
  - 双指捏合缩小走同样回中路径；
  - 滚轮/双指放大时焦点世界坐标保持在指针/手势中心；
  - 无极画布缩小到 10% 后仍可自由平移，不被强制居中；
  - 既有相册翻页、页码、编辑器和导入测试全部通过。
- 构建：
  - Linux release；
  - Android arm64 release APK。

## 7. 风险与依赖

- 回中发生在 1.0–1.5 倍区间；用户若一次滚轮从 2.0 直接跨到 1.0，仍会在单帧内完成剩余位移，这是输入步长导致，不是额外动画。
- fit 下双指平移仍能临时移动页面；未改变该既有行为，下一次缩小到最小缩放会重新居中。
- 未做真实 Android 触摸/触控板手感验收。
- 回中只影响 paged/book；无极画布的行为由 `_isInfinite` 分支隔离。

## 8. 进度记录

| 日期 | 状态 | 说明 |
|---|---|---|
| 2026-10-20 | In Progress | 实现 helper、滚轮/捏合回中与测试 |
| 2026-10-20 | Completed | analyze、60 个 Dart 测试、8 个 gtest、Linux/Android 构建通过；文档已更新 |

## 9. 结果

- 实现提交：`dev-agent` 上的书页缩小回中提交（见报告与操作日志）。
- 测试：CTest 1/1（8 个 gtest case）；Flutter/Dart 60/60；analyze 无问题。
- 构建：Linux release 成功并完成 8 秒启动冒烟；Android arm64 release APK 成功（31.7 MB）。
- 偏差：无真实设备触摸/触控板验收；单次大跨度缩小仍可能在一帧内跨过回中区间。
