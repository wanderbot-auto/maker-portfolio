import Foundation

public struct AppPaths: Sendable {
    public static let daemonPort: UInt16 = 47832
    public static let daemonLaunchAgentLabel = "com.makerportfolio.daemon"
    public static let applicationSupportOverrideEnv = "MAKER_APP_SUPPORT_DIR"
    public static let launchAgentsOverrideEnv = "MAKER_LAUNCH_AGENTS_DIR"

    public let applicationSupportDirectory: URL
    public let launchAgentsDirectory: URL
    public let databaseURL: URL
    public let logsDirectory: URL
    public let masterKeyURL: URL
    public let daemonTokenURL: URL
    public let daemonLaunchAgentURL: URL
    public let daemonStdoutURL: URL
    public let daemonStderrURL: URL

    public init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        launchAgentsDirectory: URL? = nil
    ) {
        let environment = ProcessInfo.processInfo.environment
        let base = applicationSupportDirectory ??
            environment[Self.applicationSupportOverrideEnv].map { URL(fileURLWithPath: $0, isDirectory: true) } ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MakerPortfolio", isDirectory: true)
        let launchAgents = launchAgentsDirectory ??
            environment[Self.launchAgentsOverrideEnv].map { URL(fileURLWithPath: $0, isDirectory: true) } ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)

        self.applicationSupportDirectory = base
        self.launchAgentsDirectory = launchAgents
        self.databaseURL = base.appendingPathComponent("maker.sqlite")
        self.logsDirectory = base.appendingPathComponent("Logs", isDirectory: true)
        self.masterKeyURL = base.appendingPathComponent("master.key")
        self.daemonTokenURL = base.appendingPathComponent("daemon.token")
        self.daemonLaunchAgentURL = launchAgents.appendingPathComponent("\(Self.daemonLaunchAgentLabel).plist")
        self.daemonStdoutURL = base.appendingPathComponent("daemon.stdout.log")
        self.daemonStderrURL = base.appendingPathComponent("daemon.stderr.log")
    }

    public func createIfNeeded(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}
