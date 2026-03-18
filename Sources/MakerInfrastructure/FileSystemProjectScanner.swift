import Foundation
import MakerApplication
import MakerDomain

public struct FileSystemProjectScanner: ProjectScanner {
    public init() {}

    public func scan(at path: String) async throws -> ProjectScanResult {
        let url = URL(fileURLWithPath: path)
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw CocoaError(.fileReadUnknown)
        }

        let fileNames = try Set(FileManager.default.contentsOfDirectory(atPath: path))
        let repoType: RepoType = fileNames.contains(".git") ? .git : .localOnly
        let stackSummary = inferStack(from: fileNames)
        let readmeSnippet = readmeText(in: path)
        let profiles = discoverProfiles(fileNames: fileNames, workingDir: path)

        return ProjectScanResult(
            suggestedName: url.lastPathComponent,
            repoType: repoType,
            stackSummary: stackSummary,
            readmeSnippet: readmeSnippet,
            discoveredProfiles: profiles
        )
    }

    private func inferStack(from fileNames: Set<String>) -> String {
        var labels: [String] = []
        if fileNames.contains("Package.swift") { labels.append("Swift") }
        if fileNames.contains("package.json") { labels.append("Node.js") }
        if fileNames.contains("Cargo.toml") { labels.append("Rust") }
        if fileNames.contains("pubspec.yaml") { labels.append("Flutter") }
        if fileNames.contains("Podfile") { labels.append("CocoaPods") }
        return labels.isEmpty ? "Unknown" : labels.joined(separator: " / ")
    }

    private func readmeText(in path: String) -> String? {
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent("README.md")
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
            .split(separator: "\n")
            .prefix(3)
            .joined(separator: "\n")
    }

    private func discoverProfiles(fileNames: Set<String>, workingDir: String) -> [DiscoveredRuntimeProfile] {
        var profiles: [DiscoveredRuntimeProfile] = []

        if fileNames.contains("Package.swift") {
            profiles.append(
                DiscoveredRuntimeProfile(
                    name: "swift-run",
                    entryCommand: "swift",
                    workingDir: workingDir,
                    args: ["run"]
                )
            )
        }
        if fileNames.contains("package.json") {
            profiles.append(
                DiscoveredRuntimeProfile(
                    name: "npm-dev",
                    entryCommand: "npm",
                    workingDir: workingDir,
                    args: ["run", "dev"]
                )
            )
        }

        return profiles
    }
}
