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
    
    private init() {
        checkPermission()
        startPermissionMonitoring()
    }
    
    /// Check current accessibility permission status
    func checkPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    /// Prompt user for accessibility permission
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Start monitoring for permission grant
        startPermissionMonitoring()
    }
    
    /// Open System Settings to Accessibility pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Start polling for permission changes
    private func startPermissionMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermission()
            }
        }
    }
}
