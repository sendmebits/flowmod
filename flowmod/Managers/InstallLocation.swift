import AppKit
import Darwin
import Foundation

/// Decides whether this launch is a real install, and copies the bundle into
/// Applications when it is not. Accessibility permission is tied to the path
/// macOS actually runs, so a copy opened from a disk image, Downloads, or an
/// App Translocation folder must not continue setup from that path.
nonisolated enum InstallLocation {
    static var needsRelocation: Bool {
        if isLocalDevelopmentLaunch { return false }
        return !isInstalledInApplications
    }

    /// Copies this bundle into Applications and clears the quarantine flag so
    /// the relaunch is not translocated back to a temporary path.
    static func moveToApplications() throws -> URL {
        let source = Bundle.main.bundleURL
        let applications = try applicationsDirectory()
        let destination = applications.appendingPathComponent(source.lastPathComponent)
        let fileManager = FileManager.default
        let staging = applications.appendingPathComponent(".FlowMod-install-\(UUID().uuidString).app")
        let backup = applications.appendingPathComponent(".FlowMod-install-backup-\(UUID().uuidString).app")

        do {
            try runCapturing("/usr/bin/ditto", [source.path, staging.path])
            try clearQuarantine(at: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        var backedUp = false
        if fileManager.fileExists(atPath: destination.path) {
            do {
                try fileManager.moveItem(at: destination, to: backup)
                backedUp = true
            } catch {
                try? fileManager.removeItem(at: staging)
                throw InstallLocationError.copyFailed("Quit any other copy of FlowMod, then try again.")
            }
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if backedUp {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            try? fileManager.removeItem(at: staging)
            throw InstallLocationError.copyFailed("FlowMod couldn't be placed in the Applications folder.")
        }

        try? fileManager.removeItem(at: backup)
        return destination
    }

    /// Quit this process, then open the installed copy. Opening it while this
    /// process is still running would reuse the same bundle identifier and
    /// leave the temporary copy in front.
    @MainActor
    static func relaunchInstalledCopy(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.6; exec /usr/bin/open \"$1\"",
            "flowmod-relauncher",
            url.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw InstallLocationError.copyFailed("FlowMod is in Applications, but it couldn't be reopened. Open it from the Applications folder.")
        }
        NSApp.terminate(nil)
    }

    /// Xcode and the local `build/Debug` run should not copy themselves into
    /// Applications. A debug build that was downloaded or opened from a disk
    /// image still has to move.
    private static var isLocalDevelopmentLaunch: Bool {
        if isDebuggerAttached { return true }
        let path = Bundle.main.bundleURL.standardizedFileURL.path.lowercased()
        if path.contains("/deriveddata/") { return true }
        if path.contains("/build/products/") { return true }
        if path.contains("/build/debug/") || path.contains("/build/release/") { return true }
        return false
    }

    private static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    private static var isInstalledInApplications: Bool {
        let parent = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return applicationDirectories().contains { directory in
            directory.resolvingSymlinksInPath().standardizedFileURL.path == parent.path
        }
    }

    private static func applicationDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    private static func applicationsDirectory() throws -> URL {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: systemApplications.path) {
            return systemApplications
        }

        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: userApplications, withIntermediateDirectories: true)
        } catch {
            throw InstallLocationError.applicationsNotWritable
        }
        guard FileManager.default.isWritableFile(atPath: userApplications.path) else {
            throw InstallLocationError.applicationsNotWritable
        }
        return userApplications
    }

    private static func clearQuarantine(at url: URL) throws {
        _ = try? runCapturing("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
        let listing = (try? runCapturing("/usr/bin/xattr", ["-lr", url.path])) ?? ""
        if listing.contains("com.apple.quarantine") {
            throw InstallLocationError.copyFailed("FlowMod couldn't remove the download quarantine flag, so macOS would open a temporary copy again.")
        }
    }

    @discardableResult
    private static func runCapturing(_ launchPath: String, _ arguments: [String]) throws -> String {
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            print("Install location command failed (\(process.terminationStatus)): \(launchPath) \(detail)")
            throw InstallLocationError.copyFailed("FlowMod couldn't be copied to the Applications folder.")
        }
        return output + errorOutput
    }
}

nonisolated enum InstallLocationError: LocalizedError, Sendable {
    case applicationsNotWritable
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationsNotWritable:
            return "FlowMod couldn't write to the Applications folder."
        case .copyFailed(let message):
            return message
        }
    }
}
