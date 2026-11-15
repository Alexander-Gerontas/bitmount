import AppKit
import Foundation

enum BundleRelauncher {
    /// `swift run` starts a bare executable. macOS keeps that in the background, so no window appears.
    /// Wrap it in an app bundle and open that instead.
    static func relaunchIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        guard let executable = Bundle.main.executableURL else { return }

        let fileManager = FileManager.default
        let root = packageRoot()
        let app = root.appendingPathComponent("build/BitMount.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)

        // `open` only brings an already running copy to the front, so the new build would never start.
        quitRunningCopies(bundleIdentifier: "io.github.alexander-gerontas.BitMount")

        do {
            if fileManager.fileExists(atPath: app.path) {
                try fileManager.removeItem(at: app)
            }
            try fileManager.createDirectory(at: macos, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
            try fileManager.copyItem(at: executable, to: macos.appendingPathComponent("BitMount"))

            if let plist = Bundle.module.url(forResource: "AppInfo", withExtension: "plist") {
                try fileManager.copyItem(at: plist, to: contents.appendingPathComponent("Info.plist"))
            }

            let icon = root.appendingPathComponent("Assets/AppIcon.icns")
            if fileManager.fileExists(atPath: icon.path) {
                try fileManager.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
            }

            let siblingBundle = executable
                .deletingLastPathComponent()
                .appendingPathComponent("BitMount_BitMount.bundle")
            if fileManager.fileExists(atPath: siblingBundle.path) {
                try fileManager.copyItem(
                    at: siblingBundle,
                    to: resources.appendingPathComponent("BitMount_BitMount.bundle")
                )
            }

            try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
            fputs("Opening BitMount…\n", stderr)
            try run("/usr/bin/open", [app.path])
        } catch {
            fputs("Could not open BitMount: \(error.localizedDescription)\n", stderr)
        }
        exit(0)
    }

    private static func quitRunningCopies(bundleIdentifier: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps { app.terminate() }
        for _ in 0..<30 where apps.contains(where: { !$0.isTerminated }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        for app in apps where !app.isTerminated { app.forceTerminate() }
    }

    private static func packageRoot() -> URL {
        let fileManager = FileManager.default
        var starts = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]
        if let executable = Bundle.main.executableURL {
            starts.append(executable.deletingLastPathComponent())
        }
        for start in starts {
            var url = start
            for _ in 0..<8 {
                if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                    return url
                }
                let parent = url.deletingLastPathComponent()
                if parent == url { break }
                url = parent
            }
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CocoaError(.executableLoad)
        }
    }
}
