import AppKit
import CoreGraphics
import Observation

struct Display: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isEnabled: Bool
    let isBuiltin: Bool
    let isMain: Bool
    let isMirrored: Bool
    let resolution: String?
}

@MainActor @Observable final class DisplayStore {
    private(set) var displays: [Display] = []
    private(set) var errorMessage: String?

    private let skyLight: SkyLightDisplays?
    private let defaults = UserDefaults.standard
    private static let cacheKey = "knownDisplays"
    private static let disabledKey = "disabledDisplays"

    /// A disabled display disappears from `NSScreen` and loses its UUID, so the name
    /// seen while it was online is remembered here, keyed by display ID.
    private struct Known: Codable { var name: String; var isBuiltin: Bool }
    private var known: [CGDirectDisplayID: Known]

    /// SkyLight also reports empty slots (no vendor, no UUID) that are indistinguishable
    /// from a disabled monitor, so only offline displays this app disabled are listed.
    private var disabledByApp: Set<CGDirectDisplayID> {
        didSet { defaults.set(disabledByApp.map(Int.init), forKey: Self.disabledKey) }
    }

    init() {
        do { skyLight = try SkyLightDisplays() } catch { skyLight = nil; errorMessage = error.localizedDescription }
        if let data = defaults.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([CGDirectDisplayID: Known].self, from: data) {
            known = decoded
        } else {
            known = [:]
        }
        disabledByApp = Set((defaults.array(forKey: Self.disabledKey) as? [Int] ?? []).map(CGDirectDisplayID.init))
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(prune: true) }
        }
        refresh(prune: true)
    }

    var onlineCount: Int { displays.filter(\.isEnabled).count }
    var hasDisabledDisplays: Bool { displays.contains { !$0.isEnabled } }

    /// `prune` drops tracked displays that are back online. It must be off right after this
    /// app's own toggle: `CGDisplayIsOnline` lags the commit, so a just-disabled display
    /// still reads as online and would be forgotten.
    func refresh(prune: Bool = false) {
        let screens = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        }, uniquingKeysWith: { first, _ in first })

        let ids: [CGDirectDisplayID]
        if let skyLight, let all = try? skyLight.displayIDs() {
            ids = all
        } else {
            ids = Array(screens.keys)
        }

        let isOnline = { (id: CGDirectDisplayID) in CGDisplayIsOnline(id) != 0 && CGDisplayIsActive(id) != 0 }
        let onlineIDs = Set(ids.filter(isOnline))
        if prune, !disabledByApp.isDisjoint(with: onlineIDs) { disabledByApp.subtract(onlineIDs) }

        var updatedCache = false
        displays = ids.filter { onlineIDs.contains($0) || disabledByApp.contains($0) }.map { id in
            let online = onlineIDs.contains(id)
            if let screen = screens[id] {
                let entry = Known(name: screen.localizedName, isBuiltin: CGDisplayIsBuiltin(id) != 0)
                if known[id]?.name != entry.name || known[id]?.isBuiltin != entry.isBuiltin {
                    known[id] = entry; updatedCache = true
                }
            }
            let entry = known[id]
            var resolution: String?
            if online, let mode = CGDisplayCopyDisplayMode(id) {
                resolution = "\(mode.width) × \(mode.height)"
            }
            return Display(id: id,
                           name: entry?.name ?? "Display \(id)",
                           isEnabled: online,
                           isBuiltin: entry?.isBuiltin ?? (CGDisplayIsBuiltin(id) != 0),
                           isMain: online && id == CGMainDisplayID(),
                           isMirrored: online && CGDisplayIsInMirrorSet(id) != 0,
                           resolution: resolution)
        }
        .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }

        if updatedCache, let data = try? JSONEncoder().encode(known) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    func canDisable(_ display: Display) -> Bool {
        skyLight != nil && display.isEnabled && onlineCount > 1 && !displays.contains(where: \.isMirrored)
    }

    func setEnabled(_ enabled: Bool, for display: Display) {
        errorMessage = nil
        do {
            guard let skyLight else { throw DisplayError.unsupported }
            if !enabled {
                guard onlineCount > 1 else { throw DisplayError.lastDisplay }
                guard !displays.contains(where: \.isMirrored) else { throw DisplayError.mirrored }
            }
            try skyLight.setEnabled(enabled, display: display.id)
            if enabled { disabledByApp.remove(display.id) } else { disabledByApp.insert(display.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func enableAll() {
        errorMessage = nil
        guard let skyLight else { errorMessage = DisplayError.unsupported.localizedDescription; return }
        var failure: Error?
        for display in displays where !display.isEnabled {
            // One unplugged display must not prevent recovery of the others.
            do {
                try skyLight.setEnabled(true, display: display.id)
                disabledByApp.remove(display.id)
            } catch { failure = error }
        }
        if let failure { errorMessage = failure.localizedDescription }
        refresh()
    }
}
