import Foundation
import SwiftUI
import Observation

/// Smooth scrolling intensity options
enum SmoothScrolling: String, CaseIterable, Identifiable {
    case off = "Off"
    case smooth = "Smooth"
    case verySmooth = "Very Smooth"
    
    var id: String { rawValue }
}

/// Main settings store for the app
@MainActor
@Observable
class Settings {
    static let shared = Settings()
    
    // MARK: - Scroll Settings
    var reverseScrollEnabled: Bool = true {
        didSet { UserDefaults.standard.set(reverseScrollEnabled, forKey: "reverseScrollEnabled") }
    }
    
    var smoothScrolling: SmoothScrolling = .off {
        didSet { UserDefaults.standard.set(smoothScrolling.rawValue, forKey: "smoothScrolling") }
    }
    
    /// Shift key modifier: scroll horizontally instead of vertically
    var shiftHorizontalScroll: Bool = true {
        didSet { UserDefaults.standard.set(shiftHorizontalScroll, forKey: "shiftHorizontalScroll") }
    }
    
    /// Option key modifier: slow down scroll speed for precision
    var optionPrecisionScroll: Bool = true {
        didSet { UserDefaults.standard.set(optionPrecisionScroll, forKey: "optionPrecisionScroll") }
    }
    
    /// Precision scroll speed multiplier (0.0 to 1.0)
    var precisionScrollMultiplier: Double = 0.33 {
        didSet { UserDefaults.standard.set(precisionScrollMultiplier, forKey: "precisionScrollMultiplier") }
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
        
        // Load smoothScrolling from UserDefaults (default to .off if not set)
        if let rawValue = UserDefaults.standard.string(forKey: "smoothScrolling"),
           let value = SmoothScrolling(rawValue: rawValue) {
            smoothScrolling = value
        } else {
            smoothScrolling = .off
        }
        
        // Load scroll modifier settings (default to true if not set)
        if UserDefaults.standard.object(forKey: "shiftHorizontalScroll") == nil {
            shiftHorizontalScroll = true
        } else {
            shiftHorizontalScroll = UserDefaults.standard.bool(forKey: "shiftHorizontalScroll")
        }
        
        if UserDefaults.standard.object(forKey: "optionPrecisionScroll") == nil {
            optionPrecisionScroll = true
        } else {
            optionPrecisionScroll = UserDefaults.standard.bool(forKey: "optionPrecisionScroll")
        }
        
        if UserDefaults.standard.object(forKey: "precisionScrollMultiplier") != nil {
            precisionScrollMultiplier = UserDefaults.standard.double(forKey: "precisionScrollMultiplier")
        } else {
            precisionScrollMultiplier = 0.33
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
    
    func getKeyboardAction(for keyCode: UInt16, modifiers: UInt64) -> KeyboardAction? {
        // Mask to only check relevant modifier keys (Control, Option, Shift, Command)
        let relevantModifierMask: UInt64 = CGEventFlags.maskControl.rawValue |
                                           CGEventFlags.maskAlternate.rawValue |
                                           CGEventFlags.maskShift.rawValue |
                                           CGEventFlags.maskCommand.rawValue
        
        let maskedInputModifiers = modifiers & relevantModifierMask
        
        for mapping in keyboardMappings {
            if mapping.effectiveKeyCode == keyCode {
                let mappingModifiers = mapping.effectiveModifiers & relevantModifierMask
                if mappingModifiers == maskedInputModifiers {
                    return mapping.targetAction
                }
            }
        }
        return nil
    }
}
