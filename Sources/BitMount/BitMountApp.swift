import AppKit
import BitMountCore
import SwiftUI

@main
struct BitMountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        BundleRelauncher.relaunchIfNeeded()
        NSApplication.shared.setActivationPolicy(.regular)
        // Started here and not from a view: after a launch at login there is no window.
        let model = AppModel()
        model.startMonitoring()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandMenu(Text("Drive", bundle: .module)) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Text("Refresh", bundle: .module)
                }
                .keyboardShortcut("r")
                .disabled(model.busyVolumeID != nil)
            }
        }

        MenuBarExtra {
            MenuBarDrives()
                .environment(model)
        } label: {
            Image(systemName: model.mounts.isEmpty ? "externaldrive" : "externaldrive.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.launchedAsLoginItem {
            // Menu bar only. "Open BitMount" brings back the window and the Dock icon.
            NSApp.setActivationPolicy(.accessory)
            for window in NSApp.windows where window.canBecomeMain {
                window.close()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// macOS marks the launch event when it opens the app as a login item. Valid only during launch.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
