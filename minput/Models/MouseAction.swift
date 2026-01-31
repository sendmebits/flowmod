import Foundation

/// Actions that can be triggered by mouse buttons or gestures
enum MouseAction: Codable, Equatable, Hashable, Identifiable, CaseIterable {
    case none
    case missionControl
    case showDesktop
    case launchpad
    case appExpose
    case back
    case forward
    case middleClick
    case customShortcut(KeyCombo)
    
    var id: String {
        switch self {
        case .none: return "none"
        case .missionControl: return "missionControl"
        case .showDesktop: return "showDesktop"
        case .launchpad: return "launchpad"
        case .appExpose: return "appExpose"
        case .back: return "back"
        case .forward: return "forward"
        case .middleClick: return "middleClick"
        case .customShortcut(let combo): return "custom_\(combo.keyCode)_\(combo.modifiers)"
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .appExpose: return "App Exposé"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .middleClick: return "Middle Click"
        case .customShortcut(let combo): return "Custom: \(combo.displayName)"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "nosign"
        case .missionControl: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .appExpose: return "rectangle.stack"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .middleClick: return "computermouse"
        case .customShortcut: return "keyboard"
        }
    }
    
    // For CaseIterable conformance without associated values
    static var allCases: [MouseAction] {
        [.none, .missionControl, .showDesktop, .launchpad, .appExpose,
         .back, .forward, .middleClick]
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
