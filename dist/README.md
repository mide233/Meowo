# Meowo 1.0.0-alpha.4 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

## 最新：alpha.4（MuPDF 统一书籍引擎）

- Android：`meowo-1.0.0-alpha.4-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - PDF 与 EPUB 均通过 MuPDF 导入为固定页书籍。
- Linux：`meowo-1.0.0-alpha.4-linux-x64.tar.gz`
  - 解压后运行 `bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 不再依赖 Poppler、Python 或 Chrome。

alpha.4 相对 alpha.3 新增：

- PDF/EPUB 统一使用 MuPDF 1.26.3。
- EPUB 在 Android 与桌面均可导入。
- 原始 PDF/EPUB 作为 `book_source` 嵌入 `.meowo`。
- 书籍页面文本层可提取，供后续搜索使用。
- 移除桌面 Poppler、Chrome/Python EPUB 转换桥。
- 移除 Android `PdfRenderer` MethodChannel。
- Android `minSdk` 调整为 31。

## 已知限制

- Android arm64 APK 未在真实设备上运行验证；仅 x86_64 模拟器验证了导入链路。
- 真实手写笔、压感、掌拒、延迟未验证。
- MuPDF 为 AGPL 依赖，发布前需完成合规清单。
- PDF 文本搜索/目录/链接/权限尚未接入 UI。
- 无文件锁、崩溃恢复、格式迁移。
- 当前 `.meowo` 为预发布 JSON payload，不是冻结格式。

## 历史

- alpha.3：画布缩放/平移、Android PDF 导入。
- alpha.2：像素擦除、压感曲线、套索/矩形选择、移动/缩放/复制粘贴。
- alpha.1：首个可运行 Alpha。

校验值见 `SHA256SUMS`。完整证据与缺口见
`docs/agent/reports/2026-10-20-alpha4-mupdf.md`。
