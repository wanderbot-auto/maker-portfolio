import Foundation

public enum MakerError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case missingResource(String)
    case processAlreadyRunning
    case processNotRunning
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        case let .missingResource(message):
            return "Missing resource: \(message)"
        case let .unsupported(message):
            return "Unsupported operation: \(message)"
        case .processAlreadyRunning:
            return "The runtime process is already running."
        case .processNotRunning:
            return "The runtime process is not running."
        }
    }
}
