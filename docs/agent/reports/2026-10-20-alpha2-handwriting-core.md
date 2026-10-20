# 2026-10-20 · Alpha.2 手写核心补齐报告

- 状态：`Completed / Alpha.2`
- 版本：`1.0.0-alpha.2`
- 日期：2026-10-20
- 关联计划：`docs/agent/plans/handwriting-core-completion.md`
- 关联需求：INK-001..012、SEL-001..012、Q-049..Q-070
- 结论：**像素擦除、压感曲线、套索/矩形选择及移动/缩放/删除/复制粘贴已落地，并通过自动化测试。不是完整 1.0；旋转、跨文档粘贴和真实手写笔验收仍未完成。**

## 1. 交付物

| 交付物 | 路径 | 证据 |
|---|---|---|
| Linux release | `dist/meowo-1.0.0-alpha.2-linux-x64.tar.gz` | 解压运行 `bundle/meowo`，8 秒无崩溃 |
| Android release APK | `dist/meowo-1.0.0-alpha.2-android-arm64.apk` | arm64-v8a，22.7 MB，debug 签名 |
| 手写核心代码 | `apps/meowo/lib/ink_ops.dart`、`pressure_curve_dialog.dart`、`canvas_view.dart`、`editor_page.dart` | `flutter analyze` 无问题 |
| 测试 | `apps/meowo/test/ink_ops_test.dart`、`selection_test.dart` | 新增 9 项，Dart 共 16 项通过 |

SHA-256：

```text
fc4236ad0bcc0299b47c815bf60785d572dfd623b526c6108576dbfd6579e748  meowo-1.0.0-alpha.2-android-arm64.apk
8428347663abc23a65203667026943931bb7fda82ae4aa53c0678fdbc76e5263  meowo-1.0.0-alpha.2-linux-x64.tar.gz
```

完整校验见 `dist/SHA256SUMS`。APK 仍是 debug 签名，不能作为正式发布包。

## 2. 已实现

### 2.1 矢量像素擦除

- 点击/拖动橡皮时按圆半径检测笔迹线段，不是整笔删除。
- 被擦除区域把笔迹切分为连续段；保留颜色、宽度、透明度、highlighter、压力。
- 一次按下→抬起只生成一个撤销单元；撤销恢复原始笔迹。
- 模式菜单：像素擦除 / 整笔擦除；范围：当前图层 / 所有可见未锁定图层。
- 单笔切分超过 64 段时退化为整笔删除，避免碎片失控。

### 2.2 压感曲线

- 文档 JSON 增加 `brushSettings.pen.curve` 与 `brushSettings.highlighter.curve`。
- 曲线控制点 x 固定为 0、0.25、0.5、0.75、1，y 可拖动；端点 y 保持 0/1。
- 笔与荧光笔独立曲线；工具栏 `show_chart` 打开编辑器；支持重置、取消、应用。
- 屏幕渲染、PNG 导出、PDF 导出共用 `MeowoCanvasPainter`，曲线自动一致。
- 旧文档没有 `brushSettings` 时使用线性默认曲线。

### 2.3 套索/矩形选择

- 选择工具下空白拖动开始自由套索；顶部/选择条可切换矩形。
- 选择当前页所有 `visible && !locked` 图层中未锁定的对象（笔迹、文本、图片、附件）。
- 选择框四角手柄缩放，框内拖动移动。
- 选择条：复制、粘贴、删除、取消、套索/矩形切换。
- 复制到内部剪贴板；同页粘贴偏移 12pt，跨页粘贴保持坐标；新对象生成新 ID。
- 移动/缩放从手势开始时的快照重算，避免累积误差；一次手势一个 undo。
- 文本缩放会按面积平方根调整字号并 clamp；不是排版级缩放。
- 选中对象时禁用点按打开元素，避免与拖拽冲突。

## 3. 测试与验证

- `scripts/test_all.sh`：
  - CTest：6 个 gtest 用例通过（1 个 CTest target）。
  - `flutter analyze`：No issues。
  - Dart/Flutter：16 项全部通过。
- 新增纯函数测试：曲线插值/clamp、笔迹命中、像素切分、单点删除、包围盒/多边形、平移/缩放。
- 新增 Canvas 手势测试：矩形套索返回页面坐标、框内拖动返回位移、角手柄返回缩放后 bounds。
- Linux release 启动 8 秒无崩溃；日志仅 GTK cursor theme 警告。
- Android APK 构建成功；**未真机运行**。

## 4. 未完成 / 已知限制

- 自由旋转手柄未实现；选择框只做轴对齐移动/缩放。
- 跨文档复制粘贴未实现；内部剪贴板仅当前文档。
- 对象分组、对齐、分布、翻转未实现。
- 文本非等比缩放语义仍是近似；复杂 Markdown 布局可能变形。
- 选择命中用包围盒与多边形相交，不是笔迹逐点精确相交；密集重叠时可能多选。
- 像素擦除按 1.5pt 重采样切分，极长笔迹可能产生较多点；上限 64 段后退化为整笔删除。
- 真实手写笔的压感、掌拒、P95 延迟未验证。
- Android 仍未做真机/模拟器运行验证；Windows 未构建。
- 仍在每次重绘时重建 painter 且 `shouldRepaint` 恒为 true；大文档性能未验证。

## 5. 复现命令

```bash
cd /home/mide/local_playground/Meowo
./scripts/test_all.sh
./scripts/build_linux_app.sh release
./scripts/build_android_apk.sh
```

运行 Linux：

```bash
mkdir -p /tmp/meowo-alpha2
tar -xzf dist/meowo-1.0.0-alpha.2-linux-x64.tar.gz -C /tmp/meowo-alpha2
/tmp/meowo-alpha2/bundle/meowo
```

## 6. 记录

- 操作日志：`.meowo-agent/operation-log.md`（不受 Git 追踪）
- 后续优先：真实设备手写验收、旋转、跨文档粘贴、数据安全（文件锁/崩溃恢复）。
