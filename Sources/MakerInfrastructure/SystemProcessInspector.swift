import Darwin
import Foundation
import MakerApplication

public struct SystemProcessInspector: ProcessInspector {
    public init() {}

    public func isProcessRunning(pid: Int32) async -> Bool {
        guard pid > 0 else {
            return false
        }

        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}
