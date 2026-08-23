# `.knowledge`

此目录保存框架状态以及可重建的索引、缓存和运行状态。

- `framework-state.json`：由 `tools/setup.ps1` 或 `tools/update-framework.ps1` 生成，用于安全升级；公开发布前由维护者运行 `tools/refresh-framework-state.ps1` 刷新并做严格校验。
- `local-config.json`：记录当前设备的 `WorkspaceRoot`、KnowledgeHub 绝对路径和独立仓库根目录；默认不进入 Git。
- 其他缓存默认不进入 Git，不属于知识本体。
