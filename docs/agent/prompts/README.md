# Agent 提示词库

本目录存放可复用的角色提示词与任务模板。提示词只定义**工作方式**，不定义产品事实；产品事实以 `docs/agent/` 主文档为准。

---

## 1. 文件清单

| 文件 | 用途 | 典型使用者 |
|---|---|---|
| [master-implementation.md](master-implementation.md) | 统领一个阶段/大型任务的实现 Agent | 主实现 Agent |
| [cpp-core.md](cpp-core.md) | C++23 核心、FFI、存储、几何、图书适配 | 核心 Agent |
| [flutter-app.md](flutter-app.md) | Flutter UI、状态、平台集成、交互 | 应用 Agent |
| [test-and-quality.md](test-and-quality.md) | 测试、基准、设备矩阵、CI 质量 | 测试 Agent |
| [review.md](review.md) | 独立代码/文档审查 | 审查 Agent |
| [feature-task-template.md](feature-task-template.md) | 单个功能任务的填空模板 | 任意实现 Agent |

---

## 2. 使用顺序

1. 先阅读 `docs/agent/README.md` 指定的主文档；
2. 选择角色提示词；
3. 若是具体功能，使用 `feature-task-template.md` 填充；
4. 将填充后的任务提示与角色提示一起交给 Agent；
5. Agent 必须先写/更新 `docs/agent/plans/` 中的计划，再改代码；
6. 完成后按 `reports/README.md` 写报告。

不要让 Agent 仅凭一句“实现编辑器”开始。至少提供：任务 ID、范围、非目标、关联需求/决策、验收标准、计划路径。

---

## 3. 通用前置段（建议附加到每个提示）

```text
你是 Meowo（喵记）项目的实现 Agent。

开始前必须实际阅读：
- docs/agent/README.md
- docs/agent/00-product-charter.md
- docs/agent/01-functional-requirements.md
- docs/agent/09-decisions-and-open-questions.md
- docs/agent/03-document-format.md
- docs/agent/02-technical-architecture.md
- docs/agent/04-ux-interaction-spec.md
- docs/agent/05-quality-and-test-strategy.md
- docs/agent/07-engineering-conventions.md
- docs/agent/08-agent-operating-protocol.md
- 当前阶段/任务计划（若存在）
- 相关历史报告（若存在）

工作目录：仓库根目录。所有 Agent 可读的计划和报告必须写入 docs/agent/ 下的 Markdown 文件，不能只存在于对话。

权威顺序：用户当前指令 > Accepted 决策 > MUST 需求 > 格式/架构 > 其他规范 > 计划/代码。发现冲突先停止并报告，不得静默偏离。

未写入 docs/agent/plans/ 的任务计划，不得开始实现。
不得引入未批准的依赖/许可证，不得改变 1.0 范围，不得伪造保存/测试结果。
完成后必须运行相关测试，并在 docs/agent/reports/ 写报告。
```

---

## 4. 占位符约定

功能模板使用双花括号占位符：

| 占位符 | 含义 |
|---|---|
| `{{TASK_ID}}` | 稳定任务 ID，如 `P1-LIB-001` |
| `{{TASK_TITLE}}` | 简短标题 |
| `{{PHASE}}` | 路线图阶段 |
| `{{REQ_IDS}}` | 关联需求 ID，逗号分隔 |
| `{{DECISION_IDS}}` | 关联决策 ID |
| `{{PLAN_PATH}}` | 计划文件路径 |
| `{{SCOPE}}` | 必须交付的内容 |
| `{{NON_GOALS}}` | 明确不做 |
| `{{ACCEPTANCE}}` | 可验证验收标准 |
| `{{RISKS}}` | 已知风险/限制 |
| `{{NOTES}}` | 额外上下文 |

不要留下未填占位符就启动任务；若某项确实未知，写“待确认”并列入计划。

---

## 5. 提示词纪律

- 提示词不能覆盖主文档，不能自行增加需求或放宽验收。
- 不把密钥、令牌、真实用户文档内容放进提示。
- 不依赖“上一轮对话记得”的隐含上下文；每个任务自带必读清单与范围。
- 不要求 Agent 执行破坏性 git/文件操作，除非用户明确授权。
- 不要求 Agent 绕过测试、伪造结果或把未完成说成完成。
- 子 Agent 的提示必须自包含；主 Agent 对其产出负责。
- 提示词更新后，若改变了工作流/权限，应同步更新 `08-agent-operating-protocol.md`。

---

## 6. 推荐的任务包结构

```text
1. 角色提示词（如 cpp-core.md）
2. 通用前置段
3. 填充后的 feature-task-template
4. 相关文件/接口/测试位置
5. 当前已知失败/限制
6. 期望的报告路径
```

任务包越具体，Agent 越不需要猜测；但不要用提示词替代正式需求文档。
