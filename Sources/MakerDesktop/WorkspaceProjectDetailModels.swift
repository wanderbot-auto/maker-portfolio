import Foundation
import SwiftUI
import MakerDomain

struct ProjectDetailPageModel {
    let projectID: Project.ID
    let title: String
    let path: String
    let stackSummary: String
    let status: WorkspaceStatus
    let description: String
    let readmeSnippet: String?
    let footprint: RepositoryFootprint
    let codeComposition: [CodeCompositionComponent]
    let supplyChain: [DependencyManifestSummary]
    let git: GitRepositorySnapshot
    let runtimeProfiles: [RuntimeProfileDisplayModel]
    let recentSessions: [RuntimeSessionDisplayModel]
    let recentLogs: [String]
    let buildCommand: CommandDescriptor?
    let latestBuild: CommandExecutionResult?
    let actionFeedback: ActionFeedback?

    var runningSessionID: RunSession.ID? {
        recentSessions.first(where: { $0.status == .running })?.id
    }

    var preferredRuntimeProfileID: RuntimeProfile.ID? {
        runtimeProfiles.sorted { lhs, rhs in
            lhs.priority < rhs.priority
        }.first?.id
    }
}

struct RepositoryFootprint {
    let totalSizeBytes: Int64
    let sourceSizeBytes: Int64
    let totalFiles: Int
    let sourceFiles: Int

    var totalSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var sourceSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sourceSizeBytes, countStyle: .file)
    }
}

struct CodeCompositionComponent: Identifiable {
    let id = UUID()
    let name: String
    let fileCount: Int
    let lineCount: Int
    let percentage: Double
    let color: Color
}

struct DependencyManifestSummary: Identifiable {
    let id = UUID()
    let ecosystem: String
    let directDependencies: Int
    let lockfilePresent: Bool
    let highlights: [String]
}

struct GitActivityPoint: Identifiable {
    let id = UUID()
    let label: String
    let commitCount: Int
}

struct GitRecentCommit: Identifiable {
    let id = UUID()
    let hash: String
    let date: String
    let author: String
    let message: String
}

struct GitRepositorySnapshot {
    let isGitRepository: Bool
    let branch: String
    let remote: String?
    let latestCommitHash: String?
    let latestCommitMessage: String?
    let latestCommitAuthor: String?
    let latestCommitDate: String?
    let modifiedFiles: Int
    let addedFiles: Int
    let deletedFiles: Int
    let untrackedFiles: Int
    let aheadBehind: String?
    let recentActivity: [GitActivityPoint]
    let recentCommits: [GitRecentCommit]

    static let none = GitRepositorySnapshot(
        isGitRepository: false,
        branch: "No Git repository",
        remote: nil,
        latestCommitHash: nil,
        latestCommitMessage: nil,
        latestCommitAuthor: nil,
        latestCommitDate: nil,
        modifiedFiles: 0,
        addedFiles: 0,
        deletedFiles: 0,
        untrackedFiles: 0,
        aheadBehind: nil,
        recentActivity: [],
        recentCommits: []
    )
}

struct RuntimeProfileDisplayModel: Identifiable {
    let id: RuntimeProfile.ID
    let name: String
    let command: String
    let healthCheck: String
    let autoRestart: Bool
    let priority: Int
}

struct RuntimeSessionDisplayModel: Identifiable {
    let id: RunSession.ID
    let status: RunSessionStatus
    let startedAt: String
    let detail: String
    let pid: String
}

struct CommandDescriptor: Sendable {
    let title: String
    let executable: String
    let arguments: [String]
    let workingDirectory: String

    var commandLine: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

struct CommandExecutionResult: Sendable {
    let command: CommandDescriptor
    let exitCode: Int32
    let output: String
    let executedAt: Date

    var succeeded: Bool {
        exitCode == 0
    }
}

struct ActionFeedback {
    enum Tone {
        case info
        case success
        case failure
    }

    let tone: Tone
    let message: String
    let timestamp: Date
}
