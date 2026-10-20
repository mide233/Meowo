# 报告：书页滑动导航、页码选择器与导入进度

- 状态：Completed
- 日期：2026-10-20
- Agent/负责人：subagent（OpenCode / DeepSeek V4.1 Flash）
- 关联计划：`docs/agent/plans/editor-page-navigation-and-import-progress.md`
- 关联需求：`12-final-1.0-baseline.md` §3.1/§3.3/§10；`04-ux-interaction-spec.md` §12.1/§13.4
- 关联决策：D-019–D-031
- 关联风险：单指绘制/平移与翻页手势冲突；大页数选择器性能；重复导入与失败恢复

## 1. 摘要

书页与喵书籍新增了受控的水平滑动翻页：仅在适合页面缩放、清晰水平快速滑动、且手势从页面外边缘起手（任意工具）或使用移动工具从页面内起手时触发，不会影响笔绘制、双指缩放、移动工具普通平移或鼠标中键平移。底部“第 X / Y 页”可点击打开轻量页面卡片选择器；无极画布保持“无极画布”且不提供翻页/选择器。资料库 PDF/EPUB/Markdown 导入新增不可关闭的不确定进度层、重复导入保护与正确的结果打开/失败复位。

## 2. 范围

- 修改：`apps/meowo/lib/canvas_view.dart`、`apps/meowo/lib/editor_page.dart`、`apps/meowo/lib/library_page.dart`、`apps/meowo/lib/app_state.dart`。
- 新增测试：`apps/meowo/test/page_navigation_test.dart`、`apps/meowo/test/import_state_test.dart`。
- 文档：`docs/agent/04-ux-interaction-spec.md`、计划、本报告、操作日志。
- 未改 `.meowo` 格式、核心 C++、FFI/ABI、导入管线、版本号或发布产物清单。

## 3. 完成内容

### 3.1 滑动翻页

- `CanvasView` 新增可选 `onPageSwipe`：`+1` 下一页、`-1` 上一页；`EditorPage` 仅对非无极文档传入回调。
- 触发条件：
  - 页面处于适合页面缩放（`zoom≈1.0`，且已完成 fit）；
  - 触摸手势水平位移占主导（`|dx| ≥ 1.6|dy|`）、达到距离阈值且 650 ms 内速度 ≥0.4 px/ms；
  - 从页面外灰色边缘起手时任意工具可用，且不会开始绘制/选择；
  - 从页面内起手时仅移动工具可用；普通短距/斜向拖动继续平移；
  - 双指手势、笔输入、鼠标中键不参与；页面切换时清理未完成手势。
- `EditorPage` 使用 240 ms 横向滑入/滑出 + 淡入过渡；翻页期间保留上一页图片资源，最多保留两页，下一次加载自动修剪。
- 翻页仍走原有 `_setPage`：先 flush 保存、清空选择、重置活动图层、按需加载新页图片。

### 3.2 页码选择器

- 底部页码改为 `TextButton`，保留“第 N / Y 页”文本；点击打开模态底部页面选择器。
- 选择器使用轻量页面卡片（非实时缩略图，界面明确标注），显示页序、纸张背景预览、源页/书页/笔记页标签；当前页高亮并显示“当前”。
- 点击卡片关闭选择器并调用 `_setPage` 跳转；书籍源页与笔记页均可跳转。
- 无极文档显示“无极画布”，无 `page-count-button`，不提供选择器。

### 3.3 导入进度与互斥

- `AppState` 新增 `importing`、`importLabel`；`_importInBackground` 在入口设置状态并通知，`finally` 中复位。
- 导入仍使用原有后台 `Isolate.run` + 短生命周期无锁工作区句柄。
- 导入期间：资料库显示不确定进度层、`ModalBarrier(dismissible:false)`、`PopScope(canPop:false)`，并禁用 PDF/EPUB/Markdown 导入按钮。
- 重复调用在 `AppState` 层直接忽略；首个导入完成后刷新资料库并打开新文档。
- 失败时异常继续抛给资料库 `_guard` 显示错误 Snackbar，状态在 `finally` 复位；成功/失败都不会残留进度层。

## 4. 未完成/偏差

- 滑动翻页只处理触摸；桌面鼠标拖拽/触控板横扫未绑定翻页，仍使用上一页/下一页按钮或页码选择器。
- 页面选择器是轻量卡片，不是真实内容缩略图；未复用 `renderPagePng` 批量渲染，避免 500 页/书籍源页加载开销。
- 翻页动画为固定 240 ms，未单独读取系统“减少动态效果”设置（应用当前其他动画也未统一处理）。
- 导入进度为不确定进度，核心没有进度回调，未显示百分比。
- 未做真机手写笔/Android 触摸滑动验收；仅 Flutter widget 测试与 Linux release 启动冒烟。

## 5. 验证与证据

### 自动化

```bash
./scripts/test_all.sh
```

结果：CTest `1/1` 通过（8 个 gtest case）；`flutter analyze` 无问题；Flutter/Dart 测试 `34/34` 通过。

新增测试覆盖：

- 页面外边缘左滑请求下一页；
- 页面内笔快速滑动仍产生笔迹且不翻页；
- 移动工具短距拖动仍平移、不翻页；
- 移动工具页面内快速横滑请求下一页；
- 页码卡片选择器高亮当前页并跳转；
- 编辑器中边缘滑动切换到上一页；
- 无极画布无页码选择入口；
- 导入进度层存在、导入按钮禁用、屏障不可关闭；
- Markdown 导入状态、刷新、打开文档与重复/失败复位。

### 构建

```bash
./scripts/build_linux_app.sh
```

结果：`apps/meowo/build/linux/x64/release/bundle/meowo` 构建成功。

```bash
timeout 8s apps/meowo/build/linux/x64/release/bundle/meowo
```

结果：进程运行至超时（exit 124），无崩溃；仅有环境光标主题警告 `Unable to load from the cursor theme`。

```bash
./scripts/build_android_apk.sh
```

结果：Android arm64 release APK 构建成功，`apps/meowo/build/app/outputs/flutter-apk/app-release.apk`（31.6 MB）。未安装到真机/模拟器。

### 手工/设备

| 设备 | OS | 构建 | 场景 | 结果 |
|---|---|---|---|---|
| 开发机 | Linux（Wayland） | release bundle | 启动 8 秒 | 未崩溃，未做交互验收 |
| Android 真机/模拟器 | — | arm64 release APK | 滑动/手写/导入 | 未安装、未验证 |

## 6. 文档更新

- `docs/agent/04-ux-interaction-spec.md`：补充页码选择、滑动翻页阈值/冲突规则、导入进度与重复保护。
- `docs/agent/plans/editor-page-navigation-and-import-progress.md`：完成记录。
- `.meowo-agent/operation-log.md`：追加本次操作。
- 未更新 `docs/agent/README.md`：未创建新版本/发布产物。

## 7. 风险与遗留

- 手势边界仍可能因设备触摸采样/用户习惯产生误判；已用“适合页面 + 高阈值 + 水平占主导 + 边缘/移动工具”收敛，后续可依据真机反馈调整阈值。
- 页面卡片不展示页面实际内容，用户需依赖页序/源页号识别；后续可做异步低分辨率缩略图缓存。
- 导入中系统返回被阻止且没有取消入口；大文件导入耗时较长时用户只能等待。若需要取消，应单独设计核心取消协议。
- 未验证 Android 真机触摸滑动、手写笔与导入进度层的实际表现。

## 8. 结论与下一步

功能与自动化验收完成，Linux release 可构建并启动。下一步建议在 Android 真机/模拟器验证边缘滑动与双指缩放仲裁，并评估是否为页面选择器增加异步缩略图。
