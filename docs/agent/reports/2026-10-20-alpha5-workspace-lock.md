# Meowo 1.0.0-alpha.5 — 工作区独占锁

- 日期：2026-10-20
- 状态：`Completed`（Alpha 验证完成；非正式发布）
- 分支：`dev-agent`
- 范围：工作区打开互斥、避免两个 Meowo 实例同时写同一个资料库；版本号与构建产物更新。

## 1. 交付内容

- 在 `<workspace>/.meowo.lock` 上使用 POSIX `flock(LOCK_EX | LOCK_NB)`。
- 锁在 `Workspace` 生命周期内持有；析构时先关闭 SQLite，再释放文件锁。
- 第二个实例打开同一资料库时立即失败，返回明确错误：`资料库已被另一个 Meowo 实例打开`。
- 新增 C++ 测试 `Core.RejectsConcurrentWorkspaceOpen`：
  - 第一个打开成功；
  - 第二个被拒绝；
  - 关闭第一个后可重新打开。
- `pubspec.yaml` 版本更新为 `1.0.0-alpha.5+5`，描述更新为“pen-first notes, documents and fixed-page books”。

## 2. 偏差与限制

当前实现是**独占拒绝**，不是 Q-120 约定的“只读视图 + 横幅 + 另存副本”。

- 已在 `03-document-format.md`、`12-final-1.0-baseline.md` 和 D-032 记录；
- 1.0 前必须补齐只读第二实例，或在发布说明中明确降级；
- 锁是工作区级，不是单文档级；同一资料库内多文档标签仍在一个进程内共享锁；
- Windows 的 `LockFileEx` 路径尚未实现；当前锁代码为 POSIX。

## 3. 验证

```text
C++ CTest:        1/1 test executable, 7/7 gtest cases passed
Flutter/Dart:     20/20 tests passed
flutter analyze:  No issues found
Linux release:    启动 8 秒无崩溃（仅 Gdk cursor theme 警告）
```

- Android arm64 release APK 构建成功（31.6 MB），未在真实 arm64 设备运行。
- alpha.4 的 Android x86_64 模拟器 PDF/EPUB 运行证据仍适用于导入链路；alpha.5 的锁变更主要是桌面进程行为。

## 4. 产物

| 产物 | 大小 | SHA256 |
|---|---:|---|
| `dist/meowo-1.0.0-alpha.5-linux-x64.tar.gz` | 40 MB | `c00e179d74fead7a4e97ac694c437126e8df5e956ca7484b94ee1f6881370d7f` |
| `dist/meowo-1.0.0-alpha.5-android-arm64.apk` | 31 MB | `acb44ced344a0474f128458017992aedb3a13c6e3304bbf682689e5b99a643e7` |

- APK 仍为 debug 签名，不可用于商店或正式分发。
- 二进制被 Git 忽略；校验值记录在 `dist/SHA256SUMS`。

## 5. 待人工确认

1. 在 Linux 上同时启动两个实例，确认第二个实例提示文案与退出行为。
2. 在 Windows 上实现并验证 `LockFileEx` 等价锁。
3. 决定是否在 1.0 实现只读第二实例，还是正式接受“独占拒绝”的降级。
4. 真实 Android arm64 设备安装与运行验证。
5. 真实手写笔/压感/掌拒/P95 验证。

## 6. 下一步

- 冻结 `.meowo` 格式并加入迁移/崩溃恢复；
- 文件锁跨平台（Windows）；
- 只读第二实例或明确降级；
- PDF 文本搜索/目录/权限；
- 真实设备与性能验收。
