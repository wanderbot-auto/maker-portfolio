# CLI Development Checklist

面向 `maker` 命令行的开发清单，按推荐命令树拆分为三个优先级层级。

## P0 - 已在本轮实现

### Project
- [x] `maker project show <project-id>`
- [x] `maker project update <project-id> [--name] [--description] [--status] [--priority]`
- [x] `maker project archive <project-id>`
- [x] `maker project unarchive <project-id> [--status]`
- [x] `maker project rescan <project-id>`

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

### Note / Paths
- [x] `maker note get <project-id>`
- [x] `maker note set <project-id> <content>`
- [x] `maker paths show`

## P1 - 下一批建议优先实现

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

## P2 - 工具化增强

- [x] 关键命令统一支持 `--json`
- [x] 稳定退出码规范
- [ ] shell completion
- [ ] 批量导入 / 导出
- [ ] 面向 daemon 与 runtime 的集成测试
