# Meowo 1.0.0-alpha.5 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

## 最新：alpha.5（工作区独占锁）

- Android：`meowo-1.0.0-alpha.5-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - PDF 与 EPUB 均通过 MuPDF 导入为固定页书籍。
- Linux：`meowo-1.0.0-alpha.5-linux-x64.tar.gz`
  - 解压后运行 `bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 不再依赖 Poppler、Python 或 Chrome。

alpha.5 相对 alpha.4 新增：

- 工作区 `.meowo.lock` 使用 POSIX `flock` 独占锁，阻止第二个实例同时写同一资料库。
- 第二个实例会得到明确错误，而不是静默并发写。
- `pubspec.yaml` 版本更新为 `1.0.0-alpha.5+5`。

## 已知限制

- 当前锁是**独占拒绝**，不是只读第二实例；与 Q-120 的约定存在偏差（D-032）。
- Windows 的 `LockFileEx` 等价锁尚未实现。
- Android arm64 APK 未在真实设备上运行验证；仅 x86_64 模拟器验证了 PDF/EPUB 导入链路。
- 真实手写笔、压感、掌拒、延迟未验证。
- MuPDF 为 AGPL 依赖，发布前需完成合规清单。
- PDF 文本搜索/目录/链接/权限尚未接入 UI。
- 无崩溃恢复、格式迁移。
- 当前 `.meowo` 为预发布 JSON payload，不是冻结格式。

## 历史

- alpha.4：MuPDF 统一 PDF/EPUB，移除 Poppler/Chrome/PdfRenderer 桥。
- alpha.3：画布缩放/平移、Android PDF 导入。
- alpha.2：像素擦除、压感曲线、套索/矩形选择、移动/缩放/复制粘贴。
- alpha.1：首个可运行 Alpha。

校验值见 `SHA256SUMS`。完整证据与缺口见
`docs/agent/reports/2026-10-20-alpha5-workspace-lock.md`。
