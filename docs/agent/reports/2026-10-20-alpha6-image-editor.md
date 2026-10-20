# Meowo 1.0.0-alpha.6 — 非破坏性图片编辑器

- 日期：2026-10-20
- 状态：`Completed`（Alpha 验证完成；非正式发布）
- 分支：`dev-agent`
- 范围：图片元素裁剪、90° 旋转、水平/垂直翻转；画布与导出一致。

## 1. 交付内容

### 1.1 数据模型

图片元素新增非破坏性参数：

```text
cropLeft, cropTop, cropRight, cropBottom : 0..1
rotation : 0 | 90 | 180 | 270
flipH, flipV : bool
```

原始资产不修改。缺少参数时默认完整显示。

### 1.2 绘制

- `apps/meowo/lib/image_ops.dart`
  - `normalizeImageCrop`：默认值、边界限制、至少保留 5% 内容。
  - `normalizeImageRotation`：归一化到 0/90/180/270。
  - `paintImageElementContent`：按裁剪源矩形绘制，应用翻转和旋转。
- `canvas_view.dart` 的屏幕绘制、PNG 离屏导出和 PDF 导出共用同一绘制函数。

### 1.3 编辑界面

- `apps/meowo/lib/image_edit_dialog.dart`
  - 图片预览。
  - 左/右/上/下裁剪滑杆，显示百分比。
  - 左转/右转 90°、水平翻转、垂直翻转。
  - 重置、取消、应用。
- 点击画布上的图片元素打开编辑器；应用后通过全局撤销栈保存。

### 1.4 兼容性

- 旧文档没有图片参数时按完整图片显示。
- 编辑参数写入现有 JSON payload；格式仍为预发布 schema=1。

## 2. 验证

```text
C++ CTest:        1/1 test executable, 7/7 gtest cases passed
Flutter/Dart:     24/24 tests passed
flutter analyze:  No issues found
Linux release:    启动 8 秒无崩溃（仅 Gdk cursor theme 警告）
Android arm64:    release APK 构建成功（31.6 MB）
```

新增测试：

- `image_ops_test.dart`：默认裁剪、越界/最小面积、旋转归一化、翻转参数。
- 既有 `selection_test.dart`、`ink_test.dart`、`core_test.dart` 全部回归通过。

## 3. 产物

| 产物 | 大小 | SHA256 |
|---|---:|---|
| `dist/meowo-1.0.0-alpha.6-linux-x64.tar.gz` | 40 MB | `fc67d1c43ce7584c898edebffb6414317a6b9530b9ac280dd922a4e7ff842fa9` |
| `dist/meowo-1.0.0-alpha.6-android-arm64.apk` | 31 MB | `89c519c123ad777c9b178bc8c76fe4105689083d386c103c9d0728abbba24e76` |

- APK 为 debug 签名，不可用于商店或正式分发。
- 二进制被 Git 忽略；校验值记录在 `dist/SHA256SUMS`。

## 4. 已知限制

- 仅支持矩形裁剪、90° 步进旋转和轴向翻转；不支持自由旋转、透视、滤镜。
- 图片元素框不随旋转自动换宽高；旋转内容在框内变换。
- 预览为近似预览，最终以画布/导出结果为准。
- Android arm64 未做真机运行验证；x86_64 模拟器已验证 PDF/EPUB 导入链路。
- 真实手写笔/触屏下打开编辑器、拖动滑杆尚未人工验收。
- MuPDF AGPL 合规、文件格式冻结、崩溃恢复仍未完成。

## 5. 手工确认项

1. 在 Android 平板上导入 PNG/JPEG/WebP 图片，验证裁剪、旋转、翻转和保存。
2. 在 Linux/Windows 触屏笔设备上验证点击图片、滑杆拖动和撤销。
3. 验证裁剪后的 PNG/PDF 导出与画布显示一致。
4. 确认图片旋转后的选择框/缩放手感是否可接受。
5. 确认是否需要自由角度旋转（当前明确不做）。
