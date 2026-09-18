import Foundation
import ApplicationServices
import AppKit
import Observation

/// Manages accessibility permission checking and prompting.
///
/// On macOS 27 this permission lives in System Settings → Privacy & Security →
/// Device Control and Data Access (the former Accessibility pane).
@MainActor
@Observable
class PermissionManager {
    static let shared = PermissionManager()

    private(set) var hasAccessibilityPermission = false
    @ObservationIgnored var onPermissionGranted: (@MainActor () -> Void)?
    @ObservationIgnored var onPermissionRevoked: (@MainActor () -> Void)?

    private var checkTimer: Timer?
    private var currentPollInterval: TimeInterval = 5.0
    private var hasCompletedInitialCheck = false
    private let minPollInterval: TimeInterval = 1.0
    private let maxPollInterval: TimeInterval = 30.0
    @ObservationIgnored private var becomeActiveObserver: NSObjectProtocol?

    /// System Settings pane that hosts this permission.
    static var permissionPaneName: String {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return "Device Control and Data Access"
        }
        return "Accessibility"
    }

    static var permissionSettingsPath: String {
        "System Settings → Privacy & Security → \(permissionPaneName)"
    }

    /// Fresh TCC read. `AXIsProcessTrusted()` can cache false for the process
    /// lifetime after the user turns the System Settings toggle on.
    static func isProcessTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    private init() {
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationBecameActive()
            }
        }
        checkPermission()
    }

    /// Check current accessibility permission status
    func checkPermission() {
        let hadPermission = hasAccessibilityPermission
        hasAccessibilityPermission = Self.isProcessTrusted()

        // Poll rapidly while waiting for a grant and infrequently once trusted.
        if hasAccessibilityPermission {
            currentPollInterval = maxPollInterval
            if !hadPermission {
                onPermissionGranted?()
            }
        } else {
            if hadPermission {
                currentPollInterval = minPollInterval
                onPermissionRevoked?()
            } else if hasCompletedInitialCheck {
                currentPollInterval = min(currentPollInterval * 1.8, maxPollInterval)
            }
        }

        hasCompletedInitialCheck = true

        // AXIsProcessTrusted has no dependable revocation callback. Continue at
        // a low frequency after grant so removing access is reflected within 30s.
        schedulePermissionCheck()
    }

    /// Prompt user for accessibility permission
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Start monitoring for permission grant
        startPermissionMonitoring(resetBackoff: true)
    }

    /// Open System Settings to the permission pane
    func openAccessibilitySettings() {
        checkPermission()
        if !hasAccessibilityPermission { startPermissionMonitoring(resetBackoff: true) }

        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for urlString in candidates {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Quit and reopen so a freshly granted TCC identity is picked up.
    /// Event taps often cannot be created in a process that launched untrusted.
    func relaunchApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let escaped = bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open '\(escaped)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Start polling for permission changes
    private func startPermissionMonitoring(resetBackoff: Bool) {
        if resetBackoff {
            currentPollInterval = minPollInterval
        }

        schedulePermissionCheck()
    }

    private func handleApplicationBecameActive() {
        if !hasAccessibilityPermission {
            currentPollInterval = minPollInterval
        }
        checkPermission()
    }

    private func schedulePermissionCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermission()
            }
        }
        checkTimer?.tolerance = currentPollInterval * 0.2
    }
}
