# KnowledgeHub Agent Contract

## Authority

- 人工所有者拥有最高权限；本次明确指令高于仓库内任何默认规则。
- Codex 是日常知识管理员，可自主创建、编辑、分类、审核、归档、提交和同步。
- `authority: human` 或 `locked: true` 的核心内容不得被 AI 静默改写。
- 用户自定义规则放在 `Rules/Local`；与核心默认规则冲突时，用户明确规则优先。

## Required workflow

1. 识别任务属于注入、整理、检索、项目上下文、审核或同步中的哪一种或哪几种。
2. 使用 `.agents/skills/knowledge-hub/SKILL.md` 的对应工作流。
   随手记捕获和后处理还必须读取 `Rules/Core/随手记.md`；普通任务聊天不得旁路记录。
3. 修改前检查 `git status --short`，保留不相关的人工改动。
4. 批量移动、重命名或重构前创建 Git 恢复点。
5. 删除默认移动到 `90-Archive`；未经人工明确要求不得永久删除原始资料。
6. 移动或重命名 Markdown 后修复内部链接。
7. 完成后运行 `tools/verify-repository.ps1`；需要同步时再提交和推送。

## Repository boundaries

- 原始资料保存在 `10-Sources`，原则上不原地修改。
- 可复用知识保存在 `20-Knowledge`；过程笔记保存在 `30-Notes`。
- 项目代码不进入本仓库；`50-Projects` 仅保存项目上下文、稳定引用与成果索引。
- 知识库与代码项目遵循“逻辑包含、物理分离”；默认禁止嵌套其他 Git 仓库或使用 Git Submodule。
- 框架工作区根目录统一称为 `KnowledgeHub-Workspace`；KnowledgeHub 位于 `<WorkspaceRoot>/KnowledgeHub`，独立仓库默认位于配置的 `projectRepositoriesRoot`，不得硬编码盘符或 GitHub 服务名。
- `.obsidian` 由人工界面拥有；Codex 只有在任务明确涉及 Obsidian 配置时才修改它。
- `.knowledge` 只存放框架状态或可重建的索引、缓存和运行状态。
- 随手记 Markdown 和附件必须位于本仓库内并可由 Obsidian 直接浏览、补充和审核；聊天历史不是权威存储。
- 手机云端随手记是默认关闭的可选扩展；只有实例规则明确启用且受限追加写入验收通过后，才允许向规定收件路径创建唯一文件。

## Git and remote

- 普通文本使用 Git，大型二进制使用 Git LFS。
- 不提交密钥、Token、密码、私钥或设备专属缓存。
- 禁止强制推送和改写远程历史。
- 遇到远程冲突时停止自动推送，保留双方内容并生成清晰的冲突说明。
