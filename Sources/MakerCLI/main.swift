import Foundation
import MakerApplication
import MakerDomain
import MakerInfrastructure
import MakerSupport

enum CLIError: LocalizedError {
    case usage(String)
    case invalidIdentifier(String)
    case invalidAssignment(String)
    case invalidStatus(String)
    case invalidPriority(String)
    case invalidRunSessionStatus(String)
    case invalidHealthCheckType(String)
    case invalidMilestoneState(String)
    case invalidDate(String)
    case invalidToggle(String)
    case missingResource(String)
    case runtimeCommandFailed(String)
    case daemonUnavailable

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        case let .invalidIdentifier(value):
            return "无效的标识符: \(value)"
        case let .invalidAssignment(value):
            return "无效的环境变量格式: \(value)，应为 KEY=VALUE"
        case let .invalidStatus(value):
            return "无效的项目状态: \(value)"
        case let .invalidPriority(value):
            return "无效的项目优先级: \(value)"
        case let .invalidRunSessionStatus(value):
            return "无效的运行会话状态: \(value)"
        case let .invalidHealthCheckType(value):
            return "无效的健康检查类型: \(value)"
        case let .invalidMilestoneState(value):
            return "无效的里程碑状态: \(value)"
        case let .invalidDate(value):
            return "无效的日期: \(value)，应为 YYYY-MM-DD 或 ISO-8601"
        case let .invalidToggle(value):
            return "无效的开关值: \(value)，应为 on 或 off"
        case let .missingResource(message):
            return message
        case let .runtimeCommandFailed(message):
            return message
        case .daemonUnavailable:
            return "无法连接本地 daemon。"
        }
    }
}

private enum DiagnosticLevel: String, Codable {
    case ok
    case warning
    case failure

    var label: String {
        switch self {
        case .ok:
            return "OK"
        case .warning:
            return "WARN"
        case .failure:
            return "FAIL"
        }
    }
}

private enum OutputFormat {
    case text
    case json
}

private struct DiagnosticCheck: Codable {
    let name: String
    let level: DiagnosticLevel
    let detail: String
}

private struct CLIMessageResponse: Codable {
    let message: String
}

private struct CLIIdentifierResponse: Codable {
    let id: String
}

private struct CLIEnvelope<T: Encodable>: Encodable {
    let message: String
    let data: T
}

private struct PathsSnapshot: Codable {
    let applicationSupport: String
    let database: String
    let logs: String
    let masterKey: String
    let daemonToken: String
    let launchAgent: String
}

private struct DaemonStatusSnapshot: Codable {
    let installed: Bool
    let loaded: Bool
    let responding: Bool
    let serviceTarget: String
    let launchAgent: String
    let daemonToken: String
    let details: String
}

private struct DiagnosticSection: Codable {
    let title: String
    let checks: [DiagnosticCheck]
}

private struct DiagnosticSummary: Codable {
    let failures: Int
    let warnings: Int
}

private struct DiagnosticReport: Codable {
    let sections: [DiagnosticSection]
    let summary: DiagnosticSummary?
}

private struct CLIErrorResponse: Codable {
    let error: String
    let exitCode: Int32
}

private struct ProjectAddResult: Codable {
    let project: Project
    let runtimeProfiles: [RuntimeProfile]
}

private enum CLIExitCode: Int32 {
    case success = 0
    case generalFailure = 1
    case invalidUsage = 2
    case missingResource = 3
    case daemonUnavailable = 4
    case runtimeFailure = 5
    case environmentFailure = 6
}

@MainActor
@main
struct MakerCLI {
    private static var outputFormat: OutputFormat = .text

    static func main() async {
        let rawCommand = Array(CommandLine.arguments.dropFirst())
        outputFormat = rawCommand.contains("--json") ? .json : .text
        let command = rawCommand.filter { $0 != "--json" }

        do {
            try await run(command: command)
        } catch {
            renderError(error)
            exit(exitCode(for: error).rawValue)
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
        case "doctor":
            try await runDoctorCommand()
        case "diag":
            try await runDiagCommand(Array(command.dropFirst()))
        case "milestone":
            let services = try CoreServices.makeDefault()
            try await runMilestoneCommand(Array(command.dropFirst()), services: services)
        case "note":
            let services = try CoreServices.makeDefault()
            try await runNoteCommand(Array(command.dropFirst()), services: services)
        case "paths":
            try runPathsCommand(Array(command.dropFirst()))
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

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_added", data: ProjectAddResult(project: project, runtimeProfiles: profiles)))
                return
            }
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
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "projects_listed", data: items))
                return
            }
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

        case "show":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project show <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            guard let snapshot = try await GetProjectDetailUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                envSets: services.envSets,
                sessions: services.runSessions,
                milestones: services.milestones,
                notes: services.notes
            ).execute(projectID: projectID) else {
                throw CLIError.missingResource("未找到项目。")
            }
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_detail", data: snapshot))
                return
            }
            printProject(snapshot)

        case "update":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project update <project-id> [--name 名称] [--description 文本] [--status 状态] [--priority 优先级]")
            }

            let projectID = try parseUUID(arguments[1])
            let name = value(for: "--name", in: arguments)
            let description = value(for: "--description", in: arguments)
            let status = try value(for: "--status", in: arguments).map(parseProjectStatus)
            let priority = try value(for: "--priority", in: arguments).map(parseProjectPriority)
            guard name != nil || description != nil || status != nil || priority != nil else {
                throw CLIError.usage("project update 至少需要一个变更字段。")
            }

            let project = try await UpdateProjectUseCase(projects: services.projects).execute(
                projectID: projectID,
                name: name,
                description: description,
                status: status,
                priority: priority
            )
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_updated", data: project))
                return
            }
            print("已更新项目")
            print("ID: \(project.id.uuidString)")
            print("名称: \(project.name)")
            print("状态: \(project.status.rawValue)")
            print("优先级: \(project.priority.rawValue)")

        case "archive":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project archive <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            let project = try await ArchiveProjectUseCase(projects: services.projects).execute(projectID: projectID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_archived", data: project))
                return
            }
            print("已归档项目")
            print("ID: \(project.id.uuidString)")
            print("状态: \(project.status.rawValue)")

        case "unarchive":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project unarchive <project-id> [--status 状态]")
            }

            let projectID = try parseUUID(arguments[1])
            let restoredStatus = try value(for: "--status", in: arguments).map(parseProjectStatus) ?? .active
            let project = try await UnarchiveProjectUseCase(projects: services.projects).execute(
                projectID: projectID,
                restoredStatus: restoredStatus
            )
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_unarchived", data: project))
                return
            }
            print("已恢复项目")
            print("ID: \(project.id.uuidString)")
            print("状态: \(project.status.rawValue)")

        case "rescan":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker project rescan <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            let result = try await RescanProjectUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                scanner: services.scanner
            ).execute(projectID: projectID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "project_rescanned", data: result))
                return
            }
            print("已重新扫描项目")
            print("ID: \(result.project.id.uuidString)")
            print("仓库类型: \(result.project.repoType.rawValue)")
            print("技术栈: \(result.project.stackSummary)")
            print("新增运行单元: \(result.createdProfiles.count)")

        default:
            throw CLIError.usage("未知 project 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runEnvCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 env 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "list":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker env list <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            let snapshots = try await ListEnvSetsUseCase(envSets: services.envSets, secrets: services.secrets).execute(projectID: projectID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_sets_listed", data: snapshots))
                return
            }
            if snapshots.isEmpty {
                print("该项目暂无环境集。")
                return
            }

            for snapshot in snapshots {
                print("[\(snapshot.envSet.id.uuidString)] \(snapshot.envSet.name)")
                print("  加密: \(snapshot.envSet.isEncrypted ? "yes" : "no")  变量数: \(snapshot.resolvedVariables.count)")
            }

        case "set":
            guard arguments.count >= 4 else {
                throw CLIError.usage("用法: maker env set <project-id> <env-name> KEY=VALUE [KEY=VALUE ...]")
            }

            let projectID = try parseUUID(arguments[1])
            let envName = arguments[2]
            let assignments = try parseAssignments(Array(arguments.dropFirst(3)))
            let useCase = UpsertEnvSetUseCase(envSets: services.envSets, secrets: services.secrets)
            let envSet = try await useCase.execute(projectID: projectID, name: envName, variables: assignments, encrypted: true)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_set_saved", data: EnvSetSnapshot(envSet: envSet, resolvedVariables: assignments)))
                return
            }
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
                throw CLIError.missingResource("未找到环境集。")
            }

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_set_loaded", data: snapshot))
                return
            }

            printEnvSnapshot(snapshot, reveal: reveal)

        case "unset":
            guard arguments.count >= 4 else {
                throw CLIError.usage("用法: maker env unset <project-id> <env-name> KEY [KEY ...]")
            }

            let projectID = try parseUUID(arguments[1])
            let envName = arguments[2]
            let keys = Array(arguments.dropFirst(3))
            guard let snapshot = try await UnsetEnvVariablesUseCase(envSets: services.envSets, secrets: services.secrets).execute(
                projectID: projectID,
                name: envName,
                keys: keys
            ) else {
                throw CLIError.missingResource("未找到环境集。")
            }

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_variables_unset", data: snapshot))
                return
            }

            print("已移除变量")
            print("名称: \(snapshot.envSet.name)")
            print("剩余变量数: \(snapshot.resolvedVariables.count)")

        case "delete":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker env delete <project-id> <env-name>")
            }

            let projectID = try parseUUID(arguments[1])
            let envName = arguments[2]
            guard let envSet = try await DeleteEnvSetUseCase(envSets: services.envSets, secrets: services.secrets).execute(
                projectID: projectID,
                name: envName
            ) else {
                throw CLIError.missingResource("未找到环境集。")
            }

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_set_deleted", data: envSet))
                return
            }

            print("已删除环境集")
            print("ID: \(envSet.id.uuidString)")
            print("名称: \(envSet.name)")

        case "copy":
            guard arguments.count >= 4 else {
                throw CLIError.usage("用法: maker env copy <project-id> <source-env-name> <target-env-name>")
            }

            let projectID = try parseUUID(arguments[1])
            let sourceName = arguments[2]
            let targetName = arguments[3]
            guard let snapshot = try await CopyEnvSetUseCase(envSets: services.envSets, secrets: services.secrets).execute(
                projectID: projectID,
                sourceName: sourceName,
                targetName: targetName
            ) else {
                throw CLIError.missingResource("未找到源环境集。")
            }

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "env_set_copied", data: snapshot))
                return
            }

            print("已复制环境集")
            print("名称: \(snapshot.envSet.name)")
            print("变量数: \(snapshot.resolvedVariables.count)")

        default:
            throw CLIError.usage("未知 env 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeCommand(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "profile":
            let services = try CoreServices.makeDefault()
            try await runRuntimeProfileCommand(Array(arguments.dropFirst()), services: services)
        case "session":
            try await runRuntimeSessionCommand(Array(arguments.dropFirst()))
        case "list":
            let services = try CoreServices.makeDefault()
            try await runRuntimeProfileCommand(arguments, services: services)
        case "start", "stop", "restart", "status", "show", "active", "history", "reconcile", "logs":
            try await runRuntimeSessionCommand(arguments)
        default:
            throw CLIError.usage("未知 runtime 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeProfileCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime profile 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "env":
            try await runRuntimeProfileEnvCommand(Array(arguments.dropFirst()), services: services)
        case "deps":
            try await runRuntimeProfileDepsCommand(Array(arguments.dropFirst()), services: services)
        case "health":
            try await runRuntimeProfileHealthCommand(Array(arguments.dropFirst()), services: services)
        case "auto-restart":
            try await runRuntimeProfileAutoRestartCommand(Array(arguments.dropFirst()), services: services)
        case "list":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile list <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            let profiles = try await ListRuntimeProfilesUseCase(runtimeProfiles: services.runtimeProfiles).execute(projectID: projectID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profiles_listed", data: profiles))
                return
            }
            if profiles.isEmpty {
                print("该项目暂无运行单元。")
                return
            }

            for profile in profiles {
                printRuntimeProfile(profile)
            }

        case "show":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile show <profile-id>")
            }

            let profileID = try parseUUID(arguments[1])
            guard let profile = try await GetRuntimeProfileUseCase(runtimeProfiles: services.runtimeProfiles).execute(profileID: profileID) else {
                throw CLIError.missingResource("未找到运行单元。")
            }
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_detail", data: profile))
                return
            }
            printRuntimeProfile(profile)

        case "add":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile add <project-id> --name 名称 --cmd 命令 [--cwd 目录] [--arg 参数]")
            }

            let projectID = try parseUUID(arguments[1])
            guard let name = value(for: "--name", in: arguments),
                  let command = value(for: "--cmd", in: arguments) else {
                throw CLIError.usage("runtime profile add 需要 --name 与 --cmd")
            }

            let workingDir: String
            if let explicitWorkingDir = value(for: "--cwd", in: arguments) {
                workingDir = explicitWorkingDir
            } else if let project = try await services.projects.get(id: projectID) {
                workingDir = project.localPath
            } else {
                throw CLIError.usage("未找到项目，无法推断运行目录。")
            }

            let args = values(for: "--arg", in: arguments)
            let profile = try await CreateRuntimeProfileUseCase(runtimeProfiles: services.runtimeProfiles).execute(
                projectID: projectID,
                name: name,
                entryCommand: command,
                workingDir: workingDir,
                args: args
            )
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_created", data: profile))
                return
            }
            print("已创建运行单元")
            printRuntimeProfile(profile)

        case "update":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile update <profile-id> [--name 名称] [--cmd 命令] [--cwd 目录] [--arg 参数]")
            }

            let profileID = try parseUUID(arguments[1])
            let name = value(for: "--name", in: arguments)
            let command = value(for: "--cmd", in: arguments)
            let workingDir = value(for: "--cwd", in: arguments)
            let args = arguments.contains("--arg") ? values(for: "--arg", in: arguments) : nil
            guard name != nil || command != nil || workingDir != nil || args != nil else {
                throw CLIError.usage("runtime profile update 至少需要一个变更字段。")
            }

            let profile = try await UpdateRuntimeProfileUseCase(runtimeProfiles: services.runtimeProfiles).execute(
                profileID: profileID,
                name: name,
                entryCommand: command,
                workingDir: workingDir,
                args: args
            )
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_updated", data: profile))
                return
            }
            print("已更新运行单元")
            printRuntimeProfile(profile)

        case "delete":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile delete <profile-id>")
            }

            let profileID = try parseUUID(arguments[1])
            try await DeleteRuntimeProfileUseCase(runtimeProfiles: services.runtimeProfiles).execute(profileID: profileID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_deleted", data: CLIIdentifierResponse(id: profileID.uuidString)))
                return
            }
            print("已删除运行单元: \(profileID.uuidString)")

        default:
            throw CLIError.usage("未知 runtime profile 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeProfileEnvCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime profile env 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "attach":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker runtime profile env attach <profile-id> <env-id>")
            }
            let profileID = try parseUUID(arguments[1])
            let envSetID = try parseUUID(arguments[2])
            let profile = try await AttachEnvSetToRuntimeProfileUseCase(
                runtimeProfiles: services.runtimeProfiles,
                envSets: services.envSets
            ).execute(profileID: profileID, envSetID: envSetID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_env_attached", data: profile))
                return
            }
            print("已绑定环境集")
            printRuntimeProfile(profile)

        case "detach":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile env detach <profile-id>")
            }
            let profileID = try parseUUID(arguments[1])
            let profile = try await DetachEnvSetFromRuntimeProfileUseCase(
                runtimeProfiles: services.runtimeProfiles
            ).execute(profileID: profileID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_env_detached", data: profile))
                return
            }
            print("已解绑环境集")
            printRuntimeProfile(profile)

        default:
            throw CLIError.usage("未知 runtime profile env 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeProfileDepsCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime profile deps 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "add":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker runtime profile deps add <profile-id> <depends-on-profile-id>")
            }
            let profileID = try parseUUID(arguments[1])
            let dependsOnProfileID = try parseUUID(arguments[2])
            let profile = try await AddRuntimeProfileDependencyUseCase(
                runtimeProfiles: services.runtimeProfiles
            ).execute(profileID: profileID, dependsOnProfileID: dependsOnProfileID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_dependency_added", data: profile))
                return
            }
            print("已添加依赖")
            printRuntimeProfile(profile)

        case "remove":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker runtime profile deps remove <profile-id> <depends-on-profile-id>")
            }
            let profileID = try parseUUID(arguments[1])
            let dependsOnProfileID = try parseUUID(arguments[2])
            let profile = try await RemoveRuntimeProfileDependencyUseCase(
                runtimeProfiles: services.runtimeProfiles
            ).execute(profileID: profileID, dependsOnProfileID: dependsOnProfileID)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_dependency_removed", data: profile))
                return
            }
            print("已移除依赖")
            printRuntimeProfile(profile)

        default:
            throw CLIError.usage("未知 runtime profile deps 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeProfileHealthCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime profile health 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "set":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime profile health set <profile-id> --type none|http|tcp|process-exists [--target 值]")
            }
            let profileID = try parseUUID(arguments[1])
            guard let rawType = value(for: "--type", in: arguments) else {
                throw CLIError.usage("runtime profile health set 需要 --type")
            }
            let type = try parseHealthCheckType(rawType)
            let target = value(for: "--target", in: arguments)
            let profile = try await SetRuntimeProfileHealthCheckUseCase(
                runtimeProfiles: services.runtimeProfiles
            ).execute(profileID: profileID, type: type, target: target)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_profile_health_updated", data: profile))
                return
            }
            print("已更新健康检查")
            printRuntimeProfile(profile)

        default:
            throw CLIError.usage("未知 runtime profile health 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runRuntimeProfileAutoRestartCommand(_ arguments: [String], services: CoreServices) async throws {
        guard arguments.count >= 2 else {
            throw CLIError.usage("用法: maker runtime profile auto-restart <profile-id> <on|off>")
        }

        let profileID = try parseUUID(arguments[0])
        let enabled = try parseToggle(arguments[1])
        let profile = try await SetRuntimeProfileAutoRestartUseCase(
            runtimeProfiles: services.runtimeProfiles
        ).execute(profileID: profileID, enabled: enabled)
        if outputFormat == .json {
            try emitJSON(CLIEnvelope(message: "runtime_profile_auto_restart_updated", data: profile))
            return
        }
        print("已更新自动重启")
        printRuntimeProfile(profile)
    }

    private static func runRuntimeSessionCommand(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 runtime session 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "list":
            let services = try CoreServices.makeDefault()
            let projectID = try value(for: "--project", in: arguments).map(parseUUID)
            let status = try value(for: "--status", in: arguments).map(parseRunSessionStatus)
            let limit = Int(value(for: "--limit", in: arguments) ?? "20") ?? 20
            let sessions = try await ListRuntimeSessionsUseCase(sessions: services.runSessions).execute(
                projectID: projectID,
                status: status,
                limit: limit
            )
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "runtime_sessions_listed", data: sessions))
                return
            }
            if sessions.isEmpty {
                print("暂无匹配的运行会话。")
                return
            }
            for session in sessions {
                printRuntimeSession(session)
            }

        case "start":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker runtime session start <project-id> <profile-id>")
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
            try emitDaemonResponse(response)

        case "stop":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime session stop <session-id>")
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
            try emitDaemonResponse(response)

        case "restart":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime session restart <session-id>")
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
            try emitDaemonResponse(response)

        case "status", "show":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime session \(subcommand) <session-id>")
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
            try emitDaemonResponse(response)

        case "active":
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.active"
                )
            )
            try emitDaemonResponse(response)

        case "history":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime session history <project-id> [--limit N]")
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
            try emitDaemonResponse(response)

        case "reconcile":
            let projectID = arguments.dropFirst().first.flatMap(UUID.init(uuidString:))
            if arguments.count > 1, projectID == nil {
                throw CLIError.usage("用法: maker runtime session reconcile [project-id]")
            }
            let client = try await ensureDaemonRunning()
            let response = try await client.send(
                DaemonRequest(
                    token: try daemonTokenStore().loadOrCreateToken(),
                    action: "runtime.reconcile",
                    projectID: projectID?.uuidString
                )
            )
            try emitDaemonResponse(response)

        case "logs":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker runtime session logs <session-id> [--tail N] [--follow]")
            }
            let sessionID = try parseUUID(arguments[1])
            let tail = Int(value(for: "--tail", in: arguments) ?? "50") ?? 50
            let follow = arguments.contains("--follow")
            if outputFormat == .json, follow {
                throw CLIError.usage("`maker runtime session logs --json` 暂不支持与 `--follow` 同时使用。")
            }
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
                try emitDaemonResponse(response)
            }

        default:
            throw CLIError.usage("未知 runtime session 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runDoctorCommand() async throws {
        let report = await makeDoctorReport()
        if outputFormat == .json {
            try emitJSON(report)
            return
        }

        print("Maker Doctor")
        for section in report.sections {
            printDiagnosticChecks(title: section.title, checks: section.checks)
        }
        if let summary = report.summary {
            print("---- summary ----")
            print("failures: \(summary.failures)")
            print("warnings: \(summary.warnings)")
        }
    }

    private static func runDiagCommand(_ arguments: [String]) async throws {
        guard let topic = arguments.first else {
            throw CLIError.usage("用法: maker diag <daemon|db|paths|sessions>")
        }

        let section: DiagnosticSection
        switch topic {
        case "daemon":
            section = DiagnosticSection(title: "Daemon", checks: await diagnoseDaemon())
        case "db":
            section = DiagnosticSection(title: "Database", checks: diagnoseDatabase())
        case "paths":
            section = DiagnosticSection(title: "Paths", checks: diagnosePaths())
        case "sessions":
            section = DiagnosticSection(title: "Sessions", checks: await diagnoseSessions())
        default:
            throw CLIError.usage("未知 diag 主题: \(topic)\n\n\(helpText)")
        }

        if outputFormat == .json {
            try emitJSON(makeDiagnosticReport(sections: [section]))
            return
        }
        printDiagnosticChecks(title: section.title, checks: section.checks)
    }

    private static func runMilestoneCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 milestone 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "list":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker milestone list <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            let milestones = try await ListMilestonesUseCase(
                projects: services.projects,
                milestones: services.milestones
            ).execute(projectID: projectID)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "milestones_listed", data: milestones))
                return
            }

            if milestones.isEmpty {
                print("该项目暂无里程碑。")
                return
            }

            for milestone in milestones {
                printMilestone(milestone)
            }

        case "add":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker milestone add <project-id> <title> [--due YYYY-MM-DD]")
            }

            let projectID = try parseUUID(arguments[1])
            let dueFlagIndex = arguments.firstIndex(of: "--due") ?? arguments.endIndex
            let titleParts = Array(arguments[2..<dueFlagIndex])
            let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw CLIError.usage("maker milestone add 需要里程碑标题。")
            }
            let dueDate = try value(for: "--due", in: arguments).map(parseDate)
            let milestone = try await CreateMilestoneUseCase(
                projects: services.projects,
                milestones: services.milestones
            ).execute(projectID: projectID, title: title, dueDate: dueDate)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "milestone_created", data: milestone))
                return
            }

            print("已创建里程碑")
            printMilestone(milestone)

        case "state":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker milestone state <milestone-id> <notStarted|inProgress|completed>")
            }

            let milestoneID = try parseUUID(arguments[1])
            let state = try parseMilestoneState(arguments[2])
            let milestone = try await UpdateMilestoneStateUseCase(
                milestones: services.milestones
            ).execute(milestoneID: milestoneID, state: state)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "milestone_state_updated", data: milestone))
                return
            }

            print("已更新里程碑状态")
            printMilestone(milestone)

        case "edit":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker milestone edit <milestone-id> [--title 标题] [--due YYYY-MM-DD|none]")
            }

            let milestoneID = try parseUUID(arguments[1])
            let title = value(for: "--title", in: arguments)
            let dueDate = try optionalDateValue(for: "--due", in: arguments)
            guard title != nil || dueDate != nil else {
                throw CLIError.usage("maker milestone edit 至少需要一个变更字段。")
            }

            let milestone = try await UpdateMilestoneUseCase(
                milestones: services.milestones
            ).execute(milestoneID: milestoneID, title: title, dueDate: dueDate)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "milestone_updated", data: milestone))
                return
            }

            print("已更新里程碑")
            printMilestone(milestone)

        case "remove", "delete":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker milestone remove <milestone-id>")
            }

            let milestoneID = try parseUUID(arguments[1])
            try await DeleteMilestoneUseCase(
                milestones: services.milestones
            ).execute(milestoneID: milestoneID)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "milestone_deleted", data: CLIIdentifierResponse(id: milestoneID.uuidString)))
                return
            }

            print("已删除里程碑: \(milestoneID.uuidString)")

        default:
            throw CLIError.usage("未知 milestone 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runNoteCommand(_ arguments: [String], services: CoreServices) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("缺少 note 子命令。\n\n\(helpText)")
        }

        switch subcommand {
        case "get":
            guard arguments.count >= 2 else {
                throw CLIError.usage("用法: maker note get <project-id>")
            }

            let projectID = try parseUUID(arguments[1])
            if let note = try await LoadProjectNoteUseCase(notes: services.notes).execute(projectID: projectID) {
                if outputFormat == .json {
                    try emitJSON(CLIEnvelope(message: "note_loaded", data: note))
                    return
                }
                print(note.content)
            } else {
                if outputFormat == .json {
                    try emitJSON(CLIEnvelope(message: "note_not_found", data: Optional<ProjectNote>.none))
                    return
                }
                print("该项目暂无备注。")
            }

        case "set":
            guard arguments.count >= 3 else {
                throw CLIError.usage("用法: maker note set <project-id> <content>")
            }

            let projectID = try parseUUID(arguments[1])
            let content = Array(arguments.dropFirst(2)).joined(separator: " ")
            let note = try await SaveProjectNoteUseCase(notes: services.notes).execute(projectID: projectID, content: content)
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "note_saved", data: note))
                return
            }
            print("已保存备注")
            print("ID: \(note.id.uuidString)")
            print("更新时间: \(note.updatedAt.ISO8601Format())")

        default:
            throw CLIError.usage("未知 note 子命令: \(subcommand)\n\n\(helpText)")
        }
    }

    private static func runPathsCommand(_ arguments: [String]) throws {
        guard arguments.isEmpty || arguments.first == "show" else {
            throw CLIError.usage("用法: maker paths show")
        }

        let paths = AppPaths()
        let snapshot = PathsSnapshot(
            applicationSupport: paths.applicationSupportDirectory.path,
            database: paths.databaseURL.path,
            logs: paths.logsDirectory.path,
            masterKey: paths.masterKeyURL.path,
            daemonToken: paths.daemonTokenURL.path,
            launchAgent: paths.daemonLaunchAgentURL.path
        )
        if outputFormat == .json {
            try emitJSON(CLIEnvelope(message: "paths", data: snapshot))
            return
        }
        print("applicationSupport: \(paths.applicationSupportDirectory.path)")
        print("database: \(paths.databaseURL.path)")
        print("logs: \(paths.logsDirectory.path)")
        print("masterKey: \(paths.masterKeyURL.path)")
        print("daemonToken: \(paths.daemonTokenURL.path)")
        print("launchAgent: \(paths.daemonLaunchAgentURL.path)")
    }

    private static func diagnosePaths() -> [DiagnosticCheck] {
        let paths = AppPaths()
        let fileManager = FileManager.default
        var checks: [DiagnosticCheck] = []

        do {
            try paths.createIfNeeded(fileManager: fileManager)
            checks.append(DiagnosticCheck(name: "applicationSupport", level: .ok, detail: paths.applicationSupportDirectory.path))
        } catch {
            checks.append(DiagnosticCheck(name: "applicationSupport", level: .failure, detail: error.localizedDescription))
        }

        let logsExists = fileManager.fileExists(atPath: paths.logsDirectory.path)
        checks.append(
            DiagnosticCheck(
                name: "logsDirectory",
                level: logsExists ? .ok : .failure,
                detail: logsExists ? paths.logsDirectory.path : "missing: \(paths.logsDirectory.path)"
            )
        )

        let launchAgentsWritable = fileManager.fileExists(atPath: paths.launchAgentsDirectory.path)
            ? fileManager.isWritableFile(atPath: paths.launchAgentsDirectory.path)
            : fileManager.isWritableFile(atPath: paths.launchAgentsDirectory.deletingLastPathComponent().path)
        checks.append(
            DiagnosticCheck(
                name: "launchAgentsDirectory",
                level: launchAgentsWritable ? .ok : .warning,
                detail: paths.launchAgentsDirectory.path
            )
        )

        let masterKeyExists = fileManager.fileExists(atPath: paths.masterKeyURL.path)
        checks.append(
            DiagnosticCheck(
                name: "masterKey",
                level: masterKeyExists ? .ok : .warning,
                detail: masterKeyExists ? paths.masterKeyURL.path : "not created yet"
            )
        )

        let tokenExists = fileManager.fileExists(atPath: paths.daemonTokenURL.path)
        checks.append(
            DiagnosticCheck(
                name: "daemonToken",
                level: tokenExists ? .ok : .warning,
                detail: tokenExists ? paths.daemonTokenURL.path : "not created yet"
            )
        )

        return checks
    }

    private static func diagnoseDatabase() -> [DiagnosticCheck] {
        let paths = AppPaths()
        var checks: [DiagnosticCheck] = []

        do {
            try paths.createIfNeeded()
            let database = try SQLiteDatabase(path: paths.databaseURL.path)
            let version = try database.query("PRAGMA user_version;").first?["user_version"]?.int64Value ?? 0
            let tableRows = try database.query(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('projects', 'runtime_profiles', 'env_sets', 'env_set_secrets', 'run_sessions', 'milestones', 'project_notes');"
            )
            checks.append(
                DiagnosticCheck(
                    name: "databaseOpen",
                    level: .ok,
                    detail: paths.databaseURL.path
                )
            )
            checks.append(
                DiagnosticCheck(
                    name: "schemaVersion",
                    level: version >= 2 ? .ok : .warning,
                    detail: "user_version=\(version)"
                )
            )
            checks.append(
                DiagnosticCheck(
                    name: "coreTables",
                    level: tableRows.count >= 7 ? .ok : .warning,
                    detail: "detected=\(tableRows.count)"
                )
            )
        } catch {
            checks.append(DiagnosticCheck(name: "databaseOpen", level: .failure, detail: error.localizedDescription))
        }

        return checks
    }

    private static func diagnoseDaemon() async -> [DiagnosticCheck] {
        let paths = AppPaths()

        do {
            let manager = LaunchdDaemonManager(paths: paths)
            let launchdStatus = try manager.status()
            let token = try FileSystemDaemonTokenStore(tokenURL: paths.daemonTokenURL).loadToken()
            let client = DaemonClient()
            let responding: Bool
            if let token {
                responding = (try? await ping(client: client, token: token)) ?? false
            } else {
                responding = false
            }

            return [
                DiagnosticCheck(
                    name: "launchAgentInstalled",
                    level: launchdStatus.installed ? .ok : .warning,
                    detail: launchdStatus.installed ? manager.paths.daemonLaunchAgentURL.path : "not installed"
                ),
                DiagnosticCheck(
                    name: "launchdLoaded",
                    level: launchdStatus.loaded ? .ok : .warning,
                    detail: launchdStatus.loaded ? "service target: \(manager.serviceTarget)" : "not loaded"
                ),
                DiagnosticCheck(
                    name: "daemonToken",
                    level: token == nil ? .warning : .ok,
                    detail: token == nil ? "token not created yet" : manager.paths.daemonTokenURL.path
                ),
                DiagnosticCheck(
                    name: "daemonResponding",
                    level: responding ? .ok : .warning,
                    detail: responding ? "tcp://127.0.0.1:\(AppPaths.daemonPort)" : "daemon did not respond"
                )
            ]
        } catch {
            return [DiagnosticCheck(name: "daemonDiagnostics", level: .failure, detail: error.localizedDescription)]
        }
    }

    private static func diagnoseSessions() async -> [DiagnosticCheck] {
        do {
            let services = try CoreServices.makeDefault()
            let items = try await DiagnoseRuntimeSessionsUseCase(
                sessions: services.runSessions,
                processInspector: services.processInspector
            ).execute()

            guard !items.isEmpty else {
                return [DiagnosticCheck(name: "runningSessions", level: .ok, detail: "no active sessions")]
            }

            var checks = [
                DiagnosticCheck(name: "runningSessions", level: .ok, detail: "count=\(items.count)")
            ]
            for item in items {
                let level: DiagnosticLevel = item.processRunning ? .ok : .warning
                let pid = item.pid.map(String.init) ?? "-"
                checks.append(
                    DiagnosticCheck(
                        name: item.sessionID.uuidString,
                        level: level,
                        detail: "project=\(item.projectID.uuidString) profile=\(item.runtimeProfileID.uuidString) pid=\(pid) processRunning=\(item.processRunning)"
                    )
                )
            }
            return checks
        } catch {
            return [DiagnosticCheck(name: "runningSessions", level: .failure, detail: error.localizedDescription)]
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
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "daemon_started", data: try await daemonStatusSnapshot(manager: manager, createTokenIfMissing: true)))
                return
            }
            print("daemon 已通过 launchd 启动")

        case "install":
            let manager = try launchdManager()
            try manager.install(executableURL: try currentExecutableURL())
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "daemon_installed", data: try await daemonStatusSnapshot(manager: manager)))
                return
            }
            print("launchd agent 已安装")
            print("plist: \(manager.paths.daemonLaunchAgentURL.path)")

        case "status":
            let manager = try launchdManager()
            let snapshot = try await daemonStatusSnapshot(manager: manager)

            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "daemon_status", data: snapshot))
                return
            }

            if snapshot.responding {
                print("daemon 运行中")
                print("launchd: loaded")
                return
            }

            if snapshot.loaded {
                print("daemon 未响应，但 launchd 已加载")
                if !snapshot.details.isEmpty {
                    print(snapshot.details)
                }
                return
            }

            if snapshot.installed {
                print("daemon 已安装，但 launchd 未加载")
                if !snapshot.details.isEmpty {
                    print(snapshot.details)
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
                    if outputFormat == .json {
                        try emitJSON(CLIEnvelope(message: "daemon_stopped", data: try await daemonStatusSnapshot(manager: manager)))
                        return
                    }
                    print("daemon 已停止")
                    return
                }
            }
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "daemon_stopping", data: try await daemonStatusSnapshot(manager: manager)))
                return
            }
            print("daemon 正在停止")

        case "uninstall":
            let manager = try launchdManager()
            try manager.uninstall()
            if outputFormat == .json {
                try emitJSON(CLIEnvelope(message: "daemon_uninstalled", data: try await daemonStatusSnapshot(manager: manager)))
                return
            }
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

    private static func daemonStatusSnapshot(
        manager: LaunchdDaemonManager,
        createTokenIfMissing: Bool = false
    ) async throws -> DaemonStatusSnapshot {
        let launchdStatus = try manager.status()
        let tokenStore = try daemonTokenStore()
        let token = try (createTokenIfMissing ? tokenStore.loadOrCreateToken() : tokenStore.loadToken())
        let client = DaemonClient()
        let responding: Bool
        if let token {
            responding = (try? await ping(client: client, token: token)) ?? false
        } else {
            responding = false
        }

        return DaemonStatusSnapshot(
            installed: launchdStatus.installed,
            loaded: launchdStatus.loaded,
            responding: responding,
            serviceTarget: manager.serviceTarget,
            launchAgent: manager.paths.daemonLaunchAgentURL.path,
            daemonToken: manager.paths.daemonTokenURL.path,
            details: launchdStatus.details
        )
    }

    private static func printDaemonResponse(_ response: DaemonResponse) throws {
        guard response.ok else {
            throw CLIError.runtimeCommandFailed(response.message)
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
                throw CLIError.runtimeCommandFailed(response.message)
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

    private static func printDiagnosticChecks(title: String, checks: [DiagnosticCheck]) {
        print("---- \(title.lowercased()) ----")
        for check in checks {
            print("[\(check.level.label)] \(check.name): \(check.detail)")
        }
    }

    private static func emitDaemonResponse(_ response: DaemonResponse) throws {
        if outputFormat == .json {
            try emitJSON(response)
            return
        }
        try printDaemonResponse(response)
    }

    private static func makeDoctorReport() async -> DiagnosticReport {
        let sections = [
            DiagnosticSection(title: "Paths", checks: diagnosePaths()),
            DiagnosticSection(title: "Database", checks: diagnoseDatabase()),
            DiagnosticSection(title: "Daemon", checks: await diagnoseDaemon()),
            DiagnosticSection(title: "Sessions", checks: await diagnoseSessions())
        ]
        return makeDiagnosticReport(sections: sections)
    }

    private static func makeDiagnosticReport(sections: [DiagnosticSection]) -> DiagnosticReport {
        let allChecks = sections.flatMap(\.checks)
        let summary = DiagnosticSummary(
            failures: allChecks.filter { $0.level == .failure }.count,
            warnings: allChecks.filter { $0.level == .warning }.count
        )
        return DiagnosticReport(sections: sections, summary: summary)
    }

    private static func printProject(_ snapshot: ProjectDetailSnapshot) {
        let project = snapshot.project
        print("项目: \(project.name)")
        print("ID: \(project.id.uuidString)")
        print("路径: \(project.localPath)")
        print("状态: \(project.status.rawValue)  优先级: \(project.priority.rawValue)")
        print("仓库类型: \(project.repoType.rawValue)")
        print("技术栈: \(project.stackSummary)")
        print("标签: \(project.tags.joined(separator: ", "))")
        if !project.description.isEmpty {
            print("描述: \(project.description)")
        }
        print("运行单元: \(snapshot.runtimeProfiles.count)")
        print("环境集: \(snapshot.envSets.count)")
        print("里程碑: \(snapshot.milestones.count)")
        print("最近会话: \(snapshot.recentSessions.count)")
        if let note = snapshot.note {
            print("备注: \(note.content)")
        }
        if !snapshot.recentSessions.isEmpty {
            print("---- recent sessions ----")
            for session in snapshot.recentSessions {
                print("[\(session.id.uuidString)] \(session.status.rawValue) pid=\(session.pid.map(String.init) ?? "-")")
            }
        }
    }

    private static func printMilestone(_ milestone: Milestone) {
        print("[\(milestone.id.uuidString)] \(milestone.title)")
        print("  项目: \(milestone.projectID.uuidString)")
        print("  状态: \(milestone.state.rawValue)")
        print("  截止: \(milestone.dueDate.map { $0.ISO8601Format() } ?? "-")")
    }

    private static func printEnvSnapshot(_ snapshot: EnvSetSnapshot, reveal: Bool) {
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
    }

    private static func printRuntimeProfile(_ profile: RuntimeProfile) {
        let args = profile.args.joined(separator: " ")
        print("[\(profile.id.uuidString)] \(profile.name)")
        print("  项目: \(profile.projectID.uuidString)")
        print("  命令: \(profile.entryCommand)\(args.isEmpty ? "" : " \(args)")")
        print("  工作目录: \(profile.workingDir)")
        print("  适配器: \(profile.adapterType.rawValue)")
        print("  环境集: \(profile.envSetID?.uuidString ?? "-")")
        print("  健康检查: \(profile.healthCheckType.rawValue)\(profile.healthCheckTarget.map { " \($0)" } ?? "")")
        print("  依赖: \(profile.dependsOn.isEmpty ? "-" : profile.dependsOn.map(\.uuidString).joined(separator: ", "))")
        print("  自动重启: \(profile.autoRestart ? "on" : "off")")
    }

    private static func printRuntimeSession(_ session: RunSession) {
        print("[\(session.id.uuidString)] \(session.status.rawValue)")
        print("  项目: \(session.projectID.uuidString)")
        print("  运行单元: \(session.runtimeProfileID.uuidString)")
        print("  PID: \(session.pid.map(String.init) ?? "-")")
        print("  startedAt: \(session.startedAt.ISO8601Format())")
        if let endedAt = session.endedAt {
            print("  endedAt: \(endedAt.ISO8601Format())")
        }
        if let exitCode = session.exitCode {
            print("  exitCode: \(exitCode)")
        }
        print("  trigger: \(session.triggerSource.rawValue)")
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

    private static func parseProjectStatus(_ rawValue: String) throws -> ProjectStatus {
        guard let status = ProjectStatus(rawValue: rawValue) else {
            throw CLIError.invalidStatus(rawValue)
        }
        return status
    }

    private static func parseProjectPriority(_ rawValue: String) throws -> ProjectPriority {
        guard let priority = ProjectPriority(rawValue: rawValue.lowercased()) else {
            throw CLIError.invalidPriority(rawValue)
        }
        return priority
    }

    private static func parseHealthCheckType(_ rawValue: String) throws -> HealthCheckType {
        guard let type = HealthCheckType(rawValue: rawValue) else {
            throw CLIError.invalidHealthCheckType(rawValue)
        }
        return type
    }

    private static func parseMilestoneState(_ rawValue: String) throws -> Milestone.State {
        guard let state = Milestone.State(rawValue: rawValue) else {
            throw CLIError.invalidMilestoneState(rawValue)
        }
        return state
    }

    private static func parseRunSessionStatus(_ rawValue: String) throws -> RunSessionStatus {
        guard let status = RunSessionStatus(rawValue: rawValue) else {
            throw CLIError.invalidRunSessionStatus(rawValue)
        }
        return status
    }

    private static func parseDate(_ rawValue: String) throws -> Date {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"

        if let date = dayFormatter.date(from: rawValue) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackISOFormatter.date(from: rawValue) {
            return date
        }

        throw CLIError.invalidDate(rawValue)
    }

    private static func parseToggle(_ rawValue: String) throws -> Bool {
        switch rawValue.lowercased() {
        case "on":
            return true
        case "off":
            return false
        default:
            throw CLIError.invalidToggle(rawValue)
        }
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func optionalDateValue(for flag: String, in arguments: [String]) throws -> Date?? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        guard arguments.indices.contains(index + 1) else {
            throw CLIError.usage("\(flag) 需要一个值。")
        }

        let rawValue = arguments[index + 1]
        switch rawValue.lowercased() {
        case "none", "null", "-":
            return .some(nil)
        default:
            return .some(try parseDate(rawValue))
        }
    }

    private static func values(for flag: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, value in
            guard value == flag, arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }

    private static func emitJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        print(text)
    }

    private static func renderError(_ error: Error) {
        let exitCode = exitCode(for: error)
        if outputFormat == .json {
            let payload = CLIErrorResponse(error: error.localizedDescription, exitCode: exitCode.rawValue)
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(payload)
                FileHandle.standardError.write(data)
                FileHandle.standardError.write(Data([0x0A]))
            } catch {
                fputs("Error: \(payload.error)\n", stderr)
            }
            return
        }
        fputs("Error: \(error.localizedDescription)\n", stderr)
    }

    private static func exitCode(for error: Error) -> CLIExitCode {
        if let error = error as? CLIError {
            switch error {
            case .usage, .invalidIdentifier, .invalidAssignment, .invalidStatus, .invalidPriority, .invalidRunSessionStatus, .invalidHealthCheckType, .invalidMilestoneState, .invalidDate, .invalidToggle:
                return .invalidUsage
            case .missingResource:
                return .missingResource
            case .runtimeCommandFailed:
                return .runtimeFailure
            case .daemonUnavailable:
                return .daemonUnavailable
            }
        }

        if let error = error as? MakerError {
            switch error {
            case .missingResource:
                return .missingResource
            case .invalidConfiguration:
                return .invalidUsage
            case .processAlreadyRunning, .processNotRunning, .unsupported:
                return .runtimeFailure
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain {
            if nsError.code == NSFileWriteNoPermissionError || nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
                return .environmentFailure
            }
        }

        return .generalFailure
    }

    private static func printHelp() {
        print(helpText)
    }
}

private let helpText = """
Maker CLI

用法:
  关键查询/诊断命令支持追加 --json

  maker doctor
  maker diag <daemon|db|paths|sessions>
  maker milestone list <project-id>
  maker milestone add <project-id> <title> [--due YYYY-MM-DD]
  maker milestone state <milestone-id> <notStarted|inProgress|completed>
  maker milestone edit <milestone-id> [--title 标题] [--due YYYY-MM-DD|none]
  maker milestone remove <milestone-id>

  maker project add <path> [--description 文本] [--tag 标签]
  maker project list
  maker project show <project-id>
  maker project update <project-id> [--name 名称] [--description 文本] [--status 状态] [--priority 优先级]
  maker project archive <project-id>
  maker project unarchive <project-id> [--status 状态]
  maker project rescan <project-id>

  maker env list <project-id>
  maker env set <project-id> <env-name> KEY=VALUE [KEY=VALUE ...]
  maker env get <project-id> <env-name> [--reveal]
  maker env unset <project-id> <env-name> KEY [KEY ...]
  maker env delete <project-id> <env-name>
  maker env copy <project-id> <source-env-name> <target-env-name>

  maker runtime profile list <project-id>
  maker runtime profile show <profile-id>
  maker runtime profile add <project-id> --name 名称 --cmd 命令 [--cwd 目录] [--arg 参数]
  maker runtime profile update <profile-id> [--name 名称] [--cmd 命令] [--cwd 目录] [--arg 参数]
  maker runtime profile delete <profile-id>
  maker runtime profile env attach <profile-id> <env-id>
  maker runtime profile env detach <profile-id>
  maker runtime profile deps add <profile-id> <depends-on-profile-id>
  maker runtime profile deps remove <profile-id> <depends-on-profile-id>
  maker runtime profile health set <profile-id> --type none|http|tcp|process-exists [--target 值]
  maker runtime profile auto-restart <profile-id> <on|off>

  maker runtime session start <project-id> <profile-id>
  maker runtime session list [--project 项目ID] [--status 状态] [--limit N]
  maker runtime session stop <session-id>
  maker runtime session restart <session-id>
  maker runtime session status <session-id>
  maker runtime session show <session-id>
  maker runtime session active
  maker runtime session history <project-id> [--limit N]
  maker runtime session reconcile [project-id]
  maker runtime session logs <session-id> [--tail N] [--follow]

兼容别名:
  maker runtime list <project-id>
  maker runtime start <project-id> <profile-id>
  maker runtime stop <session-id>
  maker runtime restart <session-id>
  maker runtime status <session-id>
  maker runtime active
  maker runtime history <project-id> [--limit N]
  maker runtime reconcile [project-id]
  maker runtime logs <session-id> [--tail N] [--follow]

  maker note get <project-id>
  maker note set <project-id> <content>
  maker paths show
  maker daemon install|start|status|stop|uninstall|run
"""
