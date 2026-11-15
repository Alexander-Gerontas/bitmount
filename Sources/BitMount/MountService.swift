import Foundation
import BitMountCore

enum PrivilegedMount {
    static let ownHelper = "/usr/local/sbin/bitmount-helper"
    static let sudoersRule = "/etc/sudoers.d/bitmount"
    static let versionMarker = "bitmount-helper 1"

    /// True when anything BitMount installed as root is still on this Mac, even an older helper.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: ownHelper) || FileManager.default.fileExists(atPath: sudoersRule)
    }

    /// True when the installed helper is the one this version of the app expects.
    static var ownHelperIsCurrent: Bool {
        (try? String(contentsOfFile: ownHelper, encoding: .utf8))?.contains(versionMarker) == true
    }
}

enum MacAuthPrompt {
    static var approvalDialog: String {
        String(
            localized: "BitMount needs your approval once. After that, mounting asks only for the BitLocker password.",
            bundle: .module
        )
    }

    static var removalDialog: String {
        String(
            localized: "BitMount will remove its mount helper. The next unlock will ask for your approval again.",
            bundle: .module
        )
    }

    static func caption(approved: Bool) -> String {
        if approved {
            return String(localized: "Mounting asks only for the BitLocker password.", bundle: .module)
        }
        return String(
            localized: "The first unlock asks you to approve BitMount once. After that, only the BitLocker password is needed.",
            bundle: .module
        )
    }
}

enum MountService {
    static func mount(
        volume: WindowsVolume,
        passphrase: String?,
        readOnly: Bool,
        enginePath: String
    ) async -> ProcessRunner.Result {
        guard let device = DevicePath.normalize(volume.id) else {
            return ProcessRunner.Result(status: 2, stdout: "", stderr: "Invalid device", timedOut: false)
        }
        _ = await ProcessRunner.run(executable: enginePath, arguments: ["stop", "-f", device], timeout: 20)
        let secret = Data((passphrase ?? "").utf8)
        if await ownHelperReady() {
            return await mountWithOwnHelper(device: device, readOnly: readOnly, remount: volume.mountPoint != nil, secret: secret)
        }
        if let failure = await installOwnHelper() {
            return failure
        }
        return await mountWithOwnHelper(device: device, readOnly: readOnly, remount: volume.mountPoint != nil, secret: secret)
    }

    static func unmount(deviceID: String, enginePath: String) async -> ProcessRunner.Result {
        guard let device = DevicePath.normalize(deviceID) else {
            return ProcessRunner.Result(status: 2, stdout: "", stderr: "Invalid device", timedOut: false)
        }
        let plain = await ProcessRunner.run(executable: enginePath, arguments: ["unmount", device], timeout: 60)
        if plain.status == 0 { return plain }
        if await ownHelperReady() {
            let quiet = await ProcessRunner.run(
                executable: "/usr/bin/sudo",
                arguments: ["-n", "--", PrivilegedMount.ownHelper, "unmount", device],
                timeout: 60
            )
            if quiet.status == 0 { return quiet }
        }
        let stopped = await ProcessRunner.run(executable: enginePath, arguments: ["stop", "-f", device], timeout: 20)
        return stopped.status == 0 ? stopped : plain
    }

    static func mountPoint(deviceID: String, enginePath: String) async -> ParsedMount? {
        let status = await ProcessRunner.run(executable: enginePath, arguments: ["status"])
        return StatusParser.parse(status.stdout + "\n" + status.stderr).first { $0.deviceID == deviceID }
    }

    private static func mountWithOwnHelper(device: String, readOnly: Bool, remount: Bool, secret: Data) async -> ProcessRunner.Result {
        await ProcessRunner.run(
            executable: "/usr/bin/sudo",
            arguments: [
                "-n", "--", PrivilegedMount.ownHelper, "mount", device,
                readOnly ? "ro" : "rw",
                remount ? "yes" : "no",
            ],
            stdin: secret,
            timeout: 300
        )
    }

    private static func ownHelperReady() async -> Bool {
        guard PrivilegedMount.ownHelperIsCurrent else { return false }
        let ping = await ProcessRunner.run(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "--", PrivilegedMount.ownHelper, "ping"],
            timeout: 15
        )
        return ping.status == 0
    }

    /// Removes the root-owned helper and its sudoers rule. Paths are fixed; nothing else is touched.
    static func uninstallHelper() async -> ProcessRunner.Result {
        await runAsRoot(
            script: """
            #!/bin/bash
            set -euo pipefail
            rm -f \(PrivilegedMount.ownHelper) \(PrivilegedMount.sudoersRule)
            """,
            scriptName: "uninstall.sh",
            arguments: [],
            prompt: MacAuthPrompt.removalDialog,
            timeout: 180
        )
    }

    private static func installOwnHelper() async -> ProcessRunner.Result? {
        let installed = await runAsRoot(
            script: installScript,
            scriptName: "install.sh",
            arguments: [NSUserName()],
            prompt: MacAuthPrompt.approvalDialog,
            timeout: 180
        )
        if installed.status != 0 { return installed }
        if await ownHelperReady() { return nil }
        return ProcessRunner.Result(status: 1, stdout: "", stderr: installed.combined, timedOut: false)
    }

    private static var helperScript: String {
        """
        #!/bin/bash
        # \(PrivilegedMount.versionMarker)
        # Root-owned. sudoers grants NOPASSWD for this path only.
        set -euo pipefail

        cmd="${1:-}"
        if [[ "$cmd" == "ping" ]]; then
          exit 0
        fi

        device="${2:-}"
        if [[ ! "$device" =~ ^/dev/disk[0-9]+(s[0-9]+)*$ ]]; then
          echo "Invalid device" >&2
          exit 2
        fi
        if [[ "${SUDO_UID:-}" == "" || "${SUDO_GID:-}" == "" ]]; then
          echo "anylinuxfs must be started with sudo" >&2
          exit 1
        fi
        if [[ "${SUDO_USER:-}" =~ ^[A-Za-z0-9._-]+$ && -d "/Users/$SUDO_USER" ]]; then
          if [[ "${HOME:-}" != /Users/* || "$HOME" == *".."* ]]; then
            export HOME="/Users/$SUDO_USER"
          fi
        fi

        engine=""
        for candidate in /opt/homebrew/bin/anylinuxfs /usr/local/bin/anylinuxfs; do
          if [[ -x "$candidate" ]]; then
            engine="$candidate"
            break
          fi
        done
        if [[ -z "$engine" ]]; then
          echo "anylinuxfs is not installed" >&2
          exit 127
        fi

        if [[ "$cmd" == "unmount" ]]; then
          exec "$engine" unmount "$device"
        fi
        if [[ "$cmd" == "stop" ]]; then
          exec "$engine" stop -f "$device"
        fi
        if [[ "$cmd" != "mount" ]]; then
          echo "Invalid command" >&2
          exit 2
        fi

        mode="${3:-rw}"
        remount="${4:-no}"
        if [[ "$mode" != "ro" && "$mode" != "rw" ]]; then
          echo "Invalid mode" >&2
          exit 2
        fi
        if [[ "$remount" != "yes" && "$remount" != "no" ]]; then
          echo "Invalid remount flag" >&2
          exit 2
        fi

        IFS= read -r ALFS_PASSPHRASE || true
        if [[ -n "${ALFS_PASSPHRASE}" ]]; then
          export ALFS_PASSPHRASE
        fi

        # vmnet can fail the NFS port check after BitLocker is open, and anylinuxfs
        # then waits forever. gvproxy uses loopback. One retry disables vmnet offloading.
        stop_engine() {
          /usr/bin/sudo -n -u "#${SUDO_UID}" -H -- "$engine" stop -f "$device" >/dev/null 2>&1 || true
        }

        attempt() {
          nethelper="$1"
          umask 077
          logfile=$(mktemp "${TMPDIR:-/tmp}/bitmount-anylinuxfs.XXXXXX")
          mountcmd=("$engine" mount -w false --net-helper "$nethelper")
          if [[ "$nethelper" == "vmnet" ]]; then
            mountcmd+=(--vmnet-offloading disabled)
          fi
          if [[ "$mode" == "ro" ]]; then
            mountcmd+=(-o ro)
          fi
          if [[ "$remount" == "yes" ]]; then
            mountcmd+=(--remount)
          fi
          mountcmd+=("$device")

          "${mountcmd[@]}" >"$logfile" 2>&1 &
          pid=$!
          i=0
          while [[ "$i" -lt 120 ]]; do
            if ! kill -0 "$pid" 2>/dev/null; then
              if wait "$pid"; then
                status=0
              else
                status=$?
              fi
              cat "$logfile" >&2
              rm -f "$logfile"
              return "$status"
            fi
            # A wrong password also ends in "NFS server not ready". Check it first:
            # 65 stops here, 75 asks for a retry with the other network helper.
            failure=""
            if grep -q "No key available" "$logfile"; then
              failure=65
            elif grep -q "NFS server not ready" "$logfile"; then
              failure=75
            fi
            if [[ -n "$failure" ]]; then
              kill "$pid" 2>/dev/null || true
              stop_engine
              sleep 1
              stop_engine
              wait "$pid" 2>/dev/null || true
              cat "$logfile" >&2
              rm -f "$logfile"
              return "$failure"
            fi
            i=$((i + 1))
            sleep 1
          done
          echo "Mount timed out" >&2
          kill "$pid" 2>/dev/null || true
          stop_engine
          wait "$pid" 2>/dev/null || true
          cat "$logfile" >&2
          rm -f "$logfile"
          return 75
        }

        if attempt gvproxy; then
          exit 0
        else
          first=$?
        fi
        if [[ "$first" != "75" ]]; then
          exit "$first"
        fi
        echo "Retrying the mount with vmnet offloading disabled" >&2
        if attempt vmnet; then
          exit 0
        else
          exit $?
        fi
        """
    }

    private static var installScript: String {
        let helper = helperScript
        return """
        #!/bin/bash
        set -euo pipefail
        user="$1"
        if [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]; then
          echo "Invalid user" >&2
          exit 2
        fi
        umask 077
        tmphelper=$(mktemp)
        cat > "$tmphelper" << 'ENDHELPER'
        \(helper)
        ENDHELPER
        /usr/bin/install -d -o root -g wheel -m 755 /usr/local/sbin
        /usr/bin/install -o root -g wheel -m 755 "$tmphelper" \(PrivilegedMount.ownHelper)
        rm -f "$tmphelper"
        fragment=$(mktemp)
        printf '%s\\n' "$user ALL=(root) NOPASSWD: \(PrivilegedMount.ownHelper)" > "$fragment"
        /usr/sbin/visudo -c -f "$fragment"
        /usr/bin/install -o root -g wheel -m 440 "$fragment" \(PrivilegedMount.sudoersRule)
        rm -f "$fragment"
        """
    }

    private static func runAsRoot(
        script: String,
        scriptName: String,
        arguments: [String],
        prompt: String,
        timeout: TimeInterval
    ) async -> ProcessRunner.Result {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bitmount-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return ProcessRunner.Result(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }
        defer { try? fileManager.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent(scriptName)
        do {
            try Data(script.utf8).write(to: scriptURL)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            return ProcessRunner.Result(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        // The standard macOS authorization dialog. It offers Touch ID where the Mac has it,
        // which a password box of our own cannot do.
        let source = AppleScript.privilegedCommand(
            argv: ["/bin/bash", scriptURL.path] + arguments,
            prompt: prompt
        )
        return await ProcessRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", source],
            timeout: timeout
        )
    }
}
