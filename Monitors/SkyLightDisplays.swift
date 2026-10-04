import CoreGraphics
import Darwin
import Foundation

/// Wraps the private SkyLight calls used to soft-disconnect a display.
/// Resolved at runtime: a missing symbol produces an error instead of a crash.
@MainActor final class SkyLightDisplays {
    private typealias Enable = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError
    private typealias List = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>) -> CGError

    private let handle: UnsafeMutableRawPointer
    private let enable: Enable
    private let list: List

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            throw DisplayError.unsupported
        }
        guard let enable = dlsym(handle, "SLSConfigureDisplayEnabled"), let list = dlsym(handle, "SLSGetDisplayList") else {
            dlclose(handle)
            throw DisplayError.unsupported
        }
        self.handle = handle
        self.enable = unsafeBitCast(enable, to: Enable.self)
        self.list = unsafeBitCast(list, to: List.self)
    }

    /// Every display WindowServer knows about, including ones that are currently disabled
    /// (those are missing from `CGGetOnlineDisplayList` and `NSScreen.screens`).
    func displayIDs() throws -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 128), count: UInt32 = 0
        let error = list(UInt32(ids.count), &ids, &count)
        guard error == .success, count < ids.count else { throw DisplayError.coreGraphics("List displays", error) }
        return Array(ids.prefix(Int(count)))
    }

    /// One display per transaction: batching several toggles can be rejected by
    /// WindowServer with illegalArgument (1001).
    func setEnabled(_ enabled: Bool, display id: CGDirectDisplayID) throws {
        var configuration: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&configuration)
        guard begin == .success, let configuration else { throw DisplayError.coreGraphics("Begin display configuration", begin) }
        let error = enable(configuration, id, enabled)
        guard error == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DisplayError.coreGraphics("Set display \(id) enabled=\(enabled)", error)
        }
        let commit = CGCompleteDisplayConfiguration(configuration, .permanently)
        guard commit == .success else { throw DisplayError.coreGraphics("Commit display configuration", commit) }
    }
}

enum DisplayError: LocalizedError {
    case unsupported
    case lastDisplay
    case mirrored
    case coreGraphics(String, CGError)

    var errorDescription: String? {
        switch self {
        case .unsupported: "This version of macOS does not expose the display enable API."
        case .lastDisplay: "At least one display must stay enabled."
        case .mirrored: "Turn off display mirroring before disabling a display."
        case let .coreGraphics(operation, error): "\(operation) failed (Core Graphics error \(error.rawValue))."
        }
    }
}
