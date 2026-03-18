import Foundation

public struct EnvSet: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public enum Scope: String, Codable, Sendable, CaseIterable {
        case project
        case runtimeProfile
    }

    public var id: ID
    public var projectID: Project.ID
    public var name: String
    public var variables: [String: String]
    public var isEncrypted: Bool
    public var scope: Scope

    public init(
        id: ID = UUID(),
        projectID: Project.ID,
        name: String,
        variables: [String: String] = [:],
        isEncrypted: Bool = true,
        scope: Scope = .project
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.variables = variables
        self.isEncrypted = isEncrypted
        self.scope = scope
    }
}
