import Foundation
import SwiftUI
import Observation

/// Main settings store for the app
@MainActor
@Observable
class Settings {
    static let shared = Settings()
    
    // MARK: - Scroll Settings
    var reverseScrollEnabled: Bool = true {
        didSet { UserDefaults.standard.set(reverseScrollEnabled, forKey: "reverseScrollEnabled") }
    }
    
    // MARK: - Mouse Button Mappings
    var mouseButtonMappings: [MouseButton: MouseAction] = [:] {
        didSet { saveMouseButtonMappings() }
    }
    
    // MARK: - Middle Drag Gesture Mappings
    var middleDragMappings: [DragDirection: MouseAction] = [:] {
        didSet { saveMiddleDragMappings() }
    }
    
    // MARK: - Keyboard Mappings
    var keyboardMappings: [KeyboardMapping] = [] {
        didSet { saveKeyboardMappings() }
    }
    
    // MARK: - Excluded Apps
    var excludedApps: [ExcludedApp] = [] {
        didSet { saveExcludedApps() }
    }
    
    // MARK: - General Settings
    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
    
    var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon") }
    }
    
    var dragThreshold: Double {
        get { UserDefaults.standard.object(forKey: "dragThreshold") as? Double ?? 40.0 }
        set { UserDefaults.standard.set(newValue, forKey: "dragThreshold") }
    }
    
    /// Override device detection - assume external mouse is always connected
    var assumeExternalMouse: Bool {
        get { UserDefaults.standard.bool(forKey: "assumeExternalMouse") }
        set { UserDefaults.standard.set(newValue, forKey: "assumeExternalMouse") }
    }
    
    /// Override device detection - assume external keyboard is always connected
    var assumeExternalKeyboard: Bool {
        get { UserDefaults.standard.bool(forKey: "assumeExternalKeyboard") }
        set { UserDefaults.standard.set(newValue, forKey: "assumeExternalKeyboard") }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load reverseScrollEnabled from UserDefaults (default to true if not set)
        if UserDefaults.standard.object(forKey: "reverseScrollEnabled") == nil {
            reverseScrollEnabled = true
        } else {
            reverseScrollEnabled = UserDefaults.standard.bool(forKey: "reverseScrollEnabled")
        }
        
        loadMouseButtonMappings()
        loadMiddleDragMappings()
        loadKeyboardMappings()
        loadExcludedApps()
        
        // Set defaults if empty
        if mouseButtonMappings.isEmpty {
            mouseButtonMappings = [
                .back: .back,
                .forward: .forward,
                .middleClick: .middleClick
            ]
        }
        
        if middleDragMappings.isEmpty {
            middleDragMappings = [
                .up: .missionControl,
                .down: .showDesktop,
                .left: .none,
                .right: .none
            ]
        }
        
        if keyboardMappings.isEmpty {
            keyboardMappings = [
                KeyboardMapping(sourceKey: .home, targetAction: .lineStart),
                KeyboardMapping(sourceKey: .end, targetAction: .lineEnd)
            ]
        }
    }
    
    // MARK: - Persistence
    
    private let mouseButtonMappingsKey = "mouseButtonMappings"
    private let middleDragMappingsKey = "middleDragMappings"
    private let keyboardMappingsKey = "keyboardMappings"
    private let excludedAppsKey = "excludedApps"
    
    private func saveMouseButtonMappings() {
        if let data = try? JSONEncoder().encode(mouseButtonMappings) {
            UserDefaults.standard.set(data, forKey: mouseButtonMappingsKey)
        }
    }
    
    private func loadMouseButtonMappings() {
        if let data = UserDefaults.standard.data(forKey: mouseButtonMappingsKey),
           let mappings = try? JSONDecoder().decode([MouseButton: MouseAction].self, from: data) {
            mouseButtonMappings = mappings
        }
    }
    
    private func saveMiddleDragMappings() {
        if let data = try? JSONEncoder().encode(middleDragMappings) {
            UserDefaults.standard.set(data, forKey: middleDragMappingsKey)
        }
    }
    
    private func loadMiddleDragMappings() {
        if let data = UserDefaults.standard.data(forKey: middleDragMappingsKey),
           let mappings = try? JSONDecoder().decode([DragDirection: MouseAction].self, from: data) {
            middleDragMappings = mappings
        }
    }
    
    private func saveKeyboardMappings() {
        if let data = try? JSONEncoder().encode(keyboardMappings) {
            UserDefaults.standard.set(data, forKey: keyboardMappingsKey)
        }
    }
    
    private func loadKeyboardMappings() {
        if let data = UserDefaults.standard.data(forKey: keyboardMappingsKey),
           let mappings = try? JSONDecoder().decode([KeyboardMapping].self, from: data) {
            keyboardMappings = mappings
        }
    }
    
    private func saveExcludedApps() {
        if let data = try? JSONEncoder().encode(excludedApps) {
            UserDefaults.standard.set(data, forKey: excludedAppsKey)
        }
    }
    
    private func loadExcludedApps() {
        if let data = UserDefaults.standard.data(forKey: excludedAppsKey),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = apps
        }
    }
    
    // MARK: - Helpers
    
    func isAppExcluded(_ bundleIdentifier: String) -> Bool {
        excludedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    func getAction(for button: MouseButton) -> MouseAction {
        mouseButtonMappings[button] ?? .none
    }
    
    func getAction(for direction: DragDirection) -> MouseAction {
        middleDragMappings[direction] ?? .none
    }
    
    func getKeyboardAction(for keyCode: UInt16) -> KeyboardAction? {
        for mapping in keyboardMappings {
            if mapping.effectiveKeyCode == keyCode {
                return mapping.targetAction
            }
        }
        return nil
    }
}
