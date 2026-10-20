# 报告：相册式跟手翻页

- 状态：Completed
- 日期：2026-10-20
- Agent/负责人：subagent（OpenCode / DeepSeek V4.1 Flash）
- 关联计划：`docs/agent/plans/editor-album-page-turn.md`
- 关联需求：`04-ux-interaction-spec.md` §2.4/§12.1/§12.2
- 关联决策：D-019–D-031（文档类型、翻页）
- 关联风险：翻页与绘制/平移/双指缩放冲突；相邻页预览性能；书籍源页图片加载

## 1. 摘要

书页与喵书籍的翻页从“松手后触发滑入”改为相册式跟手翻页：手工具在适合页面缩放下水平拖动时，当前页随手指移动，上一页/下一页在两侧同屏露出；松手按距离/速度吸附或回弹。首页/末页越界只做阻尼回弹。书页/书籍缩放下限改为适合页面；无极画布仍无翻页且保留原缩放范围。绘制、双指、中键、页码选择器与导入流程回归测试通过。

## 2. 范围

- 新增：`apps/meowo/lib/page_turn.dart`（`PageTurnController`、`PageTurnLayer`、阈值常量）。
- 修改：`apps/meowo/lib/canvas_view.dart`、`apps/meowo/lib/editor_page.dart`。
- 测试：新增 `apps/meowo/test/page_turn_test.dart`；更新 `apps/meowo/test/page_navigation_test.dart`。
- 文档：`docs/agent/04-ux-interaction-spec.md`、本计划、本报告、操作日志。
- 未改：`.meowo` 格式、C++ 核心、FFI/ABI、导入管线、版本号、发布产物清单。

## 3. 完成内容

### 3.1 手势仲裁

- 翻页入口在 `CanvasView` 的手工具分支，且 `PageTurnController.canStart` 由当前构建状态设置：paged/book、`tool == 'hand'`、`_atFitZoom`。
- 指针按下后进入 pending；移动超过 8 logical px 后锁定轴：
  - 水平占主导（`|dx| ≥ 1.15|dy|`）→ 跟随翻页；
  - 垂直占主导 → 取消 pending，回落到原手工具平移；
  - 第二指落下 / 指针取消 → 取消翻页。
- 笔、荧光笔、橡皮、选择、文本等工具完全不进入翻页分支；鼠标中键在翻页判断前处理。
- 无极画布不创建 `PageTurnLayer`，也不向 `CanvasView` 传 controller；即使误传 controller，`CanvasView` 也会把 `canStart` 固定为 false。

### 3.2 跟手视觉

- `PageTurnLayer` 将当前 `CanvasView` 平移 `progress × viewportWidth`。
- 上一页/下一页用 `MeowoCanvasPainter` 以只读方式绘制在左右各一个视口位置，并使用相同位移；预览不创建额外可交互画布，不共享编辑器 `GlobalKey`。
- 预览使用 `RepaintBoundary`，拖动时只更新 `Transform`；相邻页图片在 `EditorPage._loadPageImages` 中与当前页一起预加载，书籍源页也能出现在预览中。
- 提交时抑制原 `_PageSlideTransition`，避免预览落位后再次滑入；按钮/页码选择器跳转仍使用原 240 ms 过渡。

### 3.3 吸附、边界与缩放

| 参数 | 默认值 |
|---|---|
| 距离阈值 | `max(72px, 25% × 视口宽度)` |
| 快速滑动 | `≥700 logical px/s` 且位移 `≥40px` |
| 轴锁 | 8 logical px，水平/垂直占优比 1.15 |
| 首页/末页阻尼 | 位移 ×0.22，最大 12% 视口 |
| 提交动画 | 240 ms easeOutCubic |
| 回弹动画 | 260–300 ms easeOutCubic |

- 第一页向右、最后一页向左：只产生阻尼位移，松手回弹，不换页、不循环。
- paged/book：`_zoom` 相对适合页面比例的下限从 0.25 改为 1.0；滚轮和双指缩放均不能小于适合页面。
- infinite：保持 0.1–8.0 缩放、无界平移，无翻页。
- 翻页仍走 `_setPage`：flush 保存、清空选择、重置活动图层、加载新页及相邻页图片；页码标签与选择器读取同一 `_pageIndex`。

## 4. 未完成/偏差

- 相邻页是只读 painter 预览，不能直接在预览上绘制或选择；落位后当前页恢复完整交互。
- 预览按“每个页面占一个视口槽位”布局，页面较窄时相邻页之间会看到较宽的背景留白；这是与系统相册整屏槽位一致的取舍。
- 未做真实 Android/桌面触控板手势与手写笔验收；仅 widget 测试、Linux release 冒烟。
- 未对超大数据量书籍页做帧率测量；当前限制最多两张相邻页预览并预加载图片。
- 减少动态效果通过 `MediaQuery.disableAnimations` 生效，跳过补间但保留拖动跟手。

## 5. 验证与证据

### 自动化

```bash
./scripts/test_all.sh
```

结果：

- CTest `1/1` 通过（8 个 gtest case）；
- `flutter analyze`：No issues found；
- Flutter/Dart：`54/54` 通过。

新增/更新用例覆盖：

- 手工具 fit 下左拖跟手并吸附下一页、右拖吸附上一页；
- 短拖回弹不换页；
- 首页右拖 / 末页左拖阻尼且不换页；
- 笔工具拖动只绘制，不翻页；
- 放大后手工具水平拖动只平移；
- 滚轮缩小止于适合页面；
- 无极画布即使有 controller 也不翻页且仍可平移；
- 双指捏合缩放不翻页；
- 鼠标中键拖动平移不翻页；
- 速度阈值可在未达距离阈值时提交翻页；
- 编辑器手工具翻页后页码标签更新，笔工具拖动不换页；
- 页码选择器、导入进度层等既有测试继续通过。

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

结果：Android arm64 release APK 构建成功，`apps/meowo/build/app/outputs/flutter-apk/app-release.apk`（31.7 MB）。未安装到真机/模拟器。

## 6. 文档更新

- `docs/agent/04-ux-interaction-spec.md`：
  - §2.4 页面切换改为相册式跟手横移；
  - §12.1 重写翻页触发、阈值、边界阻尼、减少动态效果；
  - §12.2 明确书页/书籍最小缩放为适合页面，无极保留 10% 下限。
- 新增本计划与报告；`.meowo-agent/operation-log.md` 追加记录（已忽略）。

## 7. 风险与遗留

- 真实设备上 25%/700 px/s 阈值可能需要按手感微调；参数集中在 `page_turn.dart` 顶部常量。
- 相邻页预览会解码最多两张额外页面图片；500 页书籍仍只加载当前页与前后页，未见内存增长测试。
- 若未来无极画布需要分页，不能复用本层，需先定义页面容器。
- 翻页提交依赖保存 flush；保存失败时 `_flushSave` 仍继续切页并显示失败状态，不阻塞导航。

## 8. 结论与下一步

- 满足用户确认的 6 条交互规格与测试/构建要求。
- 建议后续在 Android 平板/手写笔与桌面触控板上做手感验收，必要时只调整阈值常量。
- 可选改进：为相邻页预览增加与当前页一致的纸张阴影/间距调优，或在超宽视口下改为相邻槽位布局。
