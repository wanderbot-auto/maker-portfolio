# CLI Development Checklist

面向 `maker` 命令行的开发清单。本文档现在按“已完成 / 未完成”维护，避免与当前代码状态脱节。

说明：

- `[x]` 表示命令或能力已经落地，并已体现在当前 CLI 中
- `[ ]` 表示尚未落地，或只有局部基础能力，未达到 checklist 目标

## 已完成

### Project

- [x] `maker project import <root-path> [--recursive] [--tag] [--status] [--priority]`
- [x] `maker project list [--status] [--tag] [--query]`
- [x] `maker project show <project-id>`
- [x] `maker project update <project-id> [--name] [--description] [--status] [--priority]`
- [x] `maker project archive <project-id>`
- [x] `maker project unarchive <project-id> [--status]`
- [x] `maker project rescan <project-id>`
- [x] `maker project delete <project-id>`

### Env

- [x] `maker env list <project-id>`
- [x] `maker env unset <project-id> <env-name> KEY [KEY ...]`
- [x] `maker env delete <project-id> <env-name>`
- [x] `maker env copy <project-id> <source-env-name> <target-env-name>`

### Runtime

- [x] 引入 `runtime profile` / `runtime session` 命令分层
- [x] 保留现有 `runtime list/start/stop/...` 兼容别名
- [x] `maker runtime profile show <profile-id>`
- [x] `maker runtime profile add <project-id> --name --cmd [--cwd] [--arg]`
- [x] `maker runtime profile update <profile-id> [--name] [--cmd] [--cwd] [--arg]`
- [x] `maker runtime profile delete <profile-id>`
- [x] `maker runtime session show <session-id>`

### Diagnostics

- [x] `maker doctor`
- [x] `maker diag daemon`
- [x] `maker diag db`
- [x] `maker diag paths`
- [x] `maker diag sessions`

### Runtime orchestration

- [x] `runtime profile env attach/detach`
- [x] `runtime profile deps add/remove`
- [x] `runtime profile health set`
- [x] `runtime profile auto-restart on/off`
- [x] `runtime session list [--project] [--status] [--limit]`

### Metadata

- [x] `maker milestone list <project-id>`
- [x] `maker milestone add <project-id> <title> [--due]`
- [x] `maker milestone state <milestone-id> <state>`
- [x] `maker milestone edit <milestone-id> [--title] [--due]`
- [x] `maker milestone remove <milestone-id>`
- [x] `maker note get <project-id>`
- [x] `maker note set <project-id> <content>`
- [x] `maker paths show`

### Tooling baseline

- [x] 关键命令统一支持 `--json`
- [x] 稳定退出码规范

## 未完成

### Tooling enhancement

- [ ] shell completion
- [ ] 批量导入 / 导出

### Testing

- [x] 面向 daemon 与 runtime 的基础集成测试

说明：当前已具备 CLI JSON contract、SQLite contract、launchd manager、log store、应用层用例，以及基础 daemon/runtime 端到端集成测试；如果后续引入更多编排策略，仍建议继续补齐更复杂的恢复与异常路径测试。
