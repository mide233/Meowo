# Meowo 1.0.0-alpha.7 — 附件面板与引用保护

- 日期：2026-10-20
- 状态：`Completed`（Alpha 验证完成；非正式发布）
- 分支：`dev-agent`
- 范围：附件列表、外部打开、添加、引用检测与受保护删除。

## 1. 交付内容

### 1.1 核心能力

新增两个文档级操作：

- `list_assets`：返回资源元数据、`referenced`、`referenceCount` 和引用位置。
- `delete_asset`：删除未被引用的资源；仍被引用时拒绝删除并返回引用位置。

引用扫描覆盖：

- `bookSource.assetId`；
- 页面本底文本中的 `meowo://asset/<id>`；
- 每页、每图层的元素 `assetId` / `sourceAssetId`；
- 元素文本中的 `meowo://asset/<id>`。

删除前必须在文档数据库中删除资源行；早期实现误在 workspace 数据库执行，已修正并加入回归测试。

### 1.2 Flutter 附件面板

编辑器顶栏新增“附件”按钮，打开底部面板：

- 列出文件名、大小、MIME、类型、引用数量；
- 支持添加附件、外部打开；
- 被引用资源显示锁定状态，删除时列出引用位置；
- 无引用资源可删除；
- 面板支持刷新、错误提示和空状态。

### 1.3 明确边界

- 不在应用内预览附件；所有打开操作交给系统应用。
- 不执行附件中的脚本或可执行文件。
- Android 端的外部打开仍受平台限制，当前会给出“不支持”的明确提示。
- 引用检测是基于文档结构的扫描，不替代完整的资源垃圾回收。

## 2. 验证

```text
C++ CTest:        1/1 executable, 8/8 gtest cases passed
Flutter/Dart:     24/24 tests passed
flutter analyze:  No issues found
```

新增 C++ 回归测试 `Core.AssetReferenceProtection`：

1. 添加附件并挂到页面元素；
2. `list_assets` 返回引用；
3. 被引用时 `delete_asset` 抛出错误；
4. 移除元素后删除成功；
5. 再次查询为空。

Linux release 与 Android arm64 release 均构建成功。Linux release 启动 8 秒无崩溃，仅有 GTK cursor theme 警告。Android APK 未在真实 arm64 设备上运行。

## 3. 产物

| 产物 | 大小 | SHA256 |
|---|---:|---|
| `dist/meowo-1.0.0-alpha.7-linux-x64.tar.gz` | 40 MB | `7db295fbdb0bd71fa5c9900499173e7ffa69e895c50ad52eb514c348f85ddd8b` |
| `dist/meowo-1.0.0-alpha.7-android-arm64.apk` | 31.6 MB | `79c36f058bcf1a018e39314bd5203c381489a953ee26f2d902e3b6ea12861c81` |

- APK 为 debug 签名，不可用于商店或正式分发。
- 二进制被 Git 忽略；校验值记录在 `dist/SHA256SUMS`。

## 4. 已知限制

- Android 附件外部打开尚未接入平台 intent。
- 引用扫描覆盖常见文档字段，但未来新增元素类型必须同步扩展。
- 未实现孤立资源自动垃圾回收；当前仅提供受保护的手动删除。
- 未在真实 Android arm64 设备验证。
- Alpha.5 独占工作区锁仍与 Q-120 的“第二实例只读”存在偏差。
- MuPDF AGPL 合规、CVE 跟进、签名、格式冻结、崩溃恢复、迁移、PDF 文本搜索/大纲/权限、缩略图、章节、Windows 仍未完成。

## 5. 手工确认项

1. 在真实 Android 设备上验证附件添加、列表、外部打开提示和删除。
2. 验证附件引用位置提示是否足以让用户理解“为什么不能删”。
3. 确认 Android 外部打开应使用系统 intent，而不是当前占位提示。
4. 确认资源垃圾回收的时机与是否需要“清理未引用资源”入口。
