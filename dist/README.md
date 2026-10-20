# Meowo 1.0.0-alpha.3 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

## 最新：alpha.3（画布视图 + Android PDF）

- Android：`meowo-1.0.0-alpha.3-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - 支持 PDF 导入（Android `PdfRenderer` 固定页快照）。
  - EPUB 导入仍依赖桌面 Chrome/Poppler 桥接，Android 暂未启用。
- Linux：`meowo-1.0.0-alpha.3-linux-x64.tar.gz`
  - 解压后运行 `bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 导入额外需要 `pdfinfo`、`pdftoppm`、Python3 + Chrome（EPUB）。

alpha.3 相对 alpha.2 新增：

- 画布/书页缩放：鼠标滚轮、触控板/双指缩放。
- 画布/书页移动：工具栏“移动”模式拖动；双指平移。
- “适应页面”一键复位。
- Android PDF 导入：原生 `PdfRenderer` 渲染为固定页，再写入 `.meowo` 书籍。
- 修复 alpha.2 选择/笔迹在缩放后坐标不一致的问题。

## 历史

- alpha.2：像素擦除、压感曲线、套索/矩形选择、移动/缩放/复制粘贴。
- alpha.1：首个可运行 Alpha（资料库、书页/无极画布、基础笔迹、文本、图片、附件、PDF/EPUB 导入、基础导出）。

校验值见 `SHA256SUMS`。构建与运行说明、已知缺口见
`docs/agent/reports/2026-10-20-alpha3-viewport-android-pdf.md`。
