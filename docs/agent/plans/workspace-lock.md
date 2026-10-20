# 工作区互斥锁计划

- 状态：`Completed`
- 阶段：Alpha.5
- 关联：D-032、Q-120、`03-document-format.md` §8.4

## 目标

防止两个 Meowo 进程同时写同一个资料库，避免 SQLite/WAL 竞争、目录原子 rename 冲突和不可预测的数据损坏。

## 非目标

- 本期不实现只读第二实例；
- 本期不实现 Windows `LockFileEx`；
- 本期不做跨机器/网络盘协调。

## 实现

1. 工作区初始化时创建 `<workspace>/.meowo.lock`。
2. 使用非阻塞 `flock(LOCK_EX | LOCK_NB)`；失败返回可读错误。
3. RAII 持有；成员顺序保证 SQLite 先关闭、再释放锁。
4. 测试首开成功、二次拒绝、关闭后重开。

## 验收

- [x] Linux 编译与 CTest 通过（7 个 gtest case）。
- [x] Dart/Flutter 20 个测试通过，analyze 无错误。
- [x] Linux release 启动无崩溃。
- [x] Android arm64 APK 构建成功。
- [ ] Windows 等价锁。
- [ ] 只读第二实例或正式降级。
- [ ] 真实设备验证。

## 已知风险

- 独占拒绝与 Q-120 的只读体验不一致；
- 锁文件放在工作区根目录，用户误删不影响进程内已持有的 fd，但会降低跨实例协调的可诊断性；
- 网络盘上的 `flock` 语义不保证，云同步目录仍不受支持。
