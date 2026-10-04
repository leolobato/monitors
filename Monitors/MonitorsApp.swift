import ServiceManagement
import SwiftUI

@main
struct MonitorsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Monitors", systemImage: "display.2") {
            MonitorsMenu(store: appDelegate.store)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the store so displays this app disabled are turned back on when it quits.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DisplayStore()
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill`/`pkill` sends SIGTERM, which skips `applicationWillTerminate` unless routed through it.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }
        source.resume()
        termination = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.enableAll()
    }
}

struct MonitorsMenu: View {
    let store: DisplayStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section("Displays") {
            ForEach(store.displays) { display in
                Toggle(isOn: Binding(get: { display.isEnabled },
                                     set: { store.setEnabled($0, for: display) })) {
                    Text(title(for: display))
                    if let subtitle = subtitle(for: display) { Text(subtitle) }
                }
                .disabled(display.isEnabled && !store.canDisable(display))
            }
        }
        if let error = store.errorMessage {
            Divider()
            Text(error)
        }
        Divider()
        Button("Enable All Displays") { store.enableAll() }
        Button("Refresh") { store.refresh(prune: true) }
            .keyboardShortcut("r")
        Divider()
        Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
        Button("Quit Monitors") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(for display: Display) -> String {
        display.isMain ? "\(display.name) (main)" : display.name
    }

    private func subtitle(for display: Display) -> String? {
        guard display.isEnabled else { return "Disabled" }
        return [display.resolution, display.isBuiltin ? "Built-in" : nil, display.isMirrored ? "Mirrored" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
