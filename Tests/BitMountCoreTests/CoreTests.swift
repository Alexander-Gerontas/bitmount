import XCTest
@testable import BitMountCore

final class CoreTests: XCTestCase {
    func testRecoveryKeyGrouping() {
        XCTAssertEqual(SecretFormat.grouped("123456789012"), "123456-789012")
        XCTAssertEqual(SecretFormat.digits(from: "111111-222222"), "111111222222")
        XCTAssertFalse(SecretFormat.isCompleteRecovery("123"))
        let digits = String(repeating: "1", count: 48)
        XCTAssertTrue(SecretFormat.isCompleteRecovery(SecretFormat.grouped(digits)))
        XCTAssertEqual(SecretFormat.grouped(digits).filter(\.isNumber).count, 48)
    }

    func testSavedSecretUsesDashedRecoveryKey() {
        let saved = SavedSecret(kind: .recovery, secret: String(repeating: "2", count: 48))
        XCTAssertEqual(saved.passphrase, SecretFormat.grouped(String(repeating: "2", count: 48)))
        let password = SavedSecret(kind: .password, secret: "p@ss word")
        XCTAssertEqual(password.passphrase, "p@ss word")
    }

    func testDevicePath() {
        XCTAssertEqual(DevicePath.normalize("disk4s2"), "/dev/disk4s2")
        XCTAssertEqual(DevicePath.normalize("disk10"), "/dev/disk10")
        XCTAssertNil(DevicePath.normalize("/dev/disk4s2"))
        XCTAssertNil(DevicePath.normalize("disk4s2;rm"))
        XCTAssertNil(DevicePath.normalize("disk"))
    }

    func testAppleScriptQuotesPrompt() {
        let source = AppleScript.privilegedCommand(
            argv: ["/bin/bash", "/tmp/my script.sh"],
            prompt: "Say \"hi\""
        )
        XCTAssertTrue(source.contains("with administrator privileges"))
        XCTAssertTrue(source.contains("quoted form of \"/bin/bash\""))
        XCTAssertTrue(source.contains("Say \\\"hi\\\""))
        XCTAssertFalse(source.contains("Say \"hi\""))
    }

    func testStatusParserKeepsSpacesInMountPoint() {
        let text = """
        /dev/disk9s3 on /Volumes/My Disk (ntfs, uid=501, gid=20, mounted by alex) VM[cpus: 2, ram: 512 MiB]

        /dev/disk2s1 on /Volumes/WIN (exfat, uid=501, gid=20, mounted by alex)
        not a mount
        """
        let mounts = StatusParser.parse(text)
        XCTAssertEqual(mounts.count, 2)
        XCTAssertEqual(mounts[0].deviceID, "disk9s3")
        XCTAssertEqual(mounts[0].mountPoint, "/Volumes/My Disk")
        XCTAssertEqual(mounts[0].filesystem, "ntfs")
        XCTAssertEqual(mounts[1].filesystem, "exfat")
    }

    func testFailureClassifierPrefersAdminPasswordOverBitLocker() {
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "The administrator password was incorrect.", timedOut: false),
            .adminRejected
        )
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "User canceled.", timedOut: false),
            .canceled
        )
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "No key available with this passphrase.", timedOut: false),
            .wrongSecret
        )
        let realLog = """
        Linux: No key available with this passphrase.
        Linux: Sent report to vmctrl client
        Linux: Error: Failed to open encrypted device '/dev/vda': 2
        macOS: NFS server not ready
        macOS: libkrun VM exited with status: 1
        macOS: vmnet-helper exited with status: 0
        """
        XCTAssertEqual(FailureClassifier.classify(status: 0, output: realLog, timedOut: false), .wrongSecret)
        XCTAssertEqual(FailureClassifier.classify(status: 1, output: realLog + "\nNo such file or directory", timedOut: false), .wrongSecret)
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "sudo: 3 incorrect password attempts", timedOut: false),
            .adminRejected
        )
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "sudo: no password was provided", timedOut: false),
            .canceled
        )
        XCTAssertEqual(
            FailureClassifier.classify(status: 1, output: "boom", timedOut: true),
            .timedOut
        )
    }

    func testAutoMountQueueReturnsVolumesOnlyWhenTheyAppear() {
        var queue = AutoMountQueue()
        let all: (String) -> Bool = { _ in true }

        // First scan: everything connected counts as just arrived.
        queue.record(connected: ["a", "b"])
        XCTAssertEqual(queue.drain(where: all), ["a", "b"])

        // Still connected, for example after a manual eject: nothing to do.
        queue.record(connected: ["a", "b"])
        XCTAssertEqual(queue.drain(where: all), [])

        // Unplugged and plugged back in.
        queue.record(connected: ["b"])
        queue.record(connected: ["a", "b"])
        XCTAssertEqual(queue.drain(where: all), ["a"])
    }

    func testAutoMountQueueKeepsArrivalsUntilDrainedAndDropsTheRest() {
        var queue = AutoMountQueue()

        // Several scans can pass before a drain, for example while another drive is unlocking.
        queue.record(connected: ["a"])
        queue.record(connected: ["a", "b"])
        queue.record(connected: ["b", "c"])
        XCTAssertEqual(queue.drain(where: { $0 != "c" }), ["b"])

        // "c" was not eligible at arrival and does not come back while it stays connected.
        queue.record(connected: ["b", "c"])
        XCTAssertEqual(queue.drain(where: { _ in true }), [])
    }

    func testScrubRemovesSecret() {
        let cleaned = FailureClassifier.scrub("failed for secret-value", secret: "secret-value")
        XCTAssertFalse(cleaned.contains("secret-value"))
    }

    func testInventoryKeepsWindowsPartitionsOfExternalDisks() {
        let basicData = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
        let efi = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
        let records = [
            // Out of order on purpose: the system does not list them sorted.
            MediaRecord(id: "disk10s1", isWhole: false, content: "Windows_NTFS", size: 900),
            MediaRecord(id: "disk4s2", isWhole: false, content: basicData, size: 800, uuid: "AAA-BBB"),
            MediaRecord(id: "disk4s1", isWhole: false, content: efi, size: 100),
            MediaRecord(id: "disk4", isWhole: true, content: "GUID_partition_scheme", size: 1000, bus: "USB", model: "Samsung SSD"),
            MediaRecord(id: "disk0", isWhole: true, content: "GUID_partition_scheme", size: 500, isInternal: true, bus: "Apple Fabric"),
            MediaRecord(id: "disk0s2", isWhole: false, content: basicData, size: 400),
            MediaRecord(id: "disk5", isWhole: true, content: "GUID_partition_scheme", size: 2000, bus: "Virtual Interface"),
            MediaRecord(id: "disk5s1", isWhole: false, content: basicData, size: 2000),
            MediaRecord(id: "disk10", isWhole: true, content: "FDisk_partition_scheme", size: 1000, bus: "USB", model: "EXTERNAL_USB"),
            MediaRecord(
                id: "disk1s1", isWhole: false, content: "DOS_FAT_32", size: 300,
                volumeName: "STICK", isReadableByMac: true, mountPoint: "/Volumes/STICK"
            ),
            MediaRecord(id: "disk1", isWhole: true, content: "FDisk_partition_scheme", size: 300, bus: "USB"),
            // A container without a partition table, and a snapshot that is not a partition.
            MediaRecord(id: "disk3", isWhole: true, content: "EF57347C-0000-11AA-AA11-00306543ECAC", size: 700),
            MediaRecord(id: "disk4s2s1", isWhole: false, content: basicData, size: 800),
        ]
        let disks = DiskInventory.disks(from: records)
        XCTAssertEqual(disks.map(\.id), ["disk1", "disk4", "disk10"])

        // disk10s1 belongs to disk10, not to disk1.
        XCTAssertEqual(disks[0].volumes.map(\.id), ["disk1s1"])
        XCTAssertTrue(disks[0].volumes[0].isReadableByMac)
        XCTAssertEqual(disks[0].volumes[0].name, "STICK")
        XCTAssertEqual(disks[0].volumes[0].mountPoint, "/Volumes/STICK")

        XCTAssertEqual(disks[1].name, "Samsung SSD")
        XCTAssertEqual(disks[1].bus, "USB")
        XCTAssertEqual(disks[1].volumes.map(\.id), ["disk4s2"])
        XCTAssertEqual(disks[1].volumes[0].content, "Microsoft Basic Data")
        XCTAssertEqual(disks[1].volumes[0].stableID, "gpt:AAA-BBB")
        XCTAssertFalse(disks[1].volumes[0].isReadableByMac)

        XCTAssertEqual(disks[2].volumes.map(\.id), ["disk10s1"])
        XCTAssertEqual(disks[2].volumes[0].stableID, "legacy:900:Windows_NTFS")
        XCTAssertEqual(disks[2].volumes[0].parentName, "EXTERNAL_USB")
    }
}
