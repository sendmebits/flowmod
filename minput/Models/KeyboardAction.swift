import Foundation
import CoreGraphics

/// Actions that can be triggered by keyboard remapping
enum KeyboardAction: Codable, Equatable, Hashable, Identifiable, CaseIterable {
    case none
    case lineStart      // ⌘←
    case lineEnd        // ⌘→
    case documentStart  // ⌘↑
    case documentEnd    // ⌘↓
    case pageUp
    case pageDown
    case deleteForward
    case selectToLineStart    // ⇧⌘←
    case selectToLineEnd      // ⇧⌘→
    case selectToDocStart     // ⇧⌘↑
    case selectToDocEnd       // ⇧⌘↓
    case customShortcut(KeyCombo)
    
    var id: String {
        switch self {
        case .none: return "none"
        case .lineStart: return "lineStart"
        case .lineEnd: return "lineEnd"
        case .documentStart: return "documentStart"
        case .documentEnd: return "documentEnd"
        case .pageUp: return "pageUp"
        case .pageDown: return "pageDown"
        case .deleteForward: return "deleteForward"
        case .selectToLineStart: return "selectToLineStart"
        case .selectToLineEnd: return "selectToLineEnd"
        case .selectToDocStart: return "selectToDocStart"
        case .selectToDocEnd: return "selectToDocEnd"
        case .customShortcut(let combo): return "custom_\(combo.keyCode)_\(combo.modifiers)"
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None (Pass Through)"
        case .lineStart: return "Line Start (⌘←)"
        case .lineEnd: return "Line End (⌘→)"
        case .documentStart: return "Document Start (⌘↑)"
        case .documentEnd: return "Document End (⌘↓)"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .deleteForward: return "Delete Forward (⌦)"
        case .selectToLineStart: return "Select to Line Start (⇧⌘←)"
        case .selectToLineEnd: return "Select to Line End (⇧⌘→)"
        case .selectToDocStart: return "Select to Doc Start (⇧⌘↑)"
        case .selectToDocEnd: return "Select to Doc End (⇧⌘↓)"
        case .customShortcut(let combo): return "Custom: \(combo.displayName)"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "arrow.right"
        case .lineStart: return "arrow.left.to.line"
        case .lineEnd: return "arrow.right.to.line"
        case .documentStart: return "arrow.up.to.line"
        case .documentEnd: return "arrow.down.to.line"
        case .pageUp: return "arrow.up.doc"
        case .pageDown: return "arrow.down.doc"
        case .deleteForward: return "delete.right"
        case .selectToLineStart: return "arrow.left.to.line.compact"
        case .selectToLineEnd: return "arrow.right.to.line.compact"
        case .selectToDocStart: return "arrow.up.to.line.compact"
        case .selectToDocEnd: return "arrow.down.to.line.compact"
        case .customShortcut: return "keyboard"
        }
    }
    
    /// The key combo to send when this action is triggered
    var keyCombo: KeyCombo? {
        switch self {
        case .none:
            return nil
        case .lineStart:
            return KeyCombo(keyCode: 0x7B, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘←
        case .lineEnd:
            return KeyCombo(keyCode: 0x7C, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘→
        case .documentStart:
            return KeyCombo(keyCode: 0x7E, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘↑
        case .documentEnd:
            return KeyCombo(keyCode: 0x7D, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘↓
        case .pageUp:
            return KeyCombo(keyCode: 0x74, modifiers: 0) // Page Up
        case .pageDown:
            return KeyCombo(keyCode: 0x79, modifiers: 0) // Page Down
        case .deleteForward:
            return KeyCombo(keyCode: 0x75, modifiers: 0) // Forward Delete
        case .selectToLineStart:
            return KeyCombo(keyCode: 0x7B, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToLineEnd:
            return KeyCombo(keyCode: 0x7C, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToDocStart:
            return KeyCombo(keyCode: 0x7E, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToDocEnd:
            return KeyCombo(keyCode: 0x7D, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .customShortcut(let combo):
            return combo
        }
    }
    
    // For CaseIterable conformance without associated values
    static var allCases: [KeyboardAction] {
        [.none, .lineStart, .lineEnd, .documentStart, .documentEnd,
         .pageUp, .pageDown, .deleteForward,
         .selectToLineStart, .selectToLineEnd, .selectToDocStart, .selectToDocEnd]
    }
}
