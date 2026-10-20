# Meowo 1.0.0-alpha.7 构建产物

本目录中的二进制是 2026-10-20 在本机生成的 Alpha 构建，**不是正式发布包**。

## 最新：alpha.7（附件面板与引用保护）

- Android：`meowo-1.0.0-alpha.7-android-arm64.apk`
  - Android 12+ / arm64-v8a；debug 签名（不可用于商店发布）。
  - PDF 与 EPUB 均通过 MuPDF 导入为固定页书籍。
- Linux：`meowo-1.0.0-alpha.7-linux-x64.tar.gz`
  - 解压后运行 `meowo-1.0.0-alpha.7-linux-x64/bundle/meowo`。
  - 需要 GTK3、SQLite3；PDF/EPUB 不依赖 Poppler、Python 或 Chrome。

alpha.7 相对 alpha.6 新增：

- 编辑器顶栏新增“附件”入口，打开附件列表。
- 附件列表显示名称、大小、MIME、引用次数；可添加、用系统应用打开。
- 被引用的附件禁止删除，并列出引用位置；解除引用后才允许删除。
- 删除附件后同步清理文档资源与元数据。
- 核心与 Flutter 各有回归测试；附件面板当前不在应用内预览文件。

## 已知限制

- 当前工作区锁是**独占拒绝**，不是只读第二实例；与 Q-120 的约定存在偏差（D-032）。
- Windows 的 `LockFileEx` 等价锁尚未实现。
- Android arm64 APK 未在真实设备上运行验证；仅 x86_64 模拟器验证了 PDF/EPUB 导入链路。
- 真实手写笔、压感、掌拒、两指手势与 P95 延迟未验证。
- MuPDF 为 AGPL 依赖；发布前需完成许可证清单、源码提供方式与 CVE 跟进。
- `.meowo` 仍为预发布 JSON payload；无格式迁移、崩溃恢复、文档级锁。
- PDF 搜索/目录/链接/权限、缩略图、章节、FTS5、Windows 构建仍未完成。
