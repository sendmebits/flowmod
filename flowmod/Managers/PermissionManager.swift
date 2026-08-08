import Foundation
import ApplicationServices
import AppKit
import Observation

/// Manages accessibility permission checking and prompting
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
    
    private init() {
        checkPermission()
    }
    
    /// Check current accessibility permission status
    func checkPermission() {
        let hadPermission = hasAccessibilityPermission
        hasAccessibilityPermission = AXIsProcessTrusted()
        
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
    
    /// Open System Settings to Accessibility pane
    func openAccessibilitySettings() {
        checkPermission()
        if !hasAccessibilityPermission { startPermissionMonitoring(resetBackoff: true) }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Start polling for permission changes
    private func startPermissionMonitoring(resetBackoff: Bool) {
        if resetBackoff {
            currentPollInterval = minPollInterval
        }
        
        schedulePermissionCheck()
    }

    private func schedulePermissionCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermission()
            }
        }
    }
}
