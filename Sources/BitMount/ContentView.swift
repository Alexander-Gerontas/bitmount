import BitMountCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 560)
        .sheet(isPresented: unlockPresented) {
            // The sheet's own volume first: an automatic unlock can fail for a drive that is not selected.
            if let volume = volume(id: model.unlockSheetVolumeID) ?? model.selectedVolume {
                UnlockSheet(volume: volume)
                    .environment(model)
            }
        }
    }

    private var unlockPresented: Binding<Bool> {
        Binding(
            get: { model.unlockSheetVolumeID != nil },
            set: { if !$0 { model.unlockSheetVolumeID = nil } }
        )
    }

    private var sidebar: some View {
        List(selection: Bindable(model).selectedVolumeID) {
            if model.disks.isEmpty {
                Text("No drives yet", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.disks) { disk in
                    Section {
                        if disk.volumes.isEmpty {
                            Text("No Windows volume", bundle: .module)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(disk.volumes) { volume in
                                VolumeRow(
                                    volume: volume,
                                    mounted: model.mounts[volume.id] != nil,
                                    saved: model.savedKind(for: volume) != nil
                                )
                                .tag(volume.id)
                                .contextMenu {
                                    volumeMenu(volume)
                                }
                            }
                        }
                    } header: {
                        Text(diskTitle(disk))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BitMount")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Text("Refresh", bundle: .module))
                .disabled(model.busyVolumeID != nil)
            }
            ToolbarItem(placement: .automatic) {
                engineBadge
            }
        }
        .overlay {
            if !model.hasLoaded {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var detail: some View {
        Group {
            if let volume = model.selectedVolume {
                VolumeDetailView(volume: volume)
            } else if model.disks.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Connect a drive", bundle: .module)
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                } description: {
                    Text("Plug in a Windows USB drive or SSD. It shows up here, and you unlock it with the volume password or a 48-digit recovery key.", bundle: .module)
                }
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Select a volume", bundle: .module)
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                } description: {
                    Text("Choose a Windows volume from the sidebar.", bundle: .module)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var engineBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.engine.isReady && model.engine.rootfsReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.engine.version ?? String(localized: "Not installed", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func volumeMenu(_ volume: WindowsVolume) -> some View {
        if model.mounts[volume.id] != nil {
            Button(String(localized: "Eject", bundle: .module)) {
                Task { await model.eject(volume: volume) }
            }
        } else {
            Button(String(localized: "Unlock", bundle: .module)) {
                model.selectedVolumeID = volume.id
                if model.savedKind(for: volume) != nil {
                    Task { await model.unlock(volume: volume, secret: nil, remember: false, readOnly: false) }
                } else {
                    model.unlockSheetVolumeID = volume.id
                }
            }
        }
        if model.savedKind(for: volume) != nil {
            Button(String(localized: "Remove saved password", bundle: .module)) {
                model.forget(account: volume.stableID)
            }
        }
    }

    private func volume(id: String?) -> WindowsVolume? {
        guard let id else { return nil }
        return model.disks.flatMap(\.volumes).first { $0.id == id }
    }

    private func diskTitle(_ disk: ExternalDisk) -> String {
        let name = disk.name.isEmpty ? String(localized: "External drive", bundle: .module) : disk.name
        return "\(name) · \(Format.bytes(disk.size))"
    }
}

struct VolumeRow: View {
    var volume: WindowsVolume
    var mounted: Bool
    var saved: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name.isEmpty ? String(localized: "Windows volume", bundle: .module) : volume.name)
                    .lineLimit(1)
                Text(Format.bytes(volume.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        if mounted { return "checkmark.circle.fill" }
        if saved { return "key.horizontal.fill" }
        if volume.isReadableByMac { return "externaldrive.fill" }
        return "lock.fill"
    }

    private var color: Color {
        if mounted { return .green }
        if volume.isReadableByMac { return .secondary }
        return .orange
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bus(_ raw: String) -> String {
        switch raw {
        case "Secure Digital":
            String(localized: "SD Card", bundle: .module)
        case "Disk Image":
            String(localized: "Disk Image", bundle: .module)
        case "":
            String(localized: "External", bundle: .module)
        default:
            raw
        }
    }
}
