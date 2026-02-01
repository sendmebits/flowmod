import Foundation

/// Actions that can be triggered by mouse buttons or gestures
enum MouseAction: Codable, Equatable, Hashable, Identifiable, CaseIterable {
    case none
    case missionControl
    case showDesktop
    case launchpad
    case back
    case forward
    case middleClick
    case copy
    case cut
    case paste
    case undo
    case redo
    case selectAll
    case customShortcut(KeyCombo)
    
    var id: String {
        switch self {
        case .none: return "none"
        case .missionControl: return "missionControl"
        case .showDesktop: return "showDesktop"
        case .launchpad: return "launchpad"
        case .back: return "back"
        case .forward: return "forward"
        case .middleClick: return "middleClick"
        case .copy: return "copy"
        case .cut: return "cut"
        case .paste: return "paste"
        case .undo: return "undo"
        case .redo: return "redo"
        case .selectAll: return "selectAll"
        case .customShortcut(let combo): return "custom_\(combo.keyCode)_\(combo.modifiers)"
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .middleClick: return "Middle Click"
        case .copy: return "Copy (⌘C)"
        case .cut: return "Cut (⌘X)"
        case .paste: return "Paste (⌘V)"
        case .undo: return "Undo (⌘Z)"
        case .redo: return "Redo (⇧⌘Z)"
        case .selectAll: return "Select All (⌘A)"
        case .customShortcut(let combo): return "Custom: \(combo.displayName)"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "nosign"
        case .missionControl: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .middleClick: return "computermouse"
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectAll: return "selection.pin.in.out"
        case .customShortcut: return "keyboard"
        }
    }
    
    // For CaseIterable conformance without associated values
    static var allCases: [MouseAction] {
        [.none, .missionControl, .showDesktop, .launchpad,
         .back, .forward, .middleClick,
         .copy, .cut, .paste, .undo, .redo, .selectAll]
    }
}

/// Mouse buttons that can be remapped
enum MouseButton: String, Codable, CaseIterable, Identifiable {
    case back = "Back Button (Mouse 4)"
    case forward = "Forward Button (Mouse 5)"
    case middleClick = "Middle Click"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .back: return "chevron.left.circle"
        case .forward: return "chevron.right.circle"
        case .middleClick: return "circle.circle"
        }
    }
    
    var buttonNumber: Int64 {
        switch self {
        case .back: return 3
        case .forward: return 4
        case .middleClick: return 2
        }
    }
    
    /// Check if a button number is a primary button (left/right click)
    static func isPrimaryButton(_ buttonNumber: Int64) -> Bool {
        return buttonNumber == 0 || buttonNumber == 1  // Left click = 0, Right click = 1
    }
    
    /// Check if a button number is already a built-in button
    static func isBuiltInButton(_ buttonNumber: Int64) -> Bool {
        return allCases.contains { $0.buttonNumber == buttonNumber }
    }
    
    /// Get built-in button for a button number, if any
    static func builtInButton(for buttonNumber: Int64) -> MouseButton? {
        return allCases.first { $0.buttonNumber == buttonNumber }
    }
}

/// A custom mouse button mapping for buttons beyond the built-in ones
struct CustomMouseButtonMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var buttonNumber: Int64
    var action: MouseAction
    
    var displayName: String {
        "Mouse Button \(buttonNumber + 1)"
    }
    
    var icon: String {
        "circle.circle"
    }
}

/// Directions for middle-drag gestures
enum DragDirection: String, Codable, CaseIterable, Identifiable {
    case up = "Drag Up"
    case down = "Drag Down"
    case left = "Drag Left"
    case right = "Drag Right"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}
