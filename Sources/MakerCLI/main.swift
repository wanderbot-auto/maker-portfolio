import Foundation
import MakerApplication
import MakerDomain
import MakerInfrastructure

enum CLIError: LocalizedError {
    case usage(String)
    case invalidIdentifier(String)
    case invalidAssignment(String)
    case daemonUnavailable

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        case let .invalidIdentifier(value):
            return "无效的标识符: \(value)"
        case let .invalidAssignment(value):
            return "无效的环境变量格式: \(value)，应为 KEY=VALUE"
        case .daemonUnavailable:
            return "无法连接本地 daemon。"
        }
    }
}

@main
struct MakerCLI {
    static func main() async {
        do {
            let command = Array(CommandLine.arguments.dropFirst())
            try await run(command: command)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(command: [String]) async throws {
        guard let root = command.first else {
            printHelp()
            return
        }

        switch root {
        case "help", "--help", "-h":
            printHelp()
        case "project":
            let services = try CoreServices.makeDefault()
            try await runProjectCommand(Array(command.dropFirst()), services: services)
        case "env":
            let services = try CoreServices.makeDefault()
            try await runEnvCommand(Array(command.dropFirst()), services: services)
        case "runtime":
            try await runRuntimeCommand(Array(command.dropFirst()))
        case "daemon":
            try await runDaemonCommand(Array(command.dropFirst()))
        default:
            throw CLIError.usage("未知命令: \(root)\n\n\(helpText)")
        }
    }

    private static func runProjectCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 project 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "add":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project add <path> [--description 文本] [--tag 标签]")
            }

            let path = arguments[1]
            let description = value(for: "--description", in: arguments) ?? ""
            let tags = values(for: "--tag", in: arguments)
            let useCase = CreateProjectUseCase(
                projects: services.projects,
                scanner: services.scanner,
                runtimeProfiles: services.runtimeProfiles
            )
            let project = try await useCase.execute(path: path, description: description, tags: tags)
            let profiles = try await ListRuntimeProfilesUseCase(runtimeProfiles: services.runtimeProfiles).execute(projectID: project.id)

            print("已添加项目")
            print("ID: \(project.id.uuidString)")
            print("名称: \(project.name)")
            print("路径: \(project.localPath)")
            print("技术栈: \(project.stackSummary)")
            print("运行单元: \(profiles.count)")

        case "list":
            let useCase = ListProjectsUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                sessions: services.runSessions
            )
            let items = try await useCase.execute()
            if items.isEmpty {
                print("暂无项目。")
                return
            }

            for item in items {
                let latestStatus = item.latestSession?.status.rawValue ?? "none"
                print("[\(item.project.id.uuidString)] \(item.project.name)")
                print("  状态: \(item.project.status.rawValue)  优先级: \(item.project.priority.rawValue)")
                print("  标签: \(item.project.tags.joined(separator: ", "))")
                print("  路径: \(item.project.localPath)")
                print("  运行单元: \(item.runtimeCount)  最近会话: \(latestStatus)")
            }

        default:
            throw CLIError.usage("未知 project 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runEnvCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 env 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "set":
            guard arguments.count >= 4 else {
                throw CLIError.usage("用法: maker env set <project-id> <env-name> KEY=VALUE [KEY=VALUE ...]")
            }

            let projectID = try parseUUID(arguments[1])
            let envName = arguments[2]
            let assignments = try parseAssignments(Array(arguments.dropFirst(3)))
            let useCase = UpsertEnvSetUseCase(envSets: services.envSets, secrets: services.secrets)
            let envSet = try await useCase.execute(projectID: projectID, name: envName, variables: assignments, encrypted: true)

            print("已保存环境集")
            print("ID: \(envSet.id.uuidString)")
            print("名称: \(envSet.name)")
            print("变量数: \(assignments.count)")

        case "get":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker env get <project-id> <env-name> [--reveal]")
            }

            let projectID = try parseUUID(arguments[1])
            let envName = arguments[2]
            let reveal = arguments.contains("--reveal")
            let useCase = LoadEnvSetUseCase(envSets: services.envSets, secrets: services.secrets)

            guard let snapshot = try await useCase.execute(projectID: projectID, name: envName) else {
                print("未找到环境集。")
                return
            }

            print("环境集: \(snapshot.envSet.name)")
            print("加密: \(snapshot.envSet.isEncrypted ? "yes" : "no")")
            if snapshot.resolvedVariables.isEmpty {
                print("变量: 0")
                return
            }

            for key in snapshot.resolvedVariables.keys.sorted() {
                let value = snapshot.resolvedVariables[key] ?? ""
                let rendered = reveal ? value : String(repeating: "*", count: max(4, min(value.count, 12)))
                print("\(key)=\(rendered)")
            }

        default:
            throw CLIError.usage("未知 env 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeCommand(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "list":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime list <project-id>")
            }

            let services = try CoreServices.makeDefault()
            let projectID = try parseUUID(arguments[1])
            let profiles = try await ListRuntimeProfilesUseCase(runtimeProfiles: services.runtimeProfiles).execute(projectID: projectID)
            if profiles.isEmpty {
                print("该项目暂无运行单元。")
                return
            }

            for profile in profiles {
                let args = profile.args.joined(separator: " ")
                print("[\(profile.id.uuidString)] \(profile.name)")
                print("  命令: \(profile.entryCommand) \(args)")
                print("  工作目录: \(profile.workingDir)")
                print("  适配器: \(profile.adapterType.rawValue)")
            }

        case "start":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker runtime start <project-id> <profile-id>")
            }
            let projectID = try parseUUID(arguments[1])
            let profileID = try parseUUID(arguments[2])
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.start",
                    projectID: projectID.uuidString,
                    runtimeProfileID: profileID.uuidString
                )
            )
            try printDaemonResponse(response)

        case "stop":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime stop <session-id>")
            }
            let sessionID = try parseUUID(arguments[1])
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.stop",
                    sessionID: sessionID.uuidString
                )
            )
            try printDaemonResponse(response)

        case "restart":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime restart <session-id>")
            }
            let sessionID = try parseUUID(arguments[1])
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.restart",
                    sessionID: sessionID.uuidString
                )
            )
            try printDaemonResponse(response)

        case "status":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime status <session-id>")
            }
            let sessionID = try parseUUID(arguments[1])
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.status",
                    sessionID: sessionID.uuidString
                )
            )
            try printDaemonResponse(response)

        case "active":
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.active"
                )
            )
            try printDaemonResponse(response)

        case "history":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime history <project-id> [--limit N]")
            }
            let projectID = try parseUUID(arguments[1])
            let limit = Int(value(for: "--limit", in: arguments) ?? "20") ?? 20
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.history",
                    projectID: projectID.uuidString,
                    tail: limit
                )
            )
            try printDaemonResponse(response)

        case "reconcile":
            let projectID = arguments.dropFirst().first.flatMap(UUID.init(uuidString:))
            if arguments.count > 1, projectID == nil {
                throw CLIError.usage("用法: maker runtime reconcile [project-id]")
            }
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.reconcile",
                    projectID: projectID?.uuidString
                )
            )
            try printDaemonResponse(response)

        case "logs":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime logs <session-id> [--tail N] [--follow]")
            }
            let sessionID = try parseUUID(arguments[1])
            let tail = Int(value(for: "--tail", in: arguments) ?? "50") ?? 50
            let follow = arguments.contains("--follow")
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.logs",
                    sessionID: sessionID.uuidString,
                    tail: tail
                )
            )
            if follow {
                try await followLogs(initialResponse: response, sessionID: sessionID, tail: tail, client: client)
            } else {
                try printDaemonResponse(response)
            }

        default:
            throw CLIError.usage("未知 runtime 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runDaemonCommand(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 daemon 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "run":
            let services = try CoreServices.makeDefault()
            let token = try daemonTokenStore().loadOrCreateToken()
            let server = RuntimeDaemonServer(services: services, authToken: token)
            try server.run()

        case "start":
            let manager = try launchdManager()
            try manager.start(executableURL: try currentExecutableURL())
            _ = try await ensureDaemonRunning()
            print("daemon 已通过 launchd 启动")

        case "install":
            let manager = try launchdManager()
            try manager.install(executableURL: try currentExecutableURL())
            print("launchd agent 已安装")
            print("plist: \(manager.paths.daemonLaunchAgentURL.path)")

        case "status":
            let manager = try launchdManager()
            let launchdStatus = try manager.status()
            let token = try daemonTokenStore().loadOrCreateToken()
            let client = DaemonClient()
            let responding = (try? await ping(client: client, token: token)) ?? false

            if responding {
                print("daemon 运行中")
                print("launchd: loaded")
                return
            }

            if launchdStatus.loaded {
                print("daemon 未响应，但 launchd 已加载")
                if !launchdStatus.details.isEmpty {
                    print(launchdStatus.details)
                }
                return
            }

            if launchdStatus.installed {
                print("daemon 已安装，但 launchd 未加载")
                if !launchdStatus.details.isEmpty {
                    print(launchdStatus.details)
                }
                return
            }

            print("daemon 未安装")

        case "stop":
            let manager = try launchdManager()
            try manager.stop()

            let client = DaemonClient()
            let token = try daemonTokenStore().loadOrCreateToken()
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(100))
                if try await !ping(client: client, token: token) {
                    print("daemon 已停止")
                    return
                }
            }
            print("daemon 正在停止")

        case "uninstall":
            let manager = try launchdManager()
            try manager.uninstall()
            print("launchd agent 已卸载")

        default:
            throw CLIError.usage("未知 daemon 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func ensureDaemonRunning() async throws -> DaemonClient {
        let tokenStore = try daemonTokenStore()
        let token = try tokenStore.loadOrCreateToken()
        let client = DaemonClient()

        if try await ping(client: client, token: token) {
            return client
        }

        let manager = try launchdManager()
        try manager.start(executableURL: try currentExecutableURL())
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(150))
            if try await ping(client: client, token: token) {
                return client
            }
        }

        throw CLIError.daemonUnavailable
    }

    private static func ping(client: DaemonClient, token: String) async throws -> Bool {
        do {
            let response = try await client.send(DaemonRequest(token: token, action: "ping"))
            return response.ok
        } catch {
            return false
        }
    }

    private static func currentExecutableURL() throws -> URL {
        let executablePath = CommandLine.arguments[0]
        return URL(
            fileURLWithPath: executablePath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
    }

    private static func launchdManager() throws -> LaunchdDaemonManager {
        let paths = AppPaths()
        try paths.createIfNeeded()
        return LaunchdDaemonManager(paths: paths)
    }

    private static func daemonTokenStore() throws -> FileSystemDaemonTokenStore {
        let paths = AppPaths()
        try paths.createIfNeeded()
        return FileSystemDaemonTokenStore(tokenURL: paths.daemonTokenURL)
    }

    private static func printDaemonResponse(_ response: DaemonResponse) throws {
        guard response.ok else {
            throw CLIError.usage(response.message)
        }

        if !response.logs.isEmpty {
            if let session = response.session {
                print("会话: \(session.sessionID)")
                print("状态: \(session.status)")
                if let pid = session.pid {
                    print("PID: \(pid)")
                }
            }
            print("---- recent logs ----")
            for line in response.logs {
                print(line)
            }
            return
        }

        if let session = response.session {
            print("会话: \(session.sessionID)")
            print("项目: \(session.projectID)")
            print("运行单元: \(session.runtimeProfileID)")
            print("状态: \(session.status)")
            if let pid = session.pid {
                print("PID: \(pid)")
            }
            return
        }

        if !response.sessions.isEmpty {
            for session in response.sessions {
                print("[\(session.sessionID)] \(session.status)  profile=\(session.runtimeProfileID) pid=\(session.pid.map(String.init) ?? "-")")
            }
            return
        }

        print(response.message)
    }

    private static func followLogs(
        initialResponse: DaemonResponse,
        sessionID: UUID,
        tail: Int,
        client: DaemonClient
    ) async throws {
        try printDaemonResponse(initialResponse)
        var nextLine = initialResponse.nextLine ?? initialResponse.logs.count
        var terminalSeenWithoutNewLogs = false
        var currentStatus = initialResponse.session?.status
        let token = try daemonTokenStore().loadOrCreateToken()

        while true {
            if isTerminal(currentStatus), terminalSeenWithoutNewLogs {
                return
            }

            try await Task.sleep(for: .milliseconds(500))

            let response = try await client.send(
                DaemonRequest(
                    token: token,
                    action: "runtime.logs",
                    sessionID: sessionID.uuidString,
                    tail: tail,
                    afterLine: nextLine
                )
            )
            guard response.ok else {
                throw CLIError.usage(response.message)
            }

            if !response.logs.isEmpty {
                for line in response.logs {
                    print(line)
                }
                terminalSeenWithoutNewLogs = false
            } else {
                terminalSeenWithoutNewLogs = isTerminal(response.session?.status)
            }
            currentStatus = response.session?.status
            nextLine = response.nextLine ?? nextLine
        }
    }

    private static func isTerminal(_ status: String?) -> Bool {
        switch status {
        case "stopped", "failed":
            return true
        default:
            return false
        }
    }

    private static func parseUUID(_ rawValue: String) throws -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw CLIError.invalidIdentifier(rawValue)
        }
        return uuid
    }

    private static func parseAssignments(_ rawValues: [String]) throws -> [String: String] {
        var values: [String: String] = [:]
        for rawValue in rawValues {
            let pieces = rawValue.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2, !pieces[0].isEmpty else {
                throw CLIError.invalidAssignment(rawValue)
            }
            values[pieces[0]] = pieces[1]
        }
        return values
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func values(for flag: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, value in
            guard value == flag, arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }

    private static func printHelp() {
        print(helpText)
    }
}

private let helpText = """
Maker CLI

用法:
  maker project add <path> [--description 文本] [--tag 标签]
  maker project list
  maker env set <project-id> <env-name> KEY=VALUE [KEY=VALUE ...]
  maker env get <project-id> <env-name> [--reveal]
  maker runtime list <project-id>
  maker runtime start <project-id> <profile-id>
  maker runtime stop <session-id>
  maker runtime restart <session-id>
  maker runtime status <session-id>
  maker runtime active
  maker runtime history <project-id> [--limit N]
  maker runtime reconcile [project-id]
  maker runtime logs <session-id> [--tail N] [--follow]
  maker daemon install|start|status|stop|uninstall|run
"""
