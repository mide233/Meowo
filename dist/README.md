# Meowo 1.0.0-alpha.1 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

- Android：`meowo-1.0.0-alpha.1-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - PDF/EPUB 导入在 Android 上暂不可用。
- Linux：`meowo-1.0.0-alpha.1-linux-x64.tar.gz`
  - 解压后运行 `bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 导入额外需要 `pdfinfo`、`pdftoppm`、Python3 + Chrome（EPUB）。

校验值见 `SHA256SUMS`。构建与运行说明、已知缺口见
`docs/agent/reports/2026-10-20-autonomous-1.0-delivery.md`。
