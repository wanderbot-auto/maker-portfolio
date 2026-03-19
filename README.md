# Maker Portfolio

一个面向 macOS 的本地开发控制核心，聚焦于个人项目管理、运行编排、元数据沉淀，以及后续桌面应用接入前的核心能力验证。

## 当前状态

当前仓库已经不是单纯的架构骨架，而是一个可运行的 `Swift-only` Core：

- `Swift Package Manager` 多模块结构已经稳定
- 领域模型已覆盖项目、运行配置、环境集、运行会话、里程碑、备注
- 默认组合根已接入 `SQLite` 仓储、数据库迁移、日志存储与 secrets 存储
- 已实现本地项目扫描与基础运行配置自动发现
- 已实现本地进程运行适配、会话状态记录、日志 tail/follow
- 已提供本地 daemon、TCP JSON 控制协议与 `launchd` 托管
- CLI 已覆盖项目、环境、运行、诊断、里程碑、备注与路径查询
- 已有 domain/application/infrastructure/cli 多层测试

当前仍未包含桌面 UI；仓库定位仍然是“先把 Core 做稳，再接 SwiftUI 壳”。

## 已实现能力

### Core 能力

- 项目增删查改、归档/恢复、重新扫描
- 项目批量导入、列表筛选、删除
- 环境集创建、读取、复制、删除、变量增删
- 运行配置管理：命令、参数、工作目录、依赖、健康检查、自动重启
- 运行会话管理：启动、停止、重启、状态查询、活动会话、历史记录、脏会话 reconcile
- 运行依赖编排、健康检查等待、失败后自动重启
- 里程碑与项目备注管理

### Infrastructure 能力

- `SQLite` 持久化与 schema migration
- 基于文件主密钥的加密 secrets 存储
- 日志文件存储与按行读取
- 本地项目扫描与运行 profile 自动发现
- 本地 daemon 与 JSON 协议
- macOS `launchd` `LaunchAgent` 安装、启动、停止、卸载、状态检测

### CLI 能力

- `project`：新增、批量导入、列表筛选、详情、更新、归档、恢复、重扫、删除
- `env`：列表、设置、读取、取消变量、删除、复制
- `runtime`：提供 `profile` / `session` 两层命令，并保留兼容别名
- `runtime profile`：详情、新增、更新、删除、环境挂载、依赖管理、健康检查、自动重启
- `runtime session`：启动、列表、停止、重启、状态、详情、活动会话、历史、reconcile、日志
- `doctor` / `diag`：路径、数据库、daemon、运行会话诊断
- `metadata`：`milestone`、`note`、`paths`
- `daemon`：install、start、status、stop、uninstall、run
- tooling baseline：关键查询与诊断命令支持 `--json`，并提供稳定退出码

更细的 CLI 完成状态见 [docs/CLI_DEVELOPMENT_CHECKLIST.md](docs/CLI_DEVELOPMENT_CHECKLIST.md)。

## 模块结构

```text
Sources/
├── MakerDomain/          # 领域模型与枚举
├── MakerApplication/     # 用例、查询模型、仓储/服务协议
├── MakerSupport/         # 通用错误与日志事件
├── MakerAdapters/        # 运行适配器协议与本地进程实现
├── MakerInfrastructure/  # SQLite、扫描、secrets、daemon、组合根
└── MakerCLI/             # 命令行入口与集成验证壳
```

对应测试目录：

```text
Tests/
├── MakerDomainTests/
├── MakerApplicationTests/
├── MakerAdaptersTests/
├── MakerInfrastructureTests/
└── MakerCLITests/
```

## 依赖关系

当前实际依赖关系以 `Package.swift` 为准：

```text
MakerCLI
  -> MakerDomain
  -> MakerApplication
  -> MakerInfrastructure
  -> MakerSupport
  -> MakerAdapters

MakerInfrastructure
  -> MakerDomain
  -> MakerApplication
  -> MakerSupport
  -> MakerAdapters

MakerApplication
  -> MakerDomain
  -> MakerSupport

MakerAdapters
  -> MakerDomain
  -> MakerSupport
```

约束目标：

- `MakerDomain` 只保留纯模型和规则
- `MakerApplication` 负责编排 use case，不直接依赖系统实现
- `MakerInfrastructure` 承担持久化、扫描、daemon、日志与系统交互
- `MakerAdapters` 承担 runtime 执行抽象
- `MakerCLI` 作为当前唯一可执行入口，用于验证数据流与运行流

## 本地开发

### 构建与测试

```bash
swift build
swift test
```

### 查看 CLI 帮助

```bash
./.build/debug/maker help
```

或直接：

```bash
swift run maker help
```

### 常用命令

```bash
./.build/debug/maker project list --status active --tag imported
./.build/debug/maker project import ~/Code --recursive --tag imported
./.build/debug/maker runtime profile list <project-id>
./.build/debug/maker runtime session list --limit 20
./.build/debug/maker doctor
./.build/debug/maker diag paths
./.build/debug/maker daemon install
./.build/debug/maker daemon start
./.build/debug/maker daemon status
./.build/debug/maker paths show
```

### JSON 输出示例

```bash
./.build/debug/maker doctor --json
./.build/debug/maker runtime session list --limit 20 --json
```

## 本地数据与运行目录

默认路径可通过 `maker paths show` 查看，核心文件包括：

- `Application Support/MakerPortfolio/maker.sqlite`
- `Application Support/MakerPortfolio/Logs/`
- `Application Support/MakerPortfolio/master.key`
- `Application Support/MakerPortfolio/daemon.token`
- `~/Library/LaunchAgents/com.makerportfolio.daemon.plist`

测试或隔离环境下也可以通过环境变量覆盖：

- `MAKER_APP_SUPPORT_DIR`
- `MAKER_LAUNCH_AGENTS_DIR`

## 已知空缺

当前仍未完成的增强项主要包括：

- shell completion
- 批量导出
- 更多 daemon / runtime 端到端集成测试
- SwiftUI 桌面壳

## Roadmap

路线图请见 [docs/ROADMAP.md](docs/ROADMAP.md)。
