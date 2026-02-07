import Foundation
import CoreGraphics

/// Actions that can be triggered by keyboard remapping
enum KeyboardAction: Codable, Equatable, Hashable, Identifiable, CaseIterable {
    case none
    case lineStart      // ⌃A
    case lineEnd        // ⌃E
    case documentStart  // ⌘↑
    case documentEnd    // ⌘↓
    case pageUp
    case pageDown
    case deleteForward
    case selectToLineStart    // ⇧⌃A
    case selectToLineEnd      // ⇧⌃E
    case selectToDocStart     // ⇧⌘↑
    case selectToDocEnd       // ⇧⌘↓
    case copy           // ⌘C
    case cut            // ⌘X
    case paste          // ⌘V
    case undo           // ⌘Z
    case redo           // ⇧⌘Z
    case selectAll      // ⌘A
    case fullscreen     // ⌃⌘F
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
        case .copy: return "copy"
        case .cut: return "cut"
        case .paste: return "paste"
        case .undo: return "undo"
        case .redo: return "redo"
        case .selectAll: return "selectAll"
        case .fullscreen: return "fullscreen"
        case .customShortcut(let combo): return "custom_\(combo.keyCode)_\(combo.modifiers)"
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None (Pass Through)"
        case .lineStart: return "Line Start (⌃A)"
        case .lineEnd: return "Line End (⌃E)"
        case .documentStart: return "Document Start (⌘↑)"
        case .documentEnd: return "Document End (⌘↓)"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .deleteForward: return "Delete Forward (⌦)"
        case .selectToLineStart: return "Select to Line Start (⇧⌃A)"
        case .selectToLineEnd: return "Select to Line End (⇧⌃E)"
        case .selectToDocStart: return "Select to Doc Start (⇧⌘↑)"
        case .selectToDocEnd: return "Select to Doc End (⇧⌘↓)"
        case .copy: return "Copy (⌘C)"
        case .cut: return "Cut (⌘X)"
        case .paste: return "Paste (⌘V)"
        case .undo: return "Undo (⌘Z)"
        case .redo: return "Redo (⇧⌘Z)"
        case .selectAll: return "Select All (⌘A)"
        case .fullscreen: return "Fullscreen (⌃⌘F)"
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
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectAll: return "selection.pin.in.out"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .customShortcut: return "keyboard"
        }
    }
    
    /// The key combo to send when this action is triggered
    var keyCombo: KeyCombo? {
        switch self {
        case .none:
            return nil
        case .lineStart:
            return KeyCombo(keyCode: 0x00, modifiers: CGEventFlags.maskControl.rawValue) // ⌃A
        case .lineEnd:
            return KeyCombo(keyCode: 0x0E, modifiers: CGEventFlags.maskControl.rawValue) // ⌃E
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
            return KeyCombo(keyCode: 0x00, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToLineEnd:
            return KeyCombo(keyCode: 0x0E, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToDocStart:
            return KeyCombo(keyCode: 0x7E, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .selectToDocEnd:
            return KeyCombo(keyCode: 0x7D, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        case .copy:
            return KeyCombo(keyCode: 0x08, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘C
        case .cut:
            return KeyCombo(keyCode: 0x07, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘X
        case .paste:
            return KeyCombo(keyCode: 0x09, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘V
        case .undo:
            return KeyCombo(keyCode: 0x06, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘Z
        case .redo:
            return KeyCombo(keyCode: 0x06, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue) // ⇧⌘Z
        case .selectAll:
            return KeyCombo(keyCode: 0x00, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘A
        case .fullscreen:
            return KeyCombo(keyCode: 0x03, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue) // ⌃⌘F
        case .customShortcut(let combo):
            return combo
        }
    }
    
    // For CaseIterable conformance without associated values
    static var allCases: [KeyboardAction] {
        [.none, .lineStart, .lineEnd, .documentStart, .documentEnd,
         .pageUp, .pageDown, .deleteForward,
         .selectToLineStart, .selectToLineEnd, .selectToDocStart, .selectToDocEnd,
         .copy, .cut, .paste, .undo, .redo, .selectAll, .fullscreen]
    }
}
