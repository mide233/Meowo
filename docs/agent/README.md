# Meowo（喵记）Agent 文档中心

> 本目录是所有 AI Agent 与协作者阅读、维护的项目事实来源（Single Source of Truth）。
> 当前基线版本：`v1.0-baseline.1`（2026-10-20）  
> 当前状态：负责人已完成 Q-001–Q-162 访谈；1.0 合并基线已冻结；**Alpha.3 已构建（Linux release + Android arm64 APK）**，新增画布缩放/平移、Android 原生 PDF 导入。交付与缺口见 [alpha.3 报告](reports/2026-10-20-alpha3-viewport-android-pdf.md)。

---

## 1. 文档读取顺序

任何 Agent 在开始工作前，必须按以下顺序阅读：

| 顺序 | 文档 | 作用 |
|---:|---|---|
| 1 | [00-product-charter.md](00-product-charter.md) | 产品愿景、用户、原则、范围、术语 |
| 2 | [01-functional-requirements.md](01-functional-requirements.md) | 需求编号、优先级、验收标准 |
| 3 | [12-final-1.0-baseline.md](12-final-1.0-baseline.md) | **1.0 合并后的最终范围、交互、格式与验收基线** |
| 4 | [09-decisions-and-open-questions.md](09-decisions-and-open-questions.md) | 已定决策与待确认事项 |
| 5 | [03-document-format.md](03-document-format.md) | 文档数据模型与 `.meowo` 文件格式 |
| 6 | [02-technical-architecture.md](02-technical-architecture.md) | Flutter / C++23 / FFI / 渲染 / 线程架构 |
| 7 | [04-ux-interaction-spec.md](04-ux-interaction-spec.md) | 页面结构、交互、笔与触控行为、视觉规范 |
| 8 | [05-quality-and-test-strategy.md](05-quality-and-test-strategy.md) | 测试、性能门槛、跨平台验收 |
| 9 | [07-engineering-conventions.md](07-engineering-conventions.md) | 编码规范、依赖、Git、Definition of Done |
| 10 | [08-agent-operating-protocol.md](08-agent-operating-protocol.md) | Agent 工作流程、权限、计划与交付格式 |
| 11 | [06-roadmap.md](06-roadmap.md) | 阶段划分、依赖关系、退出标准 |
| 12 | [10-risk-register.md](10-risk-register.md) | 风险、触发条件、缓解责任人 |
| 13 | 当前任务对应的 [plans/](plans/) 文档 | 任务级范围、步骤和进度 |
| 14 | 相关 [reports/](reports/) 报告 | 已发生的验证结果、偏差与遗留 |

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

Q-001–Q-162 的主干问题已全部回答，1.0 范围以 [12-final-1.0-baseline.md](12-final-1.0-baseline.md) 为准。仍需人工确认或补证的事项：

1. **OQ-009**：具体测试设备型号、RAM、Android 笔协议（Q-140b）。
2. **OQ-010**：Android 是否有主动压感笔，是否调整 Android 手写承诺。
3. **OQ-008**：PDF/PNG 导出页面范围、无限画布裁切与页码。
4. **OQ-011**：MuPDF 构建、AGPL 合规、体积与安全更新。
5. **OQ-012**：商标检索、正式图标/启动图/品牌资产。
6. **OQ-013**：`.md` 超长段落/表格/代码块分页规则。
7. **OQ-014**：真机手写延迟/压感/掌拒的验收证据格式。

完整状态见 [09-decisions-and-open-questions.md](09-decisions-and-open-questions.md)。未确认前，Agent 不得把相关能力宣称为已完成，也不得静默假设。

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
