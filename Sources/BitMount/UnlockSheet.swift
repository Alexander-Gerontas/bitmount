import BitMountCore
import SwiftUI

struct UnlockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var volume: WindowsVolume

    @State private var kind: SecretKind = .password
    @State private var password = ""
    @State private var recovery = ""
    @State private var reveal = false
    @State private var remember = false
    @State private var readOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Unlock", bundle: .module)
                    .font(.title2.weight(.semibold))
                Text(volume.name.isEmpty ? String(localized: "Windows volume", bundle: .module) : volume.name)
                    .foregroundStyle(.secondary)
            }

            Picker(String(localized: "Credential", bundle: .module), selection: $kind) {
                Text("Password", bundle: .module).tag(SecretKind.password)
                Text("Recovery key", bundle: .module).tag(SecretKind.recovery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if kind == .password {
                HStack {
                    Group {
                        if reveal {
                            TextField(String(localized: "Volume password", bundle: .module), text: $password)
                        } else {
                            SecureField(String(localized: "Volume password", bundle: .module), text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(reveal ? String(localized: "Hide password", bundle: .module) : String(localized: "Show password", bundle: .module)) {
                        reveal.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            } else {
                TextField("000000-000000-000000-000000-000000-000000-000000-000000", text: $recovery)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onChange(of: recovery) { _, newValue in
                        let formatted = SecretFormat.grouped(String(SecretFormat.digits(from: newValue).prefix(48)))
                        if formatted != newValue { recovery = formatted }
                    }
                HStack {
                    Text("48 digits, with or without dashes.", bundle: .module)
                    Spacer()
                    Text("\(SecretFormat.digits(from: recovery).count)/48")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let notice = model.notice, notice.volumeID == volume.id, notice.kind == .wrongSecret {
                Label {
                    Text("Wrong password or recovery key.", bundle: .module)
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Toggle(isOn: $remember) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save password on this Mac", bundle: .module)
                    Text("The password stays in the Keychain on this Mac. It is not written to the drive.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $readOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read only", bundle: .module)
                    Text("Files stay as they are. Leave this off to copy files onto the drive.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Text(MacAuthPrompt.caption(approved: model.helperApproved))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Unlock", bundle: .module)) {
                    let secret = SavedSecret(kind: kind, secret: kind == .password ? password : recovery)
                    Task {
                        await model.unlock(volume: volume, secret: secret, remember: remember, readOnly: readOnly)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.busyVolumeID != nil)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var canSubmit: Bool {
        switch kind {
        case .password:
            !password.isEmpty
        case .recovery:
            SecretFormat.isCompleteRecovery(recovery)
        }
    }
}
