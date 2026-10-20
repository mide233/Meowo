# 主页多选与清空回收站

- 日期：2026-10-20
- 状态：已实现
- 范围：资料库主页多选、批量操作、清空回收站

## 1. 交互

- 卡片长按进入多选；顶部“多选”按钮也可进入。
- 多选态下卡片显示复选框，点击卡片切换选中；显示“已选 N 项”、全选、取消。
- 普通筛选：批量收藏/取消收藏、移动到文件夹、移到回收站。
- 回收站筛选：批量恢复、永久删除；筛选栏提供“清空回收站”。
- 切换筛选、文件夹或搜索内容时自动退出多选；批量操作完成后清空选择。

## 2. 核心与状态

- `bulk_document_action`：单事务处理 favorite/unfavorite/trash/restore/move。
- `bulk_purge_documents`：删除选中文档文件与目录记录。
- `empty_trash`：删除所有 `deleted_at IS NOT NULL` 的文档并返回 ids。
- `AppState` 新增 `bulkFavorite`、`bulkTrash`、`bulkRestore`、`bulkMove`、`bulkPurge`、`emptyTrash`；批量移入回收站/永久删除会同步关闭对应标签并清理当前文档。

## 3. 验证

- `flutter analyze`：无问题。
- `flutter test`：95/95 通过。
- CTest：1/1 通过（含新增 `BulkDocumentActionsAndEmptyTrash`）。
- Linux release 未因本次 UI 改动重新打包；Android arm64 仍受仓库内 MuPDF arm64 静态库缺失限制。

## 4. 限制

- 多选范围仅当前列表（受搜索、筛选和文件夹影响），不跨筛选累积。
- 批量操作一次调用一个事务；超大选择集仍建议分批操作。
