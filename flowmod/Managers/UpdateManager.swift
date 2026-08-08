import Foundation
import Observation
import AppKit
import CryptoKit
import Security

/// Manages checking for app updates via GitHub Releases and downloading/installing them.
@MainActor
@Observable
class UpdateManager {
    static let shared = UpdateManager()
    
    // MARK: - Persisted Settings
    
    /// Whether to automatically check for updates on launch (once per day)
    var autoCheckForUpdates: Bool = true {
        didSet { UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates") }
    }
    
    /// Timestamp of the last successful update check
    private var lastUpdateCheck: Date? {
        didSet {
            if let date = lastUpdateCheck {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "lastUpdateCheckTimestamp")
            }
        }
    }
    
    // MARK: - Observable State
    
    var updateAvailable: Bool = false
    var latestVersion: String?
    var downloadURL: URL?
    private var downloadDigest: String?
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    var errorMessage: String?
    /// Shown when the app is up to date (after a check or when throttled to avoid repeated GitHub requests).
    var upToDateMessage: String?
    @ObservationIgnored private var upToDateDismissTask: Task<Void, Never>?
    
    // MARK: - Constants
    
    private let releasesURL = URL(string: "https://api.github.com/repos/sendmebits/flowmod/releases/latest")!
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    /// Minimum time between manual "Check for Updates" requests to avoid GitHub rate limiting.
    private let manualCheckThrottleInterval: TimeInterval = 30
    private let expectedBundleIdentifier = "com.sendmebits.flowmod"
    private let expectedSigningTeamIdentifier = "8383UU5VZ7"
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted settings
        if UserDefaults.standard.object(forKey: "autoCheckForUpdates") == nil {
            autoCheckForUpdates = true
        } else {
            autoCheckForUpdates = UserDefaults.standard.bool(forKey: "autoCheckForUpdates")
        }
        
        let timestamp = UserDefaults.standard.double(forKey: "lastUpdateCheckTimestamp")
        if timestamp > 0 {
            lastUpdateCheck = Date(timeIntervalSince1970: timestamp)
        }
    }
    
    // MARK: - Public Methods
    
    /// Called on app launch; checks for updates if auto-check is enabled and enough time has passed.
    func checkIfNeeded() {
        guard autoCheckForUpdates else { return }
        
        if let lastCheck = lastUpdateCheck {
            let elapsed = Date().timeIntervalSince(lastCheck)
            guard elapsed >= checkInterval else { return }
        }
        // First launch (nil) or interval exceeded — check now
        Task {
            await checkForUpdates(showUpToDateFeedback: false)
        }
    }
    
    /// Manually check for updates by hitting the GitHub Releases API.
    /// Throttled to at most once per `manualCheckThrottleInterval` to avoid GitHub rate limiting.
    func checkForUpdates(showUpToDateFeedback: Bool = true) async {
        guard !isChecking else { return }
        
        // If we checked very recently, show up-to-date without hitting the API.
        if let lastCheck = lastUpdateCheck, Date().timeIntervalSince(lastCheck) < manualCheckThrottleInterval {
            if showUpToDateFeedback {
                showUpToDateFeedbackMessage()
            } else {
                clearUpToDateFeedback()
            }
            errorMessage = nil
            return
        }
        
        isChecking = true
        errorMessage = nil
        clearUpToDateFeedback()
        
        defer { isChecking = false }
        
        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from GitHub."
                return
            }
            
            if httpResponse.statusCode == 404 {
                // No releases published yet
                updateAvailable = false
                latestVersion = nil
                downloadURL = nil
                downloadDigest = nil
                lastUpdateCheck = Date()
                if showUpToDateFeedback {
                    showUpToDateFeedbackMessage()
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                errorMessage = "GitHub returned status \(httpResponse.statusCode)."
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            // Strip leading "v" from tag for version comparison
            let remoteVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if isNewerVersion(remote: remoteVersion, local: localVersion) {
                latestVersion = remoteVersion
                // Find the zip asset (e.g. flowmod.zip) containing the .app bundle
                if let asset = release.assets.first(where: {
                    let name = $0.name.lowercased()
                    return name.contains("flowmod") && name.hasSuffix(".zip")
                }) {
                    downloadURL = URL(string: asset.browserDownloadURL)
                    downloadDigest = asset.digest
                } else {
                    downloadURL = nil
                    downloadDigest = nil
                }
                updateAvailable = true
                clearUpToDateFeedback()
            } else {
                updateAvailable = false
                latestVersion = nil
                downloadURL = nil
                downloadDigest = nil
                if showUpToDateFeedback {
                    showUpToDateFeedbackMessage()
                }
            }
            
            lastUpdateCheck = Date()
            
        } catch is CancellationError {
            // Task cancelled, ignore
        } catch {
            errorMessage = "Failed to check for updates: \(error.localizedDescription)"
            clearUpToDateFeedback()
        }
    }

    private func showUpToDateFeedbackMessage() {
        upToDateDismissTask?.cancel()
        upToDateMessage = "You're up to date."
        upToDateDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            upToDateMessage = nil
            upToDateDismissTask = nil
        }
    }

    private func clearUpToDateFeedback() {
        upToDateDismissTask?.cancel()
        upToDateDismissTask = nil
        upToDateMessage = nil
    }
    
    /// Downloads the update zip, extracts it, replaces the current app bundle, and relaunches.
    func downloadAndInstall() async {
        guard let url = downloadURL else {
            errorMessage = "No download URL available."
            return
        }
        
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil
        
        defer {
            isDownloading = false
            downloadProgress = 0
        }
        
        do {
            // 1. Download the zip to a temp directory
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowModUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { cleanup(tempDir) }
            
            let zipPath = tempDir.appendingPathComponent("FlowMod.app.zip")
            
            let (localURL, response) = try await downloadFile(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                errorMessage = "Download failed."
                return
            }
            
            try FileManager.default.moveItem(at: localURL, to: zipPath)

            // GitHub supplies a SHA-256 digest for release assets. It is not a
            // substitute for code signing, but it catches corruption between
            // release metadata retrieval and installation.
            if let expectedDigest = downloadDigest {
                try verifyDigest(of: zipPath, expectedDigest: expectedDigest)
            }
            
            // 2. Unzip
            let unzipResult = try runProcess("/usr/bin/unzip", arguments: ["-o", zipPath.path, "-d", tempDir.path])
            guard unzipResult == 0 else {
                errorMessage = "Failed to extract update (exit code \(unzipResult))."
                return
            }
            
            // 3. Find the extracted .app bundle
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            let appBundles = contents.filter { $0.pathExtension.lowercased() == "app" }
            guard appBundles.count == 1, let newAppBundle = appBundles.first else {
                errorMessage = "Could not find app bundle in update."
                return
            }

            try validateUpdateBundle(newAppBundle)
            
            // 4. Replace the current app bundle
            let currentBundleURL = Bundle.main.bundleURL
            let parentDir = currentBundleURL.deletingLastPathComponent()
            
            let destinationURL = parentDir.appendingPathComponent(currentBundleURL.lastPathComponent)
            let backupURL = try installTransactionally(
                newAppBundle: newAppBundle,
                currentBundleURL: currentBundleURL,
                destinationURL: destinationURL
            )
            
            // 5. Relaunch
            do {
                try scheduleRelaunch(appPath: destinationURL.path)
            } catch {
                try rollbackInstalledUpdate(
                    destinationURL: destinationURL,
                    backupURL: backupURL,
                    temporaryDirectory: tempDir
                )
                throw error
            }

            // The old version remains recoverable from Trash if launching the
            // validated replacement unexpectedly fails after this process exits.
            var trashedBackupURL: NSURL?
            try? FileManager.default.trashItem(at: backupURL, resultingItemURL: &trashedBackupURL)

            NSApplication.shared.terminate(nil)
            
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Version Comparison
    
    /// Returns true if `remote` is a newer semantic version than `local`.
    private func isNewerVersion(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, localParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
    
    // MARK: - Download Helper
    
    /// Downloads a file using URLSession with progress tracking via delegate.
    private func downloadFile(from url: URL) async throws -> (URL, URLResponse) {
        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 300 // 5 minutes for large downloads
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        
        return try await session.download(for: request)
    }
    
    // MARK: - Process Helper
    
    /// Runs a command-line process synchronously and returns the exit code.
    private func runProcess(_ path: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    
    // MARK: - Cleanup & Relaunch
    
    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func verifyDigest(of fileURL: URL, expectedDigest: String) throws {
        let components = expectedDigest.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2, components[0].lowercased() == "sha256" else {
            throw UpdateInstallError.invalidDigestMetadata
        }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(components[1]) == .orderedSame else {
            throw UpdateInstallError.digestMismatch
        }
    }

    private func validateUpdateBundle(_ appBundleURL: URL) throws {
        guard let bundle = Bundle(url: appBundleURL),
              bundle.bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateInstallError.invalidBundleIdentifier
        }

        guard let expectedVersion = latestVersion,
              let candidateVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              candidateVersion == expectedVersion else {
            throw UpdateInstallError.unexpectedVersion
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw UpdateInstallError.invalidCodeSignature(createStatus)
        }

        let validationFlags = SecCSFlags(rawValue:
            UInt32(kSecCSCheckAllArchitectures) |
            UInt32(kSecCSCheckNestedCode) |
            UInt32(kSecCSStrictValidate)
        )

        let requirementText = "anchor apple generic and identifier \"\(expectedBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(expectedSigningTeamIdentifier)\""
        var signingRequirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &signingRequirement
        )
        guard requirementStatus == errSecSuccess, let signingRequirement else {
            throw UpdateInstallError.unexpectedSigner
        }

        let validationStatus = SecStaticCodeCheckValidity(
            staticCode,
            validationFlags,
            signingRequirement
        )
        guard validationStatus == errSecSuccess else {
            throw UpdateInstallError.invalidCodeSignature(validationStatus)
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &signingInfo
        )
        guard infoStatus == errSecSuccess,
              let info = signingInfo as? [CFString: Any],
              let teamIdentifier = info[kSecCodeInfoTeamIdentifier] as? String,
              teamIdentifier == expectedSigningTeamIdentifier else {
            throw UpdateInstallError.unexpectedSigner
        }

        // Prefer an offline stapled-ticket check. Zip-distributed builds may not
        // be stapled; in that case Gatekeeper assessment is best-effort and must
        // not hard-fail network/transient assess errors after signature checks passed.
        try validateNotarization(of: appBundleURL)
    }

    private func validateNotarization(of appBundleURL: URL) throws {
        let staplerStatus = try runProcess(
            "/usr/bin/xcrun",
            arguments: ["stapler", "validate", appBundleURL.path]
        )
        if staplerStatus == 0 {
            return
        }

        let spctlStatus = try runProcess(
            "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", appBundleURL.path]
        )
        if spctlStatus == 0 {
            return
        }

        // Signature + team were already validated. Reject only when Gatekeeper
        // explicitly assesses the bundle as invalid (commonly status 3).
        if spctlStatus == 3 {
            throw UpdateInstallError.notNotarized
        }

        print("Update notarization could not be confirmed offline (stapler=\(staplerStatus), spctl=\(spctlStatus)); proceeding after signature validation.")
    }

    /// Copy the candidate beside the installed app before moving the current
    /// bundle. The two final moves are same-volume renames; if the second one
    /// fails, the original bundle is immediately restored.
    private func installTransactionally(
        newAppBundle: URL,
        currentBundleURL: URL,
        destinationURL: URL
    ) throws -> URL {
        let parentDirectory = destinationURL.deletingLastPathComponent()
        let stagedURL = parentDirectory.appendingPathComponent(".FlowMod-update-\(UUID().uuidString).app")
        let backupURL = parentDirectory.appendingPathComponent(".FlowMod-backup-\(UUID().uuidString).app")

        do {
            try FileManager.default.copyItem(at: newAppBundle, to: stagedURL)
            try FileManager.default.moveItem(at: currentBundleURL, to: backupURL)
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            throw error
        }

        do {
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
            return backupURL
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: currentBundleURL)
            try? FileManager.default.removeItem(at: stagedURL)
            throw error
        }
    }

    private func rollbackInstalledUpdate(
        destinationURL: URL,
        backupURL: URL,
        temporaryDirectory: URL
    ) throws {
        let failedCandidateURL = temporaryDirectory.appendingPathComponent("failed-update.app")
        try FileManager.default.moveItem(at: destinationURL, to: failedCandidateURL)
        do {
            try FileManager.default.moveItem(at: backupURL, to: destinationURL)
        } catch {
            try? FileManager.default.moveItem(at: failedCandidateURL, to: destinationURL)
            throw error
        }
    }

    private func scheduleRelaunch(appPath: String) throws {
        // Pass the path as a positional shell argument rather than interpolating
        // it into shell source; quotes or substitutions in a folder name cannot
        // become commands.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 1; exec /usr/bin/open \"$1\"",
            "flowmod-relauncher",
            appPath
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

private enum UpdateInstallError: LocalizedError {
    case invalidDigestMetadata
    case digestMismatch
    case invalidBundleIdentifier
    case unexpectedVersion
    case invalidCodeSignature(OSStatus)
    case unexpectedSigner
    case notNotarized

    var errorDescription: String? {
        switch self {
        case .invalidDigestMetadata:
            return "The release provided invalid checksum metadata."
        case .digestMismatch:
            return "The downloaded update did not match its release checksum."
        case .invalidBundleIdentifier:
            return "The update is not a FlowMod application bundle."
        case .unexpectedVersion:
            return "The update bundle's version does not match the release."
        case .invalidCodeSignature(let status):
            return "The update's code signature is invalid (status \(status))."
        case .unexpectedSigner:
            return "The update was not signed by the FlowMod developer."
        case .notNotarized:
            return "The update failed Gatekeeper/notarization assessment."
        }
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let digest: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

// MARK: - Download Progress Delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    
    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The download(for:) async API handles this; this delegate method is required for protocol conformance.
    }
}
