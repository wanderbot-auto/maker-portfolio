import Foundation

public struct FileSystemDaemonTokenStore: Sendable {
    public let tokenURL: URL

    public init(tokenURL: URL) {
        self.tokenURL = tokenURL
    }

    public func loadOrCreateToken() throws -> String {
        if let token = try loadToken() {
            return token
        }

        let token = UUID().uuidString + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: tokenURL.path
        )
        return token
    }

    public func loadToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return nil
        }
        return try String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
