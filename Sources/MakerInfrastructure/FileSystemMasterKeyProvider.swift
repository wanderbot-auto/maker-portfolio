import CryptoKit
import Foundation

public struct FileSystemMasterKeyProvider: Sendable {
    public let keyURL: URL

    public init(keyURL: URL) {
        self.keyURL = keyURL
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadExistingKey() {
            return existing
        }

        let key = SymmetricKey(size: .bits256)
        try persist(key)
        return key
    }

    private func loadExistingKey() throws -> SymmetricKey? {
        guard FileManager.default.fileExists(atPath: keyURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: keyURL)
        guard !data.isEmpty else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    private func persist(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        try data.write(to: keyURL, options: [.atomic])

        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: keyURL.path
        )
    }
}
