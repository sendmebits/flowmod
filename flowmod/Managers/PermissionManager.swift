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
    
    private var checkTimer: Timer?
    private var currentPollInterval: TimeInterval = 5.0
    private let minPollInterval: TimeInterval = 1.0
    private let maxPollInterval: TimeInterval = 30.0
    
    private init() {
        checkPermission()
        if !hasAccessibilityPermission {
            startPermissionMonitoring(resetBackoff: false)
        }
    }
    
    /// Check current accessibility permission status
    func checkPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        
        // Stop polling once permission is granted
        if hasAccessibilityPermission {
            checkTimer?.invalidate()
            checkTimer = nil
        }
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Start polling for permission changes
    private func startPermissionMonitoring(resetBackoff: Bool) {
        if resetBackoff {
            currentPollInterval = minPollInterval
        }
        
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkPermission()
                guard !self.hasAccessibilityPermission else { return }
                self.currentPollInterval = min(self.currentPollInterval * 1.8, self.maxPollInterval)
                self.startPermissionMonitoring(resetBackoff: false)
            }
        }
    }
}
