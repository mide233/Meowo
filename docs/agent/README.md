# Meowo（喵记）Agent 文档中心

> 本目录是所有 AI Agent 与协作者阅读、维护的项目事实来源（Single Source of Truth）。
> 当前基线版本：`v0.1.0`（2026-10-19）  
> 当前状态：文档基线、提示词与 Phase 0 计划已完成；等待项目负责人回答决策访谈中的 P0 问题；尚未开始编码。

---

## 1. 文档读取顺序

任何 Agent 在开始工作前，必须按以下顺序阅读：

| 顺序 | 文档 | 作用 |
|---:|---|---|
| 1 | [00-product-charter.md](00-product-charter.md) | 产品愿景、用户、原则、范围、术语 |
| 2 | [01-functional-requirements.md](01-functional-requirements.md) | 需求编号、优先级、验收标准 |
| 3 | [09-decisions-and-open-questions.md](09-decisions-and-open-questions.md) | 已定决策与待确认事项 |
| 4 | [03-document-format.md](03-document-format.md) | 文档数据模型与 `.meowo` 文件格式 |
| 5 | [02-technical-architecture.md](02-technical-architecture.md) | Flutter / C++23 / FFI / 渲染 / 线程架构 |
| 6 | [04-ux-interaction-spec.md](04-ux-interaction-spec.md) | 页面结构、交互、笔与触控行为、视觉规范 |
| 7 | [05-quality-and-test-strategy.md](05-quality-and-test-strategy.md) | 测试、性能门槛、跨平台验收 |
| 8 | [07-engineering-conventions.md](07-engineering-conventions.md) | 编码规范、依赖、Git、Definition of Done |
| 9 | [08-agent-operating-protocol.md](08-agent-operating-protocol.md) | Agent 工作流程、权限、计划与交付格式 |
| 10 | [06-roadmap.md](06-roadmap.md) | 阶段划分、依赖关系、退出标准 |
| 11 | [10-risk-register.md](10-risk-register.md) | 风险、触发条件、缓解责任人 |
| 12 | 当前任务对应的 [plans/](plans/) 文档 | 任务级范围、步骤和进度 |
| 13 | 相关 [reports/](reports/) 报告 | 已发生的验证结果、偏差与遗留 |

角色专用提示词位于 [prompts/](prompts/)。它们不能覆盖本目录中的需求、决策和约束；若提示词与主文档冲突，以主文档为准并立即报告冲突。

### 1.1 配套目录

| 目录 | 内容 |
|---|---|
| [prompts/](prompts/) | 主实现、C++、Flutter、测试、审查提示词与功能任务模板 |
| [plans/](plans/) | 阶段计划与任务计划（无计划不实施） |
| [reports/](reports/) | 实际结果、测试证据、性能数据、缺陷与遗留 |
| [10-risk-register.md](10-risk-register.md) | 风险、触发信号、缓解与责任人 |
| [11-owner-interview.md](11-owner-interview.md) | 项目负责人决策访谈：162 个问题、P0 清单与回答记录 |

## 2. 权威顺序

发生冲突时，按以下顺序裁决：

1. 用户当前明确指令；
2. [09-decisions-and-open-questions.md](09-decisions-and-open-questions.md) 中状态为 `Accepted` 的决策；
3. [01-functional-requirements.md](01-functional-requirements.md) 中带 MUST 语义的需求；
4. [03-document-format.md](03-document-format.md) 与 [02-technical-architecture.md](02-technical-architecture.md)；
5. 其余规范文档；
6. 任务计划、代码注释与历史实现。

**不得**为了迁就已有代码而静默降低需求；也不得因为“以后可能有用”擅自扩张范围。发现冲突时，先在 `09-decisions-and-open-questions.md` 记录，再向用户确认。

## 3. 状态与文档纪律

- 所有 Agent 可读文档、计划、调研报告必须放在 `docs/agent/` 内，使用 Markdown。
- 计划文档必须真实更新，不能只在对话中承诺“之后补文档”。
- 改变需求、架构、文件格式、交互或测试门槛时，必须在同一次变更中更新对应文档。
- 文件格式、FFI ABI、数据库 schema 的变更必须附带迁移方案与测试。
- 已取代的决策不得删除，标记为 `Superseded` 并链接新决策。
- 面向用户的界面文案必须可本地化；文档内部统一使用中文，技术名词保留英文并以中文解释。
- 不得把密钥、令牌、个人路径、用户隐私内容写入仓库或文档。

## 4. 路径约定

计划中的正式仓库结构（Phase 0 创建）：

```text
Meowo/
├── apps/
│   └── meowo/                    # Flutter 应用
├── packages/
│   └── meowo_core/               # Flutter FFI 插件 + Dart 绑定
│       ├── lib/
│       ├── native/               # C++23 核心（CMake）
│       └── test/
├── tools/                        # 构建、代码生成、基准脚本
├── assets/                       # 品牌、字体、测试公共资源
├── docs/agent/                   # 本文档中心
└── .github/workflows/            # CI
```

> 在脚手架建立前，实际命令以仓库根目录的 `README.md` 和 [plans/phase-0-foundation-and-spikes.md](plans/phase-0-foundation-and-spikes.md) 为准。

## 5. 当前关键待确认项

在进入书籍（PDF/EPUB）与 Markdown 文件导入开发之前，必须确认下列高杠杆决策。尚未形成决策的细节问题、追问与 P0/P1/P2 完整清单见 [11-owner-interview.md](11-owner-interview.md)；未回答项不得由 Agent 静默假设。

1. **软件许可证与 EPUB 引擎路线**：是否接受 AGPL/GPL 路线（可较快得到完整 EPUB 分页），或必须采用宽松许可证方案。
2. **“MD 阅读”的范围**：是仅指笔记内 Markdown 文本的渲染，还是必须支持导入独立 `.md` 文件。
3. **文本编辑体验**：1.0 是否接受“Markdown 源码编辑 + 实时预览”，或必须一开始就提供所见即所得编辑。
4. **云端同步**：1.0 是否坚持纯本地、无账号。
5. **导出与本底文本溢出**：1.0 是否只需 `.meowo` 快照导出；书页本底文本超出页面时采用“固定页 + 溢出提示”还是自动续排。

完整选项与推荐见 [09-decisions-and-open-questions.md](09-decisions-and-open-questions.md)。未确认前，Agent 不得擅自引入相关依赖或承诺交付形式。

## 6. 术语速查

| 中文 | 英文 / 代码名 | 含义 |
|---|---|---|
| 喵记 | Meowo | 本应用 |
| 喵文档 | Meowo Document | 一篇笔记，单个 `.meowo` 文件 |
| 无极喵文档 | Infinite Document | 单一无限画布文档 |
| 书页喵文档 | Paged Document | 分页、固定纸张大小的文档 |
| 喵书籍 | Meowo Book | 由 PDF/EPUB 导入的只读书页背景文档 |
| 书页 | Page | 固定尺寸页面；无极文档只有一个逻辑画布 |
| 图层 | Layer | 一个书页/画布上的元素容器 |
| 元素 | Element | 笔迹、图片、文本、附件图标等 |
| 画布本底文本 | Page Body Text | 类似记事本的页面正文区域，仍属于元素 |
| 图书页背景 | Book Page Background | PDF/EPUB 渲染出的只读底层内容 |
| 资料库 | Library | 本地文档列表与管理界面 |
| 笔刷预设 | Brush Preset | 颜色、宽度、压力曲线等设置的组合 |
| 图书引擎 | Book Engine | PDF/EPUB 探测、分页、渲染适配层 |

---

## 7. 后续动作

1. 项目负责人审阅本基线，确认第 5 节与决策文档中的待确认项。
2. Agent 按 [plans/phase-0-foundation-and-spikes.md](plans/phase-0-foundation-and-spikes.md) 执行脚手架与高风险技术验证。
3. 每个实现任务使用 [plans/README.md](plans/README.md) 的模板建立任务计划，不得跳过。
