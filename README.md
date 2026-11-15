# BitMount

A native macOS app for opening BitLocker-encrypted drives, read-write, without a kernel extension.

BitMount does not implement BitLocker itself. It is a SwiftUI front end for [anylinuxfs](https://github.com/nohajc/anylinuxfs), which unlocks the drive inside a small Linux virtual machine and shares it back to macOS.

## Disclaimer

**Use at your own risk.**

BitMount is provided "as is", without warranty of any kind. The authors and contributors accept no responsibility or liability for any damage to any drive, or for lost, damaged or corrupted files, resulting from the use of this software.

Back up anything you cannot afford to lose before you mount a drive, especially in read-write mode.

## Status

Early. It has been tested by hand on one drive: a BitLocker volume with a password, NTFS, on macOS 27 with anylinuxfs 0.21.1. Unlocking read-write and automatic unlocking work there. Read-only mode, recovery keys and ejecting have had little or no real-world testing yet.

## Features

- Lists external Windows volumes and unlocks them with a password or a 48-digit recovery key.
- Mounts read-write by default, with a read-only option.
- Can save the password in the macOS Keychain, on this Mac only. Off by default.
- Can unlock a drive with a saved password as soon as you plug it in. Set per drive, off by default. BitMount has to be running. Settings has an option to open it at login, where it starts in the menu bar without a window.
- Menu bar item that lists your drives.
- English and Greek interface, following the system language.

## Requirements

- An Apple Silicon Mac. anylinuxfs does not run on Intel Macs.
- macOS 15 or later.
- [Homebrew](https://brew.sh) and anylinuxfs:

  ```bash
  brew tap nohajc/anylinuxfs
  brew trust nohajc/anylinuxfs
  brew install anylinuxfs
  anylinuxfs init
  ```

- To build from source: Xcode 16 or later, or the Command Line Tools with Swift 6.

## Download

Get `BitMount-<version>.zip` from the [latest release](https://github.com/Alexander-Gerontas/bitmount/releases/latest) and unzip it.

macOS blocks the first launch of a downloaded copy. To open it:

1. Move `BitMount.app` to Applications and open it once.
2. Open System Settings → Privacy & Security and choose **Open Anyway**.

You do this once for each version. An app you build yourself from source is not blocked.

## Build and run

Clone this repository, then:

```bash
swift run
```

This builds the app, wraps it in `build/BitMount.app` and opens it.

To produce a standalone app and a zip for sharing:

```bash
./scripts/build-app.sh
```

The result is `dist/BitMount.app` and `dist/BitMount-<version>.zip`.

To run the tests:

```bash
swift test
```

## What BitMount installs

anylinuxfs needs root to read the raw disk. The first time you unlock a drive, macOS asks for an administrator password once, and BitMount installs two files:

- `/usr/local/sbin/bitmount-helper`, a root-owned script that runs anylinuxfs for a validated `/dev/diskNsM` device.
- `/etc/sudoers.d/bitmount`, a rule that lets your user run that one script with `sudo` without a password.

After that, unlocking asks only for the BitLocker password.

The trade-off: any program running as your user can mount or unmount drives through that script without a password prompt. Unlocking an encrypted drive still needs its BitLocker password.

To remove both files, open Settings → Mac password → Remove, or run:

```bash
sudo rm -f /usr/local/sbin/bitmount-helper /etc/sudoers.d/bitmount
```

## Passwords

- The BitLocker password is passed to the mount script on standard input. It is not put in command-line arguments and is not written to a file.
- It is saved only if you tick "Save password on this Mac". It goes into your login Keychain, for this device only, and is not synced. You can remove it in Settings.

## Known limitations

- Eject the drive in BitMount before you unplug it.
- If Windows was hibernated or shut down with Fast Startup, NTFS may mount read-only. BitMount does not detect this yet and still shows the drive as writable.
- BitMount starts anylinuxfs with the gvproxy network helper. With the default vmnet helper, mounting hung on macOS 27.

## License

MIT. See [LICENSE](LICENSE).

anylinuxfs is a separate project under GPL-3.0. BitMount calls it and does not include it.
