# MuPDF 接入计划

- 状态：Completed
- 日期：2026-10-20（完成于 2026-10-21）
- 目标：把 PDF/EPUB 的固定页渲染从 Poppler/Chrome/PdfRenderer 桥接切换为 MuPDF，Linux 与 Android 使用同一 C++ 核心路径。
- 决策：D-019/D-020；OQ-011 从“未集成”转为“技术接入完成，发布合规待办”。

## 范围

1. 引入 MuPDF 1.26.3 静态库，Linux CMake 可选 `MEOWO_MUPDF_ROOT`。
2. 新增 MuPDF 渲染模块：打开 PDF/EPUB、密码错误提示、EPUB 固定 A4 布局、120 dpi PNG 页面、页数上限 500。
3. 保存原始 PDF/EPUB 为 `book_source` 资产，文档记录 `bookSource` 元数据。
4. C++ 新增统一 `import_book`；保留 `import_pdf_pages` 作为测试/兼容入口，Flutter 不再使用 Android PdfRenderer。
5. Flutter 所有平台显示 PDF/EPUB 导入，删除 Poppler/Chrome/PdfRenderer 分支。
6. 更新文档、测试、构建脚本、交付报告。

## 非目标

- 不在本轮实现 PDF 表单、签名、注释编辑、文本搜索/大纲完整 UI。
- 不改变固定页快照模型，不做 EPUB 可重排阅读。
- 不做 Windows 构建。

## 验收

- Linux 与 Android 均能编译链接 MuPDF。
- 样例 PDF 与样例 EPUB 导入为固定页书籍；EPUB 文本层可抽取。
- 密码 PDF 返回明确错误，不崩溃。
- 原有 C++/Dart 测试通过；新增 MuPDF 导入测试。
- 产物重新生成并更新校验和。

## 风险

- MuPDF 静态库体积/链接顺序。
- NDK 28 与 MuPDF 1.26.3 的兼容性。
- `fz_try` 长跳转跨越 C++ 析构；渲染循环用 C 风格状态隔离。
- 大文件内存峰值；源文件 512 MiB 限制需明确报错。

## 完成记录

- 2026-10-20：MuPDF 1.26.3 Linux static libs 以 `-fPIC` 构建；Android arm64 static libs 用 NDK 28.2.13676358、android-31 构建。
- `src/mupdf_import.cpp` 统一渲染 PDF/EPUB，120 dpi、最多 500 页，EPUB 固定 A4 布局；页文本写入 `sourceText`。
- `core.cpp` 新增 `import_book`，保存 `bookSource` 与 `book_source` 资产，新增 `import_epub`；`import_pdf` 改走 MuPDF。
- Flutter 全平台直接调用核心导入，删除 `pdf_android.dart`、Kotlin `PdfRenderer` channel、`epub_to_pdf.py`。
- 验证：CTest 1/1（6 个 gtest 用例）、Dart/Flutter 20 个测试、`flutter analyze` 通过；Linux release 启动无崩溃；Android release APK 31.6 MB 构建成功。
- 未完成：真实 Android arm64 设备运行验收（x86_64 模拟器已验证 EPUB/PDF 导入与渲染）、AGPL 发布合规清单、CVE 跟进、正式签名。
