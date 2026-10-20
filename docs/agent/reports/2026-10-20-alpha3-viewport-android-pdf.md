# 2026-10-20 · Alpha.3 画布视图与 Android PDF 报告

- 状态：`Completed / Alpha.3`
- 版本：`1.0.0-alpha.3`
- 日期：2026-10-20
- 触发问题：用户反馈“画布/书页无法缩放移动，Android 端只能导入 md”
- 结论：**已补画布缩放/平移与 Android 原生 PDF 导入；Android EPUB 仍受引擎限制，未伪称完成。**

## 1. 交付物

| 交付物 | 路径 |
|---|---|
| Linux release | `dist/meowo-1.0.0-alpha.3-linux-x64.tar.gz` |
| Android release APK | `dist/meowo-1.0.0-alpha.3-android-arm64.apk` |
| 报告 | 本文件 |
| 操作日志 | `.meowo-agent/operation-log.md`（Git 忽略） |

SHA-256：

```text
a16db69929edb53e7cfcf26683aaa1857b0ca1152fba6432021ab207ff880c2e  meowo-1.0.0-alpha.3-android-arm64.apk
d2dcf995bc6469243cd3feebf6431c182b12c2ad0c7aab33428798a46e7f9283  meowo-1.0.0-alpha.3-linux-x64.tar.gz
```

APK 仍是 debug 签名，不能作为正式发布包。

## 2. 画布/书页缩放与移动

- 画布从固定适应页面改为可变换视图：
  - `_zoom` 0.25–8.0。
  - `_offset` 为视图平移。
  - 笔迹、选择框、套索、图片、文本、附件全部使用同一页面坐标变换。
- 鼠标滚轮缩放，以指针位置为中心。
- 工具栏新增“移动”手形工具：单指/鼠标拖动平移。
- 双指触摸始终平移/缩放；第二根手指按下会取消未完成的绘制/擦除/选择手势。
- “适应页面”按钮复位缩放与平移。
- 修复缩放后点击、套索、缩放选择框的坐标换算。

## 3. Android PDF 导入

- 新增 Kotlin `MethodChannel("meowo/pdf")`：
  - 使用 Android 原生 `PdfRenderer`。
  - 每页渲染为 120 dpi PNG；限制 500 页；逐页释放 Bitmap。
  - 输出到应用缓存目录，返回路径与页面点尺寸。
- 新增 C++ 核心操作 `import_pdf_pages`：
  - 接收路径与页面尺寸，创建 `book` 文档。
  - 每页写入 PNG asset，设置 `sourceAssetId`、`sourceIndex`、`isNotePage=false`。
  - 与桌面 `import_pdf` 共用书籍结构。
- Android 资料库“导入 PDF”按钮已启用。
- 桌面端继续使用 Poppler `pdfinfo`/`pdftoppm`。
- 临时渲染目录在导入完成/失败后删除。

## 4. 验证

- `scripts/test_all.sh`：
  - CTest 通过。
  - `flutter analyze` 无问题。
  - Dart/Flutter **19 项**通过。
- 新增测试：
  - 预渲染 PDF 页面创建书籍（C++ `import_pdf_pages`）。
  - 手形工具平移视图。
  - 鼠标滚轮缩放视图。
- 既有测试：套索/矩形、移动、角手柄缩放、笔迹提交、手机布局、FFI、PDF 导入、启动错误页。
- Linux alpha.3 压缩包解压启动 7 秒无崩溃（仅 GTK cursor theme 警告）。
- Android release APK 编译成功（22.8 MB）；**未在真机/模拟器运行**。

## 5. 未完成 / 已知限制

- **Android EPUB 仍不可导入**：当前 EPUB 快照依赖桌面 Chrome + Python；MuPDF 尚未集成。资料库在 Android 上仍隐藏 EPUB 按钮。
- Android PDF 未做真机验证；`PdfRenderer` 对加密/权限受限 PDF 的行为未验证。
- 双指缩放/平移未在真实触屏验证；测试仅覆盖鼠标滚轮与手形拖动。
- 画布平移没有边界限制，极端拖动后需“适应页面”复位。
- 选择命中仍是包围盒/多边形相交，不是逐笔精确命中。
- 自由旋转、跨文档粘贴、文件锁、崩溃恢复仍未完成。
- Windows 未构建。

## 6. 复现

```bash
cd /home/mide/local_playground/Meowo
./scripts/test_all.sh
./scripts/build_linux_app.sh release
./scripts/build_android_apk.sh
```
