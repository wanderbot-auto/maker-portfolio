import Foundation
import MakerDomain
import MakerSupport

public struct DefaultRuntimeAdapterFactory: RuntimeAdapterFactory {
    public init() {}

    public func makeAdapter(for profile: RuntimeProfile) -> any RuntimeAdapter {
        switch profile.adapterType {
        case .localProcess:
            return LocalProcessAdapter()
        case .androidEmulator, .iosSimulator, .macosVM:
            return UnsupportedRuntimeAdapter(adapterType: profile.adapterType)
        }
    }
}

public actor UnsupportedRuntimeAdapter: RuntimeAdapter {
    private let adapterType: RuntimeAdapterType

    public init(adapterType: RuntimeAdapterType) {
        self.adapterType = adapterType
    }

    public func prepare(project: Project, profile: RuntimeProfile, env: [String: String]) async throws {}

    public func start() async throws -> RuntimeExecutionHandle {
        throw MakerError.unsupported("Adapter \(adapterType.rawValue) is reserved for a future phase.")
    }

    public func stop() async throws {}

    public func restart() async throws -> RuntimeExecutionHandle {
        throw MakerError.unsupported("Adapter \(adapterType.rawValue) is reserved for a future phase.")
    }

    public func getStatus() async -> RuntimeProcessState {
        .idle
    }

    public nonisolated func streamLogs() -> AsyncThrowingStream<LogEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
