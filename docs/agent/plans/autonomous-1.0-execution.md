# 自治执行计划 · Meowo 1.0 初版

- 状态：`In Progress`
- 日期：2026-10-20
- 负责人：Agent（在用户授权下自治执行）
- 依据：`12-final-1.0-baseline.md`、`09` D-019–D-031

## 1. 目标

在不破坏本机与工作区外文件的前提下，交付：

1. 合并后的可执行文档基线；
2. 可构建、可运行的 Flutter + C++23 跨平台应用骨架；
3. 覆盖核心闭环的 1.0 初版：资料库、无极/书页文档、笔迹、文本、图片、附件、图层、页面、搜索、保存/恢复、书籍导入、导出；
4. C++ 单元测试、Dart 单元/Widget 测试、可行性集成测试；
5. Git 本地提交；
6. 待人工确认项与未完成项报告。

## 2. 非目标

- 不在本轮宣称“1.0 完美完成”；不伪造真机性能/压感数据。
- 不实现云同步、账号、OCR、AI、加密、插件、WYSIWYG、系统打印、iOS/macOS/Web。
- 不执行 `git push`、发布、签名、商店上传。
- 不安装需要交互 sudo 的系统包；不删除用户文件。

## 3. 阶段

### A. 文档合并（先做）

- 新增 `12-final-1.0-baseline.md`。
- 09 增加 D-019–D-031，关闭 OQ-001–006，新增 OQ-008–014。
- README 更新阅读顺序、状态与待确认项。
- 产出：决策冲突清单、实现边界。

### B. 工具链与仓库

- Flutter 3.47.7 stable 安装到 `.tools/`（Git 忽略）。
- 创建 `apps/meowo`、`packages/meowo_core`、`tools/`。
- C++23 + CMake + GoogleTest/CTest；SQLite3；Dart FFI。
- Linux 桌面优先；Android 构建在 SDK/JDK 可用时验证。
- 操作记录写入 `.meowo-agent/operation-log.md`（Git 忽略）。

### C. 核心闭环 MVP

优先级从高到低：

1. workspace/catalog + `.meowo` SQLite 打开/保存/迁移；
2. 文档/页面/图层/元素模型；
3. 笔迹添加、擦除、撤销/重做、压力/颜色/粗细；
4. Flutter 画布渲染、工具切换、保存状态；
5. 文本框/`page_body`、Markdown 源码+预览；
6. 图片导入与裁剪/旋转/翻转；
7. 附件导入/引用保护；
8. 搜索、回收站、文件夹、标签页；
9. 书页页面操作、章节；
10. PDF/EPUB 导入（先打通固定页快照；MuPDF 若环境不允许则记录阻塞）；
11. 导出 `.meowo`/PDF/PNG；
12. 自动保存/恢复、诊断日志。

### D. 测试与验收

- C++：模型、事务、笔迹切分、迁移、损坏输入、并发锁。
- Dart：控制器、格式化、Widget smoke。
- 集成：创建→书写→保存→重开→搜索→导出。
- 性能：可重复 microbenchmark；真实 P95 标记待真机。
- 可访问性：自动化扫描；不宣称完整读屏。

### E. 交付

- 本地 Git 提交（可分多个逻辑提交）。
- `docs/agent/reports/2026-10-20-autonomous-1.0-delivery.md`：完成/未完成/证据/风险/手工确认项。
- 运行说明、构建命令、已知缺陷。

## 4. 关键实现决策（本轮）

- **格式**：`.meowo` 仍是单文件 SQLite；首版 payload 使用版本化 JSON 以尽快打通端到端，schema/格式标记为 pre-1.0；在正式 1.0 前必须迁移到 FlatBuffers 或冻结 JSON 并升版本。该临时决定写入报告。
- **FFI**：C ABI + JSON 命令/响应；Dart 只通过 `meowo_core` 访问文档；错误用错误码 + UTF-8 消息。
- **存储**：C++ 使用系统 SQLite3；WAL；事务；workspace catalog 独立 SQLite。
- **渲染**：Flutter `CustomPainter` 画当前页；进行中笔迹在 Dart 侧即时绘制，完成后提交 C++；已提交笔迹由 C++ 提供页面 JSON。
- **PDF/EPUB**：优先使用系统 Poppler 工具生成固定页 PNG 作为过渡；架构保留 `BookEngine`，MuPDF 集成作为 OQ-011。不得在报告中称 MuPDF 已完成。
- **Android**：仅当 SDK/JDK 可用时构建 APK；否则交付 Linux 可运行版并记录 Android 阻塞。

## 5. 退出标准

- `cmake --build` + `ctest` 通过；
- `flutter analyze` 无 error；`flutter test` 通过；
- Linux 桌面可启动并完成“创建→书写→保存→重开→搜索→导出”；
- Git 工作区干净（除忽略的本机日志/工具链）；
- 交付报告列明所有未完成与需手工确认项。
