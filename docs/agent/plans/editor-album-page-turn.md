# 计划：相册式跟手翻页

- 状态：Completed
- 阶段：1.0 Alpha 体验修正
- 负责人/Agent：subagent（OpenCode / DeepSeek V4.1 Flash）
- 创建日期：2026-10-20
- 最后更新：2026-10-20
- 关联需求：`04-ux-interaction-spec.md` §12.1/§12.2；`12-final-1.0-baseline.md` 页面导航
- 关联决策：D-019–D-031（文档类型、翻页）
- 关联风险：翻页手势与绘制/平移/双指缩放冲突；相邻页预览性能；书籍源页图片加载

## 1. 目标

1. 书页/喵书籍支持相册式翻页：水平拖动时当前页跟手，上一页/下一页同屏露出。
2. 仅在手工具 + 最小（适合页面）缩放下触发；其余情况手工具只平移，绘制工具永不翻页。
3. 松手按距离/速度吸附到相邻页，否则平滑回弹；首页/末页越界只做阻尼回弹。
4. 书页/书籍缩放下限改为适合页面；无极画布保持原缩放范围且没有翻页。
5. 不回归绘制、双指平移缩放、滚轮缩放、中键平移、选择、撤销/重做、页码选择器与导入进度。

## 2. 非目标

- 不实现 3D 翻书、页面卷曲或阴影材质动画。
- 不为无极画布增加页面或翻页。
- 不改变 `.meowo` 格式、C++ 核心、FFI/ABI、导入管线或发布版本。
- 不实现相邻页的可编辑画布；相邻页只作为只读预览。

## 3. 背景与现状

- `CanvasView` 原先在 `9e8adc6` 中实现“适合页面 + 快速横滑 + 页面边缘/手工具”的翻页回调，松手后才切页，没有跟手位移。
- 书页缩放原为 0.25–8（相对适合页面比例），允许缩小到小于窗口。
- `EditorPage` 使用 `_PageSlideTransition` 做 240 ms 滑入/滑出；相邻页内容未预加载。

## 4. 方案

### 4.1 手势与状态

- 新增 `page_turn.dart`：
  - `PageTurnController` 管理 pending → dragging → settling/committing 状态与 `AnimationController`；
  - `PageTurnLayer` 渲染跟手位移与相邻页只读预览。
- `CanvasView` 只在 paged/book、手工具、`zoom≈1` 时把指针交给 controller；轴锁前 8 logical px 内不位移：
  - 水平占主导 → 翻页；
  - 垂直占主导 → 回落到原有手工具平移；
  - 第二指/指针取消 → 取消翻页并恢复。
- 笔、荧光笔、橡皮、选择、文本等工具不进入翻页分支；中键在翻页判断前处理。

### 4.2 视觉与吸附

- 当前页整体平移 `progress × viewportWidth`；上一页/下一页以 `MeowoCanvasPainter` 只读绘制在左右各一个视口位置，并随同一位移平移。
- 提交吸附目标为 ±1（相邻页落到当前页的 fit 位置），回弹目标为 0。
- 相邻页图片在 `EditorPage._loadPageImages` 中与当前页一起预加载；翻页层仅缓存静态预览，拖动时只更新 `Transform`。
- 翻页提交时抑制原 `_PageSlideTransition`，避免“预览落位 + 再次滑入”的双重动画；按钮/页码选择器跳转仍保留原过渡。

### 4.3 阈值与参数

| 参数 | 默认值 |
|---|---|
| 距离阈值 | `max(72px, 25% × 视口宽度)` |
| 快速滑动 | `≥700 logical px/s` 且位移 `≥40px` |
| 轴锁 | 8 logical px，水平/垂直占优比 1.15 |
| 首页/末页阻尼 | 位移 ×0.22，最大 12% 视口 |
| 提交动画 | 240 ms easeOutCubic |
| 回弹动画 | 260–300 ms easeOutCubic |
| 减少动态效果 | 跳过补间，直接落位 |

### 4.4 缩放

- paged/book：`_zoom` 相对适合页面比例的下限从 0.25 改为 1.0；滚轮与双指缩放同受此限制。
- infinite：保持 0.1–8.0 与原有无界行为。

## 5. 任务拆分

| # | 任务 | 产出 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 新增翻页 controller/layer | `page_turn.dart` | 跟手位移、相邻页预览、吸附/回弹 | 完成 |
| 2 | CanvasView 手势接入 | `canvas_view.dart` | 仅 fit+hand；笔/双指/中键不误触 | 完成 |
| 3 | Editor 集成与图片预加载 | `editor_page.dart` | 页码一致、无双重动画、书籍源页可见 | 完成 |
| 4 | 缩放下限 | `canvas_view.dart` | paged/book 不低于 fit；infinite 不变 | 完成 |
| 5 | 测试 | `page_turn_test.dart` 等 | 触发条件、吸附、边界、无极、回归 | 完成 |
| 6 | 文档与构建 | 本计划、报告、UX 规范 | analyze/test/build/smoke | 完成 |

## 6. 测试与验收

- 自动化：
  - `flutter analyze`
  - `flutter test`
  - `./scripts/test_all.sh`
- 重点用例：
  - 手工具在 fit 下跟手左/右拖并吸附下一页/上一页；
  - 短拖回弹，不换页；
  - 首页右拖/末页左拖阻尼且不换页；
  - 笔工具拖动只绘制；
  - 放大后手工具拖动只平移；
  - 滚轮缩小止于适合页面；
  - 无极画布即使误传 controller 也不翻页；
  - 双指缩放、中键平移不翻页；
  - 编辑器翻页后页码标签更新。
- 手工/构建：
  - Linux release 构建 + 8 秒启动冒烟；
  - Android arm64 release APK 构建。

## 7. 风险与依赖

- 大页面/书籍源页预览可能增加翻页首帧成本；当前限制为最多两张相邻页，并预加载图片。
- 相邻页预览为只读 painter，不响应点击/绘制；这是有意的范围限制。
- 手势阈值需要真机触摸/手写笔验证；widget 测试无法覆盖真实触感。
- 若后续需要无极画布分页，需先引入明确的页面容器，不复用本层。

## 8. 进度记录

| 日期 | 状态 | 说明 |
|---|---|---|
| 2026-10-20 | In Progress | 实现 controller/layer、CanvasView/Editor 接入、缩放下限与测试 |
| 2026-10-20 | Completed | 全量测试、Linux/Android 构建与 Linux 冒烟通过；报告已写 |

## 9. 结果

- 实现提交：`dev-agent` 上的相册翻页提交（见报告与操作日志）。
- 测试：CTest 1/1（8 个 gtest case）；Flutter/Dart 54/54；analyze 无问题。
- 构建：Linux release 成功；Android arm64 release APK 成功（31.7 MB）；Linux 8 秒冒烟无崩溃。
- 偏差：相邻页为只读预览；未做真机触摸/手写笔验收。
