import Foundation
import SwiftUI
import MakerApplication
import MakerDomain

struct WorkspaceRepositoryInspector {
    private let commandRunner = WorkspaceLocalCommandRunner()
    private let fileManager = FileManager.default

    func analyze(
        project: Project,
        scan: ProjectScanResult?,
        runtimeProfiles: [RuntimeProfile]
    ) async -> (
        footprint: RepositoryFootprint,
        composition: [CodeCompositionComponent],
        supplyChain: [DependencyManifestSummary],
        git: GitRepositorySnapshot,
        buildCommand: CommandDescriptor?
    ) {
        let footprint = analyzeFootprint(at: project.localPath)
        let composition = analyzeComposition(at: project.localPath)
        let supplyChain = analyzeSupplyChain(at: project.localPath)
        let git = await analyzeGit(at: project.localPath)
        let buildCommand = inferBuildCommand(at: project.localPath, scan: scan, runtimeProfiles: runtimeProfiles)

        return (footprint, composition, supplyChain, git, buildCommand)
    }

    private func analyzeFootprint(at path: String) -> RepositoryFootprint {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .nameKey],
            options: [.skipsPackageDescendants]
        ) else {
            return RepositoryFootprint(totalSizeBytes: 0, sourceSizeBytes: 0, totalFiles: 0, sourceFiles: 0)
        }

        var totalSize: Int64 = 0
        var sourceSize: Int64 = 0
        var totalFiles = 0
        var sourceFiles = 0

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .nameKey]) else {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            totalSize += size
            totalFiles += 1

            let pathComponents = url.pathComponents
            let isIgnored = pathComponents.contains(where: { ["node_modules", ".git", ".build", "dist", "build", ".next"].contains($0) })
            if isIgnored == false {
                sourceSize += size
                sourceFiles += 1
            }
        }

        return RepositoryFootprint(
            totalSizeBytes: totalSize,
            sourceSizeBytes: sourceSize,
            totalFiles: totalFiles,
            sourceFiles: sourceFiles
        )
    }

    private func analyzeComposition(at path: String) -> [CodeCompositionComponent] {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return fallbackComposition()
        }

        struct Bucket {
            var files = 0
            var lines = 0
            let color: Color
        }

        let palette: [String: Color] = [
            "Swift": WorkspacePalette.blue,
            "TypeScript": WorkspacePalette.indigo,
            "JavaScript": WorkspacePalette.yellow,
            "Rust": WorkspacePalette.peach,
            "Styles": WorkspacePalette.purple,
            "Docs": WorkspacePalette.slate
        ]

        var buckets: [String: Bucket] = [:]

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }

            let pathComponents = url.pathComponents
            if pathComponents.contains(where: { ["node_modules", ".git", ".build", "dist", "build", ".next"].contains($0) }) {
                continue
            }

            guard let category = languageCategory(for: url.pathExtension.lowercased()) else {
                continue
            }

            let lineCount = countLines(at: url)
            var bucket = buckets[category] ?? Bucket(files: 0, lines: 0, color: palette[category] ?? WorkspacePalette.slate)
            bucket.files += 1
            bucket.lines += lineCount
            buckets[category] = bucket
        }

        let totalLines = max(1, buckets.values.reduce(0) { $0 + $1.lines })
        let components = buckets
            .map { key, bucket in
                CodeCompositionComponent(
                    name: key,
                    fileCount: bucket.files,
                    lineCount: bucket.lines,
                    percentage: Double(bucket.lines) / Double(totalLines),
                    color: bucket.color
                )
            }
            .sorted { lhs, rhs in
                lhs.lineCount > rhs.lineCount
            }

        return components.isEmpty ? fallbackComposition() : components
    }

    private func fallbackComposition() -> [CodeCompositionComponent] {
        [
            CodeCompositionComponent(name: "Swift", fileCount: 0, lineCount: 0, percentage: 0.4, color: WorkspacePalette.blue),
            CodeCompositionComponent(name: "TypeScript", fileCount: 0, lineCount: 0, percentage: 0.3, color: WorkspacePalette.indigo),
            CodeCompositionComponent(name: "Rust", fileCount: 0, lineCount: 0, percentage: 0.2, color: WorkspacePalette.peach),
            CodeCompositionComponent(name: "Styles", fileCount: 0, lineCount: 0, percentage: 0.1, color: WorkspacePalette.purple)
        ]
    }

    private func analyzeSupplyChain(at path: String) -> [DependencyManifestSummary] {
        var manifests: [DependencyManifestSummary] = []
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)

        let packageJSON = rootURL.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: packageJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var dependencies: [String] = []
            for key in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
                if let section = json[key] as? [String: String] {
                    dependencies.append(contentsOf: section.keys)
                }
            }
            manifests.append(
                DependencyManifestSummary(
                    ecosystem: "Node / npm",
                    directDependencies: dependencies.count,
                    lockfilePresent: fileManager.fileExists(atPath: rootURL.appendingPathComponent("package-lock.json").path) ||
                        fileManager.fileExists(atPath: rootURL.appendingPathComponent("pnpm-lock.yaml").path) ||
                        fileManager.fileExists(atPath: rootURL.appendingPathComponent("yarn.lock").path),
                    highlights: Array(dependencies.sorted().prefix(4))
                )
            )
        }

        let packageSwift = rootURL.appendingPathComponent("Package.swift")
        if let text = try? String(contentsOf: packageSwift) {
            let dependencies = text
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.contains(".package(") }
                .map { line in
                    line
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }

            manifests.append(
                DependencyManifestSummary(
                    ecosystem: "SwiftPM",
                    directDependencies: dependencies.count,
                    lockfilePresent: fileManager.fileExists(atPath: rootURL.appendingPathComponent("Package.resolved").path),
                    highlights: Array(dependencies.prefix(3))
                )
            )
        }

        let cargoToml = rootURL.appendingPathComponent("Cargo.toml")
        if let text = try? String(contentsOf: cargoToml) {
            let dependencies = parseCargoDependencies(text: text)
            manifests.append(
                DependencyManifestSummary(
                    ecosystem: "Cargo",
                    directDependencies: dependencies.count,
                    lockfilePresent: fileManager.fileExists(atPath: rootURL.appendingPathComponent("Cargo.lock").path),
                    highlights: Array(dependencies.prefix(4))
                )
            )
        }

        return manifests.isEmpty ? [
            DependencyManifestSummary(ecosystem: "Local Workspace", directDependencies: 0, lockfilePresent: false, highlights: ["No package manifests detected"])
        ] : manifests
    }

    private func parseCargoDependencies(text: String) -> [String] {
        var results: [String] = []
        var inDependencySection = false

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inDependencySection = line == "[dependencies]" || line == "[dev-dependencies]" || line == "[build-dependencies]"
                continue
            }
            guard inDependencySection, line.isEmpty == false, line.hasPrefix("#") == false else {
                continue
            }
            if let name = line.split(separator: "=").first {
                results.append(String(name).trimmingCharacters(in: .whitespaces))
            }
        }

        return results
    }

    private func analyzeGit(at path: String) async -> GitRepositorySnapshot {
        let probe = try? await commandRunner.execute(
            CommandDescriptor(title: "git probe", executable: "git", arguments: ["-C", path, "rev-parse", "--is-inside-work-tree"], workingDirectory: path)
        )
        guard probe?.succeeded == true else {
            return .none
        }

        let branchResult = try? await commandRunner.execute(
            CommandDescriptor(title: "git branch", executable: "git", arguments: ["-C", path, "branch", "--show-current"], workingDirectory: path)
        )
        let logResult = try? await commandRunner.execute(
            CommandDescriptor(title: "git log", executable: "git", arguments: ["-C", path, "log", "-1", "--pretty=format:%h%x1f%an%x1f%ad%x1f%s", "--date=short"], workingDirectory: path)
        )
        let remoteResult = try? await commandRunner.execute(
            CommandDescriptor(title: "git remote", executable: "git", arguments: ["-C", path, "remote", "get-url", "origin"], workingDirectory: path)
        )
        let statusResult = try? await commandRunner.execute(
            CommandDescriptor(title: "git status", executable: "git", arguments: ["-C", path, "status", "--porcelain"], workingDirectory: path)
        )
        let upstreamResult = try? await commandRunner.execute(
            CommandDescriptor(title: "git ahead behind", executable: "git", arguments: ["-C", path, "rev-list", "--left-right", "--count", "@{upstream}...HEAD"], workingDirectory: path)
        )
        let recentActivityResult = try? await commandRunner.execute(
            CommandDescriptor(
                title: "git recent activity",
                executable: "git",
                arguments: ["-C", path, "log", "--since=13 days ago", "--date=short", "--pretty=format:%ad"],
                workingDirectory: path
            )
        )
        let recentCommitsResult = try? await commandRunner.execute(
            CommandDescriptor(
                title: "git recent commits",
                executable: "git",
                arguments: ["-C", path, "log", "-5", "--pretty=format:%h%x1f%ad%x1f%an%x1f%s", "--date=short"],
                workingDirectory: path
            )
        )

        let branch = (branchResult?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let logOutput = (logResult?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = (remoteResult?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = statusResult?.output ?? ""
        let upstream = (upstreamResult?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recentActivityOutput = recentActivityResult?.output ?? ""
        let recentCommitsOutput = recentCommitsResult?.output ?? ""

        let logParts = logOutput.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        let statusLines = statusOutput.split(whereSeparator: \.isNewline).map(String.init)
        let workingTree = summarizeWorkingTree(statusLines)

        return GitRepositorySnapshot(
            isGitRepository: true,
            branch: branch.isEmpty ? "detached" : branch,
            remote: remote.isEmpty ? nil : remote,
            latestCommitHash: logParts.count > 0 ? logParts[0] : nil,
            latestCommitMessage: logParts.count > 3 ? logParts[3] : nil,
            latestCommitAuthor: logParts.count > 1 ? logParts[1] : nil,
            latestCommitDate: logParts.count > 2 ? logParts[2] : nil,
            modifiedFiles: workingTree.modifiedFiles,
            addedFiles: workingTree.addedFiles,
            deletedFiles: workingTree.deletedFiles,
            untrackedFiles: workingTree.untrackedFiles,
            aheadBehind: upstream.isEmpty ? nil : upstream.replacingOccurrences(of: "\t", with: " / "),
            recentActivity: recentActivityPoints(from: recentActivityOutput),
            recentCommits: recentCommits(from: recentCommitsOutput)
        )
    }

    private func summarizeWorkingTree(_ statusLines: [String]) -> (modifiedFiles: Int, addedFiles: Int, deletedFiles: Int, untrackedFiles: Int) {
        var modifiedFiles = 0
        var addedFiles = 0
        var deletedFiles = 0
        var untrackedFiles = 0

        for line in statusLines {
            if line.hasPrefix("??") {
                untrackedFiles += 1
                continue
            }

            let status = String(line.prefix(2))
            if status.contains("D") {
                deletedFiles += 1
            } else if status.contains("A") {
                addedFiles += 1
            } else {
                modifiedFiles += 1
            }
        }

        return (modifiedFiles, addedFiles, deletedFiles, untrackedFiles)
    }

    private func recentActivityPoints(from output: String, days: Int = 14) -> [GitActivityPoint] {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = dateFormatter.calendar
        labelFormatter.locale = dateFormatter.locale
        labelFormatter.dateFormat = "MM/dd"

        let counts = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .reduce(into: [String: Int]()) { partialResult, value in
                partialResult[value, default: 0] += 1
            }

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            let key = dateFormatter.string(from: date)
            return GitActivityPoint(
                label: labelFormatter.string(from: date),
                commitCount: counts[key, default: 0]
            )
        }
    }

    private func recentCommits(from output: String) -> [GitRecentCommit] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4 else { return nil }
                return GitRecentCommit(
                    hash: parts[0],
                    date: parts[1],
                    author: parts[2],
                    message: parts[3]
                )
            }
    }

    private func inferBuildCommand(
        at path: String,
        scan: ProjectScanResult?,
        runtimeProfiles: [RuntimeProfile]
    ) -> CommandDescriptor? {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        if let packageScripts = npmScripts(at: rootURL), packageScripts["build"] != nil {
            return CommandDescriptor(title: "Build", executable: "npm", arguments: ["run", "build"], workingDirectory: path)
        }
        if fileManager.fileExists(atPath: rootURL.appendingPathComponent("Package.swift").path) {
            return CommandDescriptor(title: "Build", executable: "swift", arguments: ["build"], workingDirectory: path)
        }
        if fileManager.fileExists(atPath: rootURL.appendingPathComponent("Cargo.toml").path) {
            return CommandDescriptor(title: "Build", executable: "cargo", arguments: ["build"], workingDirectory: path)
        }
        if let discovered = scan?.discoveredProfiles.first {
            return CommandDescriptor(
                title: "Run",
                executable: discovered.entryCommand,
                arguments: discovered.args,
                workingDirectory: discovered.workingDir
            )
        }
        if let profile = runtimeProfiles.first {
            return CommandDescriptor(
                title: "Run",
                executable: profile.entryCommand,
                arguments: profile.args,
                workingDirectory: profile.workingDir
            )
        }
        return nil
    }

    private func npmScripts(at rootURL: URL) -> [String: Any]? {
        let packageURL = rootURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = payload["scripts"] as? [String: Any] else {
            return nil
        }
        return scripts
    }

    private func countLines(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return 0
        }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func languageCategory(for extensionName: String) -> String? {
        switch extensionName {
        case "swift":
            return "Swift"
        case "ts", "tsx":
            return "TypeScript"
        case "js", "jsx", "mjs", "cjs":
            return "JavaScript"
        case "rs":
            return "Rust"
        case "css", "scss", "sass", "less":
            return "Styles"
        case "md", "mdx":
            return "Docs"
        default:
            return nil
        }
    }
}
