# 2026-10-20 · 自治实现交付报告（Alpha）

> 后续进展：Alpha.2 手写核心补齐见
> `docs/agent/reports/2026-10-20-alpha2-handwriting-core.md`。
> 本报告保留 Alpha.1 的构建与验收证据。

- 状态：`Alpha / 可运行初版`
- 版本：`1.0.0-alpha.1`
- 日期：2026-10-20
- 执行模式：负责人授权无人值守，本地开发、本地提交；不发布、不签名发布、不 push。
- 结论：**已打通“创建 → 书写 → 保存 → 重开 → 搜索 → 导出”的 Linux 桌面闭环，并产出 Android arm64 release APK；这不是功能完整的 1.0，仍有明确的人工验收与缺口。**

---

## 1. 交付物

| 交付物 | 路径 | 证据 |
|---|---|---|
| Flutter 应用 | `apps/meowo/` | `flutter analyze` 无问题；`flutter test` 7 项通过 |
| C++23 核心 | `packages/meowo_core/native/` | CTest 6 项通过；Linux/Android arm64 构建成功 |
| Linux release | `dist/meowo-1.0.0-alpha.1-linux-x64.tar.gz` | 解压后 `bundle/meowo` 可启动，8 秒运行无崩溃 |
| Android release APK | `dist/meowo-1.0.0-alpha.1-android-arm64.apk` | 22.6 MB，arm64-v8a，包含 `libmeowo_core.so` |
| 示例 EPUB/PDF 验证 | `/tmp/meowo-sample.epub`、`/tmp/meowo-sample.pdf` | EPUB → 2 页 PDF；PDF 导入测试通过 |
| 本机操作日志 | `.meowo-agent/operation-log.md` | 不纳入 Git |
| 访谈与基线 | `docs/agent/11-owner-interview.md`、`12-final-1.0-baseline.md`、三份回答补充 | 已提交 |

APK SHA-256：

```text
50b393844d40b0f770f3e878fd2dd06222d482f9fefd5ef7c4e0e82a16dfc7e4
```

Linux 压缩包 SHA-256：

```text
291bd7179ff21a97cd5f7106a93ec11d5ac1e8d04d5a34c861c62c9e2aba5203
```

> 校验值对应构建时刻产物；后续重新构建会变化。APK 使用 debug 签名（Gradle release 配置仍指向 debug signingConfig），**不能作为正式发布包**。

---

## 2. 已实现能力

### 2.1 资料库

- 创建书页文档、无极文档；A4/A5/B5/Letter/Legal 与横竖方向。
- 文档列表、最近更新时间排序、打开标签页、关闭标签页。
- 标题/文本/书籍资源名/附件名搜索（线性扫描；不是 FTS5）。
- 收藏、回收站（软删除/恢复/永久删除）、单层/多层文件夹创建与归属。
- Markdown 文件导入为可编辑书页文档（单页 `page_body`）。
- PDF 导入为固定页书籍（Poppler `pdftoppm`，120 dpi PNG）。
- EPUB 导入为固定页 PDF 书籍（Chrome headless 快照，保留文本层；原 EPUB 作为资源存入文档）。
- `.meowo` 快照导出；PDF 导出（当前页/全部页，栅格化）；当前页 PNG 导出。

### 2.2 编辑器

- 书页/无极画布；页面新增、删除、插入、前后翻页。
- 笔、荧光笔、整笔橡皮；压感采样、颜色、线宽；画布即时绘制，提交后持久化。
- 图层：最多 5 层，新建、删除、重排、显隐、锁定、透明度；层内元素顺序未实现。
- 文本框、页面正文（`page_body`）、Markdown 源码 + 预览。
- 图片导入、显示、缩放位置；附件导入、图标+文件名、系统应用打开。
- 撤销/重做（100 步，文档级快照）。
- 自动保存（350 ms debounce）与保存中/已保存/失败状态。
- 手机与桌面自适应：资料库窄屏单列、编辑器紧凑顶栏、可滚动工具栏。
- 书籍源页只读背景；可在源页后插入笔记页。

### 2.3 核心与格式

- C ABI + JSON 命令；Flutter 不直接打开 `.meowo`。
- 工作区 `workspace.sqlite` 目录 + `documents/<id>.meowo` 单文件 SQLite。
- `.meowo` 设置 `application_id=0x4D454F57`、`user_version=1`、WAL、FULL sync。
- 文档 payload 为版本化 JSON（pre-1.0 临时方案）；资源单独 BLOB 存储。
- C++23、SQLite、nlohmann/json；Android 使用 SQLite amalgamation。
- 跨文档复制/资源深拷贝、格式迁移、文件锁尚未实现。

---

## 3. 验证证据

执行命令（Linux）：

```bash
cmake -S packages/meowo_core/native -B packages/meowo_core/native/build -G Ninja
cmake --build packages/meowo_core/native/build -j2
ctest --test-dir packages/meowo_core/native/build --output-on-failure

export PATH="$PWD/.tools/flutter/bin:$PATH"
cd apps/meowo
MEOWO_CORE_LIB="$PWD/../../packages/meowo_core/native/build/libmeowo_core.so" \
  flutter test
flutter analyze
flutter build linux --release
flutter build apk --release --target-platform android-arm64
```

结果：

- CTest：`6/6` 通过。
- Flutter test：`7/7` 通过，覆盖 FFI 文档闭环、PDF 导入、真实笔迹提交、桌面布局、手机布局、页面离屏渲染。
- `flutter analyze`：`No issues found!`
- Linux release 启动：8 秒运行无崩溃/无异常日志。
- Android release APK：22.6 MB；`lib/arm64-v8a/libmeowo_core.so` 已打包。
- 示例 PDF 导入：1 页书籍，背景资源存在。
- 示例 EPUB：Chrome 快照 2 页 PDF，`pdftotext` 能提取中文。

**未做**：真实手写笔延迟、压感误差、掌拒、两指手势、Android 真机启动、Windows 构建/运行、500 页/20k 笔迹压力测试。因此不得宣称满足 P95 <50 ms 等性能门槛。

---

## 4. 关键实现偏差

1. **MuPDF 未接入**：PDF 使用 Poppler 固定页 PNG，EPUB 使用 Chrome PDF 快照；这是过渡桥，不是最终 MuPDF 引擎。OQ-011 仍未关闭。
2. **文档 payload 是 JSON**：尚未使用 FlatBuffers/规范化表；正式 1.0 前必须冻结或迁移并写迁移测试。
3. **PDF 导出是栅格 PDF**：不保留文本层；全部页导出内存开销大，未做分块/进度。
4. **Markdown 渲染**：使用 `flutter_markdown`（已停止维护），未接 KaTeX、语法高亮、脚注/HTML 白名单等完整规则。
5. **搜索**：线性扫描 JSON 中的文本，不是 FTS5 trigram；大库会慢。
6. **撤销**：文档级 JSON 快照，不是命令级 diff；大文档内存/性能不符合 256MB 预算目标。
7. **自动保存**：350 ms debounce，尚未实现关闭等待、崩溃恢复草稿、第二实例只读锁。
8. **Android 导入限制**：因无 Poppler/Chrome/Python，PDF/EPUB 导入按钮在 Android 隐藏；Android 端目前主要支持本地创建与 Markdown 导入。
9. **桌面打包**：仅产出 Linux release bundle，未生成 deb/rpm/AppImage；Windows 未构建。
10. **无障碍**：仅做布局/基础语义，未跑自动化扫描，也未实现完整键盘/读屏验收。

---

## 5. 尚缺的 1.0 功能（按优先级）

### P0 数据与核心闭环

- 文件锁、第二实例只读视图、关闭等待保存、崩溃恢复草稿/恢复横幅。
- 正式格式冻结/迁移（JSON → 目标 schema）与损坏文件恢复测试。
- 跨文档复制资源深拷贝、引用保护、孤儿 GC。
- 自动保存 1 秒/最长 5 秒策略与失败处理对齐基线。
- PDF 权限标志、PDF 大纲/内部链接/全文搜索；书籍文本层索引。

### P0 笔与画布

- 套索选择、移动/缩放/旋转/删除、跨页粘贴、层内元素顺序。
- 矢量像素擦除（切分笔迹）与擦除手势合并撤销。
- 压力曲线编辑器、笔侧键/笔尾键配置、悬停/预测线。
- 画布缩放/平移/适应内容；无极画布边界与回到原点。
- 真实笔设备 P95、压感、掌拒、两指手势验收。

### P1 内容与书籍

- 图片非破坏裁剪/旋转/翻转编辑器；附件面板/引用位置/删除保护。
- KaTeX 子集、代码高亮、表格横向滚动、任务列表回写、链接确认。
- 章节、缩略图、封面更换、页面多选/拖动重排。
- EPUB 原文件保留与版本迁移；MuPDF 统一引擎。
- PDF/PNG 导出页面范围、无限画布裁切规则（OQ-008）、PNG zip。

### P1 平台与发布

- Windows 构建/安装包与 Windows Ink 输入。
- Android 真机运行、SAF 导入/导出、文件关联/分享、返回键/生命周期。
- Linux deb/rpm/AppImage；Wayland/X11 两套验证。
- 正式签名、release notes、隐私说明、依赖许可证清单。
- 自动化无障碍扫描；字体缩放/高对比度回归。

---

## 6. 需负责人手工确认

| 编号 | 事项 | 当前处理 |
|---|---|---|
| OQ-009 / Q-140b | Android 手写平板型号、RAM、笔协议；其他设备型号 | 仍未知；压感/延迟验收阻塞 |
| OQ-010 | Android 主动笔实测 | 未测；当前只验证了 APK 可构建 |
| OQ-011 | MuPDF 构建、AGPL 合规、安全更新 | 未接入；当前 Poppler/Chrome 过渡 |
| OQ-008 | PDF/PNG 页面范围、无限画布裁切 | 已实现“当前页/全部页”临时方案；自定义范围未定 |
| OQ-012 | 品牌名/商标/图标/启动图 | 仍为占位；未做商标检索 |
| — | Windows 实机/构建环境 | 未提供；本轮未构建 Windows |
| — | 正式发布签名与 GitHub Release | 负责人持有；本轮未发布 |
| — | 课堂日 2 小时真机验收 | 未执行 |
| — | 无障碍人工验收 | 未执行 |

---

## 7. 已知风险与缺陷

- 大 PDF/多页 PDF 导出可能占用大量内存；`pw.Document` 一次性保存。
- PDF 导入一次最多 500 页，120 dpi PNG 会显著增大 `.meowo`；未做资产压缩/按需渲染。
- EPUB 依赖桌面 Chrome 与 Python；不同 Chrome 版本可能产生分页差异。
- `flutter_markdown` 已停止维护，后续应迁移到维护中的渲染器或自研块渲染。
- 文档 JSON 保存是整包写入；20k 笔迹/500 页时会明显变慢。
- 画布只做适配缩放，没有自由缩放/平移；无极画布实际是单个大页面。
- 整笔橡皮会一次删除整条笔迹，不是像素擦除。
- 附件在 Android 上不能用系统应用打开；桌面使用 `xdg-open`/`start`。
- 没有文件锁，两个实例同时编辑有覆盖风险；不要在多实例下使用同一文档。
- 没有自动崩溃恢复；关闭前请确认保存状态为“已保存”。
- `workspace.sqlite` 与 `.meowo` 的 JSON payload 是 pre-1.0，未来升级必须迁移。

---

## 8. 运行方式

Linux：

```bash
cd apps/meowo
./build/linux/x64/release/bundle/meowo
```

若从源码重新构建：

```bash
export PATH="$PWD/.tools/flutter/bin:$PATH"
cmake -S packages/meowo_core/native -B packages/meowo_core/native/build -G Ninja
cmake --build packages/meowo_core/native/build -j2
cd apps/meowo
flutter build linux --release
```

Android：

```bash
adb install -r dist/meowo-1.0.0-alpha.1-android-arm64.apk
```

资料库默认位于 `path_provider` 的应用支持目录下（Linux 通常为 `~/.local/share/app.meowo/library` 或类似路径）。

---

## 9. 下一步

1. 负责人补充 Q-140b 设备信息并完成真实笔验收。
2. 关闭 OQ-011：接入 MuPDF，删除 Poppler/Chrome 过渡路径或将其降级为回退。
3. 冻结 `.meowo` 格式并补迁移/损坏恢复/文件锁。
4. 按 P0 清单补套索、像素擦除、压力曲线、PDF 文本搜索与权限。
5. 做 Windows 构建与 Android 真机验收。
6. 再做发布工程：签名、安装包、许可证、隐私说明、发布说明。
