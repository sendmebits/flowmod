import Foundation
import Observation

/// Codable snapshot of a profile's values, used to persist per-mouse profiles
/// as a single JSON blob in UserDefaults (see `Settings.mouseProfiles`).
struct ProfileData: Codable {
    var displayName: String
    var reverseScrollEnabled: Bool
    var smoothScrolling: SmoothScrolling
    var shiftHorizontalScroll: Bool
    var optionPrecisionScroll: Bool
    var precisionScrollMultiplier: Double
    var controlFastScroll: Bool
    var fastScrollMultiplier: Double
    var commandZoomScroll: Bool
    var customMouseButtonMappings: [CustomMouseButtonMapping]
    var middleDragMappings: [DragDirection: MouseAction]
    var continuousGestures: Bool
}

/// The per-device settings (scroll, buttons, gestures).
///
/// `Settings` owns one instance as the default profile (persisted under the
/// original UserDefaults keys, so existing installs are unaffected) plus one
/// instance per customized mouse, keyed by "vendorID:productID".
@MainActor
@Observable
final class ProfileSettings {
    /// Called whenever any property changes; the owning `Settings` uses this
    /// to persist. Nil while values are being loaded/copied so bulk assignment
    /// doesn't trigger redundant saves.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Product name of the mouse this profile belongs to (empty for the
    /// default profile). Kept so the UI can list profiles for mice that are
    /// not currently connected.
    var displayName: String = "" { didSet { onChange?() } }

    // MARK: - Scroll
    var reverseScrollEnabled: Bool = true { didSet { onChange?() } }
    var smoothScrolling: SmoothScrolling = .verySmooth { didSet { onChange?() } }
    var shiftHorizontalScroll: Bool = true { didSet { onChange?() } }
    var optionPrecisionScroll: Bool = true { didSet { onChange?() } }
    var precisionScrollMultiplier: Double = 0.33 { didSet { onChange?() } }
    var controlFastScroll: Bool = true { didSet { onChange?() } }
    var fastScrollMultiplier: Double = 3.0 { didSet { onChange?() } }
    var commandZoomScroll: Bool = true { didSet { onChange?() } }

    // MARK: - Buttons
    var customMouseButtonMappings: [CustomMouseButtonMapping] = [] { didSet { onChange?() } }

    // MARK: - Gestures
    var middleDragMappings: [DragDirection: MouseAction] = [:] { didSet { onChange?() } }
    var continuousGestures: Bool = true { didSet { onChange?() } }

    init() {}

    init(data: ProfileData) {
        displayName = data.displayName
        reverseScrollEnabled = data.reverseScrollEnabled
        smoothScrolling = data.smoothScrolling
        shiftHorizontalScroll = data.shiftHorizontalScroll
        optionPrecisionScroll = data.optionPrecisionScroll
        precisionScrollMultiplier = data.precisionScrollMultiplier
        controlFastScroll = data.controlFastScroll
        fastScrollMultiplier = data.fastScrollMultiplier
        commandZoomScroll = data.commandZoomScroll
        customMouseButtonMappings = data.customMouseButtonMappings
        middleDragMappings = data.middleDragMappings
        continuousGestures = data.continuousGestures
    }

    var data: ProfileData {
        ProfileData(
            displayName: displayName,
            reverseScrollEnabled: reverseScrollEnabled,
            smoothScrolling: smoothScrolling,
            shiftHorizontalScroll: shiftHorizontalScroll,
            optionPrecisionScroll: optionPrecisionScroll,
            precisionScrollMultiplier: precisionScrollMultiplier,
            controlFastScroll: controlFastScroll,
            fastScrollMultiplier: fastScrollMultiplier,
            commandZoomScroll: commandZoomScroll,
            customMouseButtonMappings: customMouseButtonMappings,
            middleDragMappings: middleDragMappings,
            continuousGestures: continuousGestures
        )
    }

    /// Copy all values (except `displayName`) from another profile.
    /// Used to snapshot the default profile when customizing a mouse.
    func copyValues(from other: ProfileSettings) {
        reverseScrollEnabled = other.reverseScrollEnabled
        smoothScrolling = other.smoothScrolling
        shiftHorizontalScroll = other.shiftHorizontalScroll
        optionPrecisionScroll = other.optionPrecisionScroll
        precisionScrollMultiplier = other.precisionScrollMultiplier
        controlFastScroll = other.controlFastScroll
        fastScrollMultiplier = other.fastScrollMultiplier
        commandZoomScroll = other.commandZoomScroll
        customMouseButtonMappings = other.customMouseButtonMappings
        middleDragMappings = other.middleDragMappings
        continuousGestures = other.continuousGestures
    }

    // MARK: - Helpers

    func getAction(for direction: DragDirection) -> MouseAction {
        middleDragMappings[direction] ?? .none
    }

    /// Get action for a button number from custom mappings
    func getAction(forButtonNumber buttonNumber: Int64) -> MouseAction? {
        customMouseButtonMappings.first(where: { $0.buttonNumber == buttonNumber })?.action
    }

    /// Get all custom button numbers that are already mapped
    var customMappedButtonNumbers: Set<Int64> {
        Set(customMouseButtonMappings.map { $0.buttonNumber })
    }
}
