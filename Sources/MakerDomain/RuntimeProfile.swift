import Foundation

public struct RuntimeProfile: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var projectID: Project.ID
    public var name: String
    public var entryCommand: String
    public var workingDir: String
    public var args: [String]
    public var envSetID: EnvSet.ID?
    public var healthCheckType: HealthCheckType
    public var healthCheckTarget: String?
    public var dependsOn: [ID]
    public var adapterType: RuntimeAdapterType
    public var autoRestart: Bool

    public init(
        id: ID = UUID(),
        projectID: Project.ID,
        name: String,
        entryCommand: String,
        workingDir: String,
        args: [String] = [],
        envSetID: EnvSet.ID? = nil,
        healthCheckType: HealthCheckType = .none,
        healthCheckTarget: String? = nil,
        dependsOn: [ID] = [],
        adapterType: RuntimeAdapterType = .localProcess,
        autoRestart: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.entryCommand = entryCommand
        self.workingDir = workingDir
        self.args = args
        self.envSetID = envSetID
        self.healthCheckType = healthCheckType
        self.healthCheckTarget = healthCheckTarget
        self.dependsOn = dependsOn
        self.adapterType = adapterType
        self.autoRestart = autoRestart
    }
}

public enum HealthCheckType: String, Codable, Sendable, CaseIterable {
    case none
    case http
    case tcp
    case processExists = "process-exists"
}

public enum RuntimeAdapterType: String, Codable, Sendable, CaseIterable {
    case localProcess
    case androidEmulator
    case iosSimulator
    case macosVM
}
