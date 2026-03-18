import Foundation

public struct LogEvent: Sendable, Equatable, Codable {
    public enum Stream: String, Sendable, Codable {
        case stdout
        case stderr
        case system
    }

    public var timestamp: Date
    public var stream: Stream
    public var message: String

    public init(timestamp: Date = Date(), stream: Stream, message: String) {
        self.timestamp = timestamp
        self.stream = stream
        self.message = message
    }
}
