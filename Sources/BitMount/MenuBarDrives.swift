import AppKit
import BitMountCore
import SwiftUI

struct MenuBarDrives: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if volumes.isEmpty {
                Text("No drives yet", bundle: .module)
            } else {
                ForEach(model.disks) { disk in
                    if !disk.volumes.isEmpty {
                        Section(diskTitle(disk)) {
                            ForEach(disk.volumes) { volume in
                                Button {
                                    open(volume)
                                } label: {
                                    Label(volumeTitle(volume), systemImage: symbol(for: volume))
                                }
                                .disabled(model.busyVolumeID != nil)
                            }
                        }
                    }
                }
            }
        }

        Divider()

        Button(String(localized: "Open BitMount", bundle: .module)) {
            showWindow()
        }

        Divider()

        Button(String(localized: "Quit BitMount", bundle: .module)) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var volumes: [WindowsVolume] {
        model.disks.flatMap(\.volumes)
    }

    private func open(_ volume: WindowsVolume) {
        model.selectedVolumeID = volume.id
        showWindow()
        if let mount = model.mounts[volume.id] {
            model.open(mount.mountPoint)
        } else if model.savedKind(for: volume) != nil {
            Task { await model.unlock(volume: volume, secret: nil, remember: false, readOnly: false) }
        } else {
            model.unlockSheetVolumeID = volume.id
        }
    }

    private func showWindow() {
        // After a launch at login the app is menu bar only. Give it its Dock icon back.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func symbol(for volume: WindowsVolume) -> String {
        if model.mounts[volume.id] != nil { return "checkmark.circle" }
        if model.savedKind(for: volume) != nil { return "key.horizontal" }
        if volume.isReadableByMac { return "externaldrive" }
        return "lock"
    }

    private func volumeTitle(_ volume: WindowsVolume) -> String {
        let name = volume.name.isEmpty ? String(localized: "Windows volume", bundle: .module) : volume.name
        return "\(name) · \(Format.bytes(volume.size))"
    }

    private func diskTitle(_ disk: ExternalDisk) -> String {
        disk.name.isEmpty ? String(localized: "External drive", bundle: .module) : disk.name
    }
}
