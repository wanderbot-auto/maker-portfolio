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
            profiles.append(contentsOf: npmProfiles(workingDir: workingDir))
        }

        return deduplicate(profiles)
    }

    public func discoverProjectPaths(at rootPath: String, recursive: Bool = true) throws -> [String] {
        let rootURL = URL(fileURLWithPath: rootPath)
        let resourceValues = try rootURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw CocoaError(.fileReadUnknown)
        }

        if recursive == false {
            let fileNames = try Set(FileManager.default.contentsOfDirectory(atPath: rootPath))
            return isProjectRoot(fileNames: fileNames) ? [rootPath] : []
        }

        var matches: Set<String> = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true else {
                continue
            }

            let name = values.name ?? item.lastPathComponent
            if ["node_modules", ".build", "build", "dist", ".git", ".swiftpm"].contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let fileNames = try Set(FileManager.default.contentsOfDirectory(atPath: item.path))
            if isProjectRoot(fileNames: fileNames) {
                matches.insert(item.path)
            }
        }

        if matches.isEmpty, let fileNames = try? Set(FileManager.default.contentsOfDirectory(atPath: rootPath)), isProjectRoot(fileNames: fileNames) {
            matches.insert(rootPath)
        }

        return Array(matches).sorted()
    }

    private func npmProfiles(workingDir: String) -> [DiscoveredRuntimeProfile] {
        let packageURL = URL(fileURLWithPath: workingDir).appendingPathComponent("package.json")
        guard
            let data = try? Data(contentsOf: packageURL),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = payload["scripts"] as? [String: Any]
        else {
            return [
                DiscoveredRuntimeProfile(
                    name: "npm-dev",
                    entryCommand: "npm",
                    workingDir: workingDir,
                    args: ["run", "dev"]
                )
            ]
        }

        let preferredScripts = ["dev", "start", "web", "api", "worker"]
        return preferredScripts.compactMap { name in
            guard scripts[name] != nil else { return nil }
            return DiscoveredRuntimeProfile(
                name: "npm-\(name)",
                entryCommand: "npm",
                workingDir: workingDir,
                args: ["run", name]
            )
        }
    }

    private func isProjectRoot(fileNames: Set<String>) -> Bool {
        let markers = [".git", "Package.swift", "package.json", "Cargo.toml", "pubspec.yaml", "Podfile"]
        return markers.contains { fileNames.contains($0) }
    }

    private func deduplicate(_ profiles: [DiscoveredRuntimeProfile]) -> [DiscoveredRuntimeProfile] {
        var seen: Set<String> = []
        var unique: [DiscoveredRuntimeProfile] = []

        for profile in profiles {
            let key = ([profile.name, profile.entryCommand, profile.workingDir] + profile.args).joined(separator: "\u{1F}")
            if seen.insert(key).inserted {
                unique.append(profile)
            }
        }

        return unique
    }
}
