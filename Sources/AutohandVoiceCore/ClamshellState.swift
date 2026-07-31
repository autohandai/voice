import Foundation
import IOKit

public protocol ClamshellStateChecking: Sendable {
    func isClamshellClosed() -> Bool
}

public struct SystemClamshellStateChecker: ClamshellStateChecking {
    public init() {}

    public func isClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else {
            return false
        }
        defer { IOObjectRelease(service) }

        return IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool ?? false
    }
}

public struct FixedClamshellStateChecker: ClamshellStateChecking {
    public let closed: Bool

    public init(closed: Bool) {
        self.closed = closed
    }

    public func isClamshellClosed() -> Bool {
        closed
    }
}
