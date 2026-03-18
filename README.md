# Maker Portfolio

一个面向 macOS 的本地开发控制核心，目标是管理个人项目、沉淀项目元数据，并为后续运行编排和桌面应用打基础。

## 当前状态

当前仓库已经初始化为一套 `Swift-only` 架构骨架，优先实现后端抽象层，不包含前端或桌面 UI。

已落地内容：

- `Swift Package Manager` 多模块结构
- 领域模型：项目、运行配置、环境集、运行会话、里程碑、备注
- 应用协议：仓储、扫描器、密钥存储、运行管理器
- 运行适配层：`RuntimeAdapter` 与 `LocalProcessAdapter`
- 基础设施：SQLite、加密 secrets、文件系统项目扫描、日志文件存储、组合根
- 本地 daemon：TCP JSON 控制协议、运行日志 tail/follow、历史重启、脏会话 reconcile
- macOS `launchd` 集成：`LaunchAgent` plist 生成、bootstrap/kickstart/bootout、CLI 托管启动
- `CLI` 入口，用于集成验证
- 基础测试，可通过 `swift test`

## 模块结构

```text
Sources/
├── MakerDomain/          # 领域模型与枚举
├── MakerApplication/     # 用例协议、查询模型、服务边界
├── MakerSupport/         # 通用错误与日志事件
├── MakerAdapters/        # 运行适配器协议与本地进程实现
├── MakerInfrastructure/  # 扫描、存储、组合根、运行管理器
└── MakerCLI/             # 调试与集成入口
```

## Roadmap

详细路线图见 [docs/ROADMAP.md](/Users/wander/Documents/code/apps/maker-portfolio/docs/ROADMAP.md)。

下一阶段建议按顺序推进：

1. 将内存仓储替换为 SQLite 实现
2. 引入真正的密钥管理与加密存储
3. 完善运行会话日志和状态追踪
4. 扩展 CLI 命令，作为桌面应用前的验证壳
5. 在 Core 稳定后接入 macOS `SwiftUI` 桌面壳

## 本地开发

```bash
swift test
swift run maker
swift run maker daemon install
swift run maker daemon start
swift run maker daemon status
```

`maker-portfolio` 是一个面向个人多项目管理的 macOS-first Swift 工程，首阶段先落地后端抽象层与命令行入口，后续再接 SwiftUI 桌面壳。

## 当前定位

- 先做 `Swift-only` 的核心工程结构
- 先稳住领域模型、运行抽象、持久化和命令行入口
- 桌面 UI 暂缓，等核心能力稳定后再接入

## 工程结构

本仓库按 Swift Package Manager 组织，核心模块如下：

- `MakerDomain`：领域模型与基础规则
- `MakerApplication`：用例编排与应用服务协议
- `MakerInfrastructure`：SQLite、Keychain、文件系统等基础设施实现
- `MakerAdapters`：运行器抽象与本地进程适配器
- `MakerSupport`：通用工具、错误类型、日志与辅助能力
- `MakerCLI`：命令行入口，用于验证核心流程
- `Tests/*Tests`：各模块对应的单元测试

推荐依赖方向：

```text
MakerCLI
  -> MakerApplication
  -> MakerInfrastructure
  -> MakerAdapters
  -> MakerSupport

MakerInfrastructure
  -> MakerApplication
  -> MakerDomain

MakerApplication
  -> MakerDomain
  -> MakerSupport

MakerAdapters
  -> MakerDomain
  -> MakerSupport
```

## 架构目标

- `MakerDomain` 只保留纯模型和规则，不依赖系统实现
- `MakerApplication` 负责用例编排，不直接操作 SQLite 或 `Process`
- `MakerInfrastructure` 提供持久化和系统能力实现
- `MakerAdapters` 负责运行时执行抽象，首版只实现本地进程
- `MakerCLI` 作为首个可执行入口，先验证数据流和运行流

## 开发路线

### Phase 1

- 建立 Swift Package 骨架
- 定义领域模型与核心协议
- 提供 CLI 占位入口

### Phase 2

- 补齐 SQLite 持久化
- 接入项目扫描与元数据识别
- 补充环境变量与敏感信息存储

### Phase 3

- 接入本地进程编排
- 实现启动、停止、重启与日志流
- 建立运行会话与状态记录

### Phase 4

- 增加健康检查与失败反馈
- 补充更完整的测试覆盖
- 为后续 SwiftUI 桌面壳预留组合层

## 约束

- 仅面向 macOS
- 仅使用 Swift
- 首版不引入 Web 技术栈
- 首版不接入外部平台同步
- 首版优先验证后端抽象和项目管理流程

## 备注

当前仓库仍处于基础骨架阶段，后续源码文件会按上述模块逐步补齐。
