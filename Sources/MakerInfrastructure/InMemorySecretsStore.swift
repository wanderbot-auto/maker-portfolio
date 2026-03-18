import Foundation
import MakerApplication
import MakerDomain

public actor InMemorySecretsStore: SecretsStore {
    private var storage: [EnvSet.ID: [String: String]] = [:]

    public init() {}

    public func save(values: [String: String], for envSetID: EnvSet.ID) async throws {
        storage[envSetID] = values
    }

    public func load(for envSetID: EnvSet.ID) async throws -> [String: String] {
        storage[envSetID] ?? [:]
    }

    public func delete(for envSetID: EnvSet.ID) async throws {
        storage.removeValue(forKey: envSetID)
    }
}
