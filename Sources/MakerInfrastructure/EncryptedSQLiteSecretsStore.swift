import CryptoKit
import Foundation
import MakerApplication
import MakerDomain

public actor EncryptedSQLiteSecretsStore: SecretsStore {
    private let database: SQLiteDatabase
    private let masterKeyProvider: FileSystemMasterKeyProvider
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase, masterKeyProvider: FileSystemMasterKeyProvider) {
        self.database = database
        self.masterKeyProvider = masterKeyProvider
    }

    public func save(values: [String: String], for envSetID: EnvSet.ID) async throws {
        let key = try masterKeyProvider.loadOrCreateKey()
        let plaintext = try encoder.encode(values)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw CocoaError(.coderInvalidValue)
        }

        try database.execute(
            """
            INSERT INTO env_set_secrets (env_set_id, encrypted_blob, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(env_set_id) DO UPDATE SET
                encrypted_blob = excluded.encrypted_blob,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(envSetID.uuidString),
                .blob(combined),
                .real(Date().timeIntervalSince1970)
            ]
        )
    }

    public func load(for envSetID: EnvSet.ID) async throws -> [String: String] {
        let rows = try database.query(
            "SELECT encrypted_blob FROM env_set_secrets WHERE env_set_id = ? LIMIT 1;",
            bindings: [.text(envSetID.uuidString)]
        )

        guard let blob = rows.first?["encrypted_blob"] else {
            return [:]
        }

        let encryptedData: Data
        switch blob {
        case let .blob(data):
            encryptedData = data
        case let .text(text):
            encryptedData = Data(text.utf8)
        default:
            return [:]
        }

        let key = try masterKeyProvider.loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try decoder.decode([String: String].self, from: plaintext)
    }

    public func delete(for envSetID: EnvSet.ID) async throws {
        try database.execute(
            "DELETE FROM env_set_secrets WHERE env_set_id = ?;",
            bindings: [.text(envSetID.uuidString)]
        )
    }
}
