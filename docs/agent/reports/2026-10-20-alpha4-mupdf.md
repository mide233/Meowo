# Meowo 1.0.0-alpha.4 — MuPDF 统一书籍引擎

- 日期：2026-10-20
- 状态：`Completed`（Alpha 验证完成；非正式发布）
- 分支：`dev-agent`
- 范围：PDF/EPUB 统一改用 MuPDF；移除 Poppler、Chrome、Android `PdfRenderer` 过渡桥。

## 1. 交付内容

### 1.1 统一导入链路

- 新增 `packages/meowo_core/native/src/mupdf_import.{h,cpp}`。
- PDF 与 EPUB 均通过 MuPDF 1.26.3 打开、分页、渲染为 120 dpi PNG。
- EPUB 使用固定 A4 版式（595.276 × 841.89 pt）快照，不提供可重排阅读。
- 每页文本层通过 MuPDF `stext` 提取，写入页面 `sourceText`，用于搜索。
- 原始 PDF/EPUB 作为 `book_source` 资源嵌入 `.meowo`，并在 `bookSource` 中记录：
  - `engine: mupdf`
  - `version: 1.26.3`
  - `mime`
  - `format`
  - `pageCount`
  - `title` / `author`
- 单本书最多 500 页；原始源文件上限 512 MiB。
- 加密 PDF 支持密码参数；错误会返回明确信息。

### 1.2 移除的过渡实现

- 删除桌面 `pdfinfo` / `pdftoppm` 调用。
- 删除桌面 Python + Chrome EPUB 转换脚本 `apps/meowo/assets/epub_to_pdf.py`。
- 删除 Android Kotlin `PdfRenderer` MethodChannel 与 `pdf_android.dart`。
- Android `minSdk` 调整为 31，与 MuPDF `android-31` 构建一致。
- Android 与桌面现在共用同一套 `import_pdf` / `import_epub` 核心接口。

### 1.3 构建

- Linux：MuPDF 以 `-fPIC` 静态库链接进 `libmeowo_core.so`。
- Android arm64-v8a：使用 NDK 28.2.13676358、`APP_PLATFORM=android-31`、`ndk-build` 构建 MuPDF 静态库，再链接进核心。
- MuPDF 源码与构建产物位于 `.tools/mupdf/`，均被 Git 忽略。

## 2. 验证

### 2.1 自动测试

```text
C++ CTest:        1/1 test executable, 6/6 gtest cases passed
Flutter/Dart:     20/20 tests passed
flutter analyze:  No issues found
```

覆盖新增内容：

- PDF 导入返回 `mupdf` 引擎；
- 原始 PDF 作为 `application/pdf` 资源嵌入；
- EPUB 导入返回 `mupdf` 引擎；
- 原始 EPUB 作为 `application/epub+zip` 资源嵌入；
- EPUB 标题读取与固定页生成；
- 书页渲染与离屏 PNG 导出回归。

### 2.2 Linux 运行

- Release 构建成功，GUI 启动 8 秒无崩溃。
- 仅有 `Gdk cursor theme` 警告。
- Linux 核心动态库约 42 MB（MuPDF 静态链接）。

### 2.3 Android 模拟器运行（x86_64，仅测试）

测试环境：

- AVD：`meowo_tablet`
- Android 15 / API 35 / x86_64
- 测试 APK：debug，95 MB，含测试用 x86_64 核心
- 正式 arm64 APK：31 MB

已验证：

- 应用启动并显示资料库；
- “导入 EPUB”打开系统文件选择器；
- EPUB 导入成功，编辑器显示 2 页固定页快照与中文内容；
- “导入 PDF”打开系统文件选择器；
- PDF 导入成功，持久化数据中 `bookSource.engine=mupdf`、`format=PDF 1.4`、`mime=application/pdf`、`pageCount=2`；
- 页面 `sourceIndex`、`sourceAssetId`、尺寸 594.96 × 841.92 pt 正确；
- 无 fatal exception。

测试用 x86_64 `jniLibs` 已删除，不进入提交，也不进入发布包。

### 2.4 Android arm64

- `libmeowo_core.so` 11.1 MB，APK 31 MB。
- APK 内含 `lib/arm64-v8a/libmeowo_core.so`，不含已删除的 EPUB 转换脚本。
- **未在真实 arm64 设备或 arm64 模拟器上运行验证。**

## 3. 产物

| 产物 | 大小 | SHA256 |
|---|---:|---|
| `dist/meowo-1.0.0-alpha.4-linux-x64.tar.gz` | 40 MB | `90d54e037b2810a2ebd4befa52c64522c54930290c4d6bb84270a66fb2d9c1b0` |
| `dist/meowo-1.0.0-alpha.4-android-arm64.apk` | 31 MB | `798b5bf54f8a7c6c0f3f47055ad84581f193f763df3b5f427fac14b1d563330e` |

- APK 为 debug 签名，不可用于商店或正式分发。
- 二进制被 Git 忽略；校验值记录在 `dist/SHA256SUMS`。

## 4. 已知限制

- MuPDF 为 AGPL 依赖；发布前必须完成许可证清单、对应源码提供方式与 CVE 跟进流程（OQ-011 仍未完全关闭）。
- Android arm64 未做真机运行验证。
- 未验证真实手写笔、压感、掌拒、两指手势与 P95 延迟。
- EPUB 元数据标题若为 `book.html` 一类内容文件名，回退使用源文件名；已加入测试，但未覆盖所有元数据异常。
- PDF 文本搜索、目录、链接、权限标志尚未接入 UI。
- 大 PDF 仍将全部页面 PNG 放入内存后写入，内存峰值较高。
- 无文件锁、崩溃恢复、格式迁移、第二实例只读。
- Windows 未构建。
- 当前 `.meowo` 仍为预发布 JSON payload，不是冻结格式。

## 5. 手工确认项

1. 在真实 Android arm64 平板上安装 arm64 APK，验证 PDF/EPUB 导入与阅读。
2. 用真实手写笔验证书写、压感、掌拒、两指缩放。
3. 在 Windows 构建并验证触屏笔。
4. 确认 MuPDF AGPL 合规方案与源码提供方式。
5. 确认 EPUB 标题优先级：元数据标题、文件名、内容标题。
6. 确认大 PDF 内存策略与页数上限。
7. 确认是否在 1.0 接入 PDF 文本搜索/目录/链接/权限。
