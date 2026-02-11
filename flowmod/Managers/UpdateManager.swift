import Foundation
import Observation
import AppKit

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
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    var errorMessage: String?
    
    // MARK: - Constants
    
    private let releasesURL = URL(string: "https://api.github.com/repos/sendmebits/flowmod/releases/latest")!
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
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
            await checkForUpdates()
        }
    }
    
    /// Manually check for updates by hitting the GitHub Releases API.
    func checkForUpdates() async {
        guard !isChecking else { return }
        
        isChecking = true
        errorMessage = nil
        
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
                lastUpdateCheck = Date()
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
                if let asset = release.assets.first(where: { $0.name.lowercased().contains("flowmod") && $0.name.hasSuffix(".zip") }) {
                    downloadURL = URL(string: asset.browserDownloadURL)
                } else {
                    downloadURL = nil
                }
                updateAvailable = true
            } else {
                updateAvailable = false
                latestVersion = nil
                downloadURL = nil
            }
            
            lastUpdateCheck = Date()
            
        } catch is CancellationError {
            // Task cancelled, ignore
        } catch {
            errorMessage = "Failed to check for updates: \(error.localizedDescription)"
        }
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
            
            let zipPath = tempDir.appendingPathComponent("FlowMod.app.zip")
            
            let (localURL, response) = try await downloadFile(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                errorMessage = "Download failed."
                cleanup(tempDir)
                return
            }
            
            try FileManager.default.moveItem(at: localURL, to: zipPath)
            
            // 2. Unzip
            let unzipResult = try runProcess("/usr/bin/unzip", arguments: ["-o", zipPath.path, "-d", tempDir.path])
            guard unzipResult == 0 else {
                errorMessage = "Failed to extract update (exit code \(unzipResult))."
                cleanup(tempDir)
                return
            }
            
            // 3. Find the extracted .app bundle
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newAppBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                errorMessage = "Could not find app bundle in update."
                cleanup(tempDir)
                return
            }
            
            // 4. Replace the current app bundle
            let currentBundleURL = Bundle.main.bundleURL
            let parentDir = currentBundleURL.deletingLastPathComponent()
            
            // Move old app to trash
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: currentBundleURL, resultingItemURL: &trashedURL)
            
            // Copy new app to original location
            let destinationURL = parentDir.appendingPathComponent(currentBundleURL.lastPathComponent)
            try FileManager.default.copyItem(at: newAppBundle, to: destinationURL)
            
            // 5. Relaunch
            let relaunchPath = destinationURL.path
            cleanup(tempDir)
            relaunch(appPath: relaunchPath)
            
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
    
    private func relaunch(appPath: String) {
        // Launch a background shell that waits briefly then opens the new app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        
        // Terminate the current app
        NSApplication.shared.terminate(nil)
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
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
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
