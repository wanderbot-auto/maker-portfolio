# Maker Portfolio Roadmap

## Goal

Build a macOS-first local development control core in Swift. The project focuses on project metadata management, runtime orchestration, local persistence, diagnostics, and a future desktop shell.

## Principles

- Swift-only implementation across core modules
- Domain and application layers stay independent from system APIs
- Runtime execution flows through adapter abstractions
- Sensitive configuration is isolated from general persistence
- CLI-first validation before introducing a desktop UI

## 已完成

### Core foundation

- 建立 Swift Package 多模块边界与测试 target
- 形成 `MakerDomain` / `MakerApplication` / `MakerInfrastructure` / `MakerAdapters` / `MakerCLI` 分层
- 补齐项目、运行配置、环境集、运行会话、里程碑、备注等核心模型
- 建立应用层仓储协议、扫描器、secrets、runtime manager、log reader、process inspector 等服务边界

### Persistence and configuration

- 落地 `SQLite` 仓储：projects、runtime_profiles、env_sets、run_sessions、milestones、project_notes
- 加入 migration 与 app path 管理
- 增加 `env_set_secrets` 加密存储
- 实现基于文件主密钥的 secrets 加解密
- 实现文件系统项目扫描与基础运行 profile 自动发现

### Runtime execution

- 实现本地进程 runtime adapter
- 支持 runtime start / stop / restart / status
- 持久化运行会话生命周期与历史记录
- 支持日志落盘、tail、follow、after-line 读取
- 支持运行依赖、环境集挂载、健康检查配置、自动重启开关
- 支持脏运行会话诊断与 reconcile

### CLI and daemon harness

- CLI 已覆盖 project、env、runtime、milestone、note、paths、doctor、diag、daemon
- 关键查询/诊断命令支持 `--json`
- 提供 runtime profile / runtime session 分层命令，并保留兼容别名
- 增加本地 daemon 的 TCP JSON 控制协议
- 接入 macOS `launchd`：LaunchAgent 生成、install/start/status/stop/uninstall
- 增加 CLI JSON contract、SQLite contract、launchd manager、log store 等测试

## 进行中

### 稳定性与验证

- 持续补齐 runtime / daemon 相关测试覆盖
- 持续收敛 CLI 的错误语义、退出码与 JSON contract
- 持续完善诊断命令对本地运行环境的可观测性

### Runtime extensibility

- 领域模型已为 `androidEmulator`、`iosSimulator`、`macosVM` 预留 adapter type
- 当前只有 `localProcess` 真正落地，其他 adapter 仍是 future phase 占位

## 后续

### Tooling

- shell completion
- 批量导入 / 导出能力
- 更系统化的 fixture 与端到端集成测试

### Desktop shell

- 创建依赖 Core package 的 SwiftUI macOS 壳
- 添加 composition root、view model、事件订阅与状态桥接
- 保持 UI 轻量，所有状态变更经由应用层 use case

## Deferred

- Team collaboration and remote sync
- External service integrations
- Device simulator and VM controls beyond abstraction placeholders
- Multi-profile coordinated startup and orchestration policies
