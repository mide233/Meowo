# Meowo 1.0.0-alpha.2 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

## 最新：alpha.2（手写核心补齐）

- Android：`meowo-1.0.0-alpha.2-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - PDF/EPUB 导入在 Android 上暂不可用。
- Linux：`meowo-1.0.0-alpha.2-linux-x64.tar.gz`
  - 解压后运行 `bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 导入额外需要 `pdfinfo`、`pdftoppm`、Python3 + Chrome（EPUB）。

alpha.2 相对 alpha.1 新增：

- 矢量像素擦除（笔迹切分）、整笔/像素模式、当前/所有可见图层范围。
- 笔与荧光笔独立压感曲线，可编辑、重置、实时预览。
- 套索/矩形选择、移动、四角缩放、删除、复制/粘贴。

## 历史

- alpha.1：首个可运行 Alpha（资料库、书页/无极画布、基础笔迹、文本、图片、附件、PDF/EPUB 导入、基础导出）。

校验值见 `SHA256SUMS`。构建与运行说明、已知缺口见
`docs/agent/reports/2026-10-20-autonomous-1.0-delivery.md`。
