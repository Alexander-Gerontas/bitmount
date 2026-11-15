import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("openFinderAfterMount") private var openFinder = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemFailed = false

    var body: some View {
        Form {
            Toggle(isOn: $openFinder) {
                Text("Open in Finder after mounting", bundle: .module)
            }
            // A closure, not `set: setOpensAtLogin`: passing the method itself crashes the
            // compiler in Swift 6.1 and 6.3.
            Toggle(isOn: Binding(get: { opensAtLogin }, set: { setOpensAtLogin($0) })) {
                Text("Open BitMount at login", bundle: .module)
                Text("Drives set to unlock automatically need BitMount running.", bundle: .module)
            }
            if loginItemFailed {
                Text("macOS did not apply the change. Check System Settings → General → Login Items.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledContent(String(localized: "Engine", bundle: .module)) {
                Text(model.engine.version ?? String(localized: "Not installed", bundle: .module))
            }
            if let path = model.engine.path {
                LabeledContent(String(localized: "Path", bundle: .module)) {
                    Text(path).textSelection(.enabled)
                }
            }
            Section {
                if model.savedItems.isEmpty {
                    Text("No saved passwords yet.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.savedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                Text(item.kind == .recovery
                                     ? String(localized: "Recovery key", bundle: .module)
                                     : String(localized: "Password", bundle: .module))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(String(localized: "Remove", bundle: .module)) {
                                model.forget(account: item.account)
                            }
                        }
                    }
                }
                Text("Saved passwords stay in the macOS Keychain for this Mac only.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Saved passwords", bundle: .module)
            }
            Section {
                HStack {
                    Text(model.helperApproved
                         ? String(localized: "Approved. Mounting asks only for the BitLocker password.", bundle: .module)
                         : String(localized: "Not approved yet. The next unlock asks for your Mac password once.", bundle: .module))
                    Spacer()
                    if model.helperInstalled {
                        Button(String(localized: "Remove", bundle: .module)) {
                            Task { await model.removeHelper() }
                        }
                        .disabled(model.isRemovingHelper || model.busyVolumeID != nil || !model.mounts.isEmpty)
                    }
                }
                if model.helperInstalled {
                    Text(
                        "BitMount installed a mount helper at \(PrivilegedMount.ownHelper) and a rule at \(PrivilegedMount.sudoersRule). Removing them needs your Mac password.",
                        bundle: .module
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !model.mounts.isEmpty {
                        Text("Eject mounted drives before removing.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.helperRemovalFailed {
                    Text("The mount helper could not be removed.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Mac password", bundle: .module)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .padding()
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The status read below decides what is shown.
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
        loginItemFailed = opensAtLogin != enabled
    }
}
