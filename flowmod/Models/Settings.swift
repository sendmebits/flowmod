import Foundation
import Observation
import ServiceManagement

/// Smooth scrolling intensity options
enum SmoothScrolling: String, CaseIterable, Identifiable, Codable {
    case off = "Off"
    case smooth = "Smooth"
    case verySmooth = "Very Smooth"

    var id: String { rawValue }
}

/// Main settings store for the app.
///
/// Per-device settings (scroll, buttons, gestures) live in `ProfileSettings`:
/// `defaultProfile` persists under the original UserDefaults keys (so existing
/// installs upgrade without migration), and `mouseProfiles` holds optional
/// per-mouse overrides keyed by "vendorID:productID". Global settings
/// (launch at login, drag threshold, etc.) remain here.
@MainActor
@Observable
class Settings {
    static let shared = Settings()

    /// Flag to suppress didSet UserDefaults writes during initialization
    private var isLoading = true

    // MARK: - Per-Device Profiles

    /// Settings used by any mouse without its own profile (and by everything
    /// when `perMouseSettingsEnabled` is off). Persists under the legacy keys.
    let defaultProfile: ProfileSettings

    /// Per-mouse profiles, keyed by `HIDDevice.deviceKey` ("vendorID:productID").
    /// Only consulted when `perMouseSettingsEnabled` is true.
    private(set) var mouseProfiles: [String: ProfileSettings] = [:]

    /// Opt-in master switch for per-mouse settings. When off, all mice follow
    /// the default profile (existing behavior); profiles are retained but inert.
    var perMouseSettingsEnabled: Bool = false {
        didSet { if !isLoading { UserDefaults.standard.set(perMouseSettingsEnabled, forKey: "perMouseSettingsEnabled") } }
    }

    /// Resolve the profile to use for a device key (nil key = unattributed
    /// event or no device). Falls back to the default profile.
    func profile(forKey key: String?) -> ProfileSettings {
        guard perMouseSettingsEnabled, let key, let profile = mouseProfiles[key] else {
            return defaultProfile
        }
        return profile
    }

    /// Create a profile for a mouse, starting as a copy of the current
    /// default settings. Returns the existing profile if one is present.
    @discardableResult
    func createProfile(forKey key: String, displayName: String) -> ProfileSettings {
        if let existing = mouseProfiles[key] { return existing }
        let profile = ProfileSettings()
        profile.copyValues(from: defaultProfile)
        profile.displayName = displayName
        profile.onChange = { [weak self] in self?.saveMouseProfiles() }
        mouseProfiles[key] = profile
        saveMouseProfiles()
        LogManager.shared.log("Created profile for \(displayName) [\(key)]", category: "Settings")
        return profile
    }

    /// Delete a mouse's profile; that mouse goes back to the default settings.
    func removeProfile(forKey key: String) {
        guard mouseProfiles.removeValue(forKey: key) != nil else { return }
        saveMouseProfiles()
        LogManager.shared.log("Removed profile [\(key)]", category: "Settings")
    }

    // MARK: - Master Toggles

    /// Master toggle for mouse interception (scroll, buttons, drag gestures)
    var mouseEnabled: Bool = true {
        didSet { if !isLoading { UserDefaults.standard.set(mouseEnabled, forKey: "mouseEnabled") } }
    }

    // MARK: - General Settings
    var launchAtLogin: Bool = true {
        didSet { if !isLoading { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") } }
    }

    var dragThreshold: Double = 10.0 {
        didSet { if !isLoading { UserDefaults.standard.set(dragThreshold, forKey: "dragThreshold") } }
    }

    /// Override device detection - assume external mouse is always connected
    var assumeExternalMouse: Bool = false {
        didSet { if !isLoading { UserDefaults.standard.set(assumeExternalMouse, forKey: "assumeExternalMouse") } }
    }

    /// Enable debug logging
    var debugLogging: Bool = false {
        didSet { if !isLoading { UserDefaults.standard.set(debugLogging, forKey: "debugLogging") } }
    }

    // MARK: - Initialization

    private init() {
        defaultProfile = ProfileSettings()

        // Load master toggles from UserDefaults (default to true if not set)
        if UserDefaults.standard.object(forKey: "mouseEnabled") == nil {
            mouseEnabled = true
        } else {
            mouseEnabled = UserDefaults.standard.bool(forKey: "mouseEnabled")
        }

        // Load general settings
        if UserDefaults.standard.object(forKey: "launchAtLogin") != nil {
            launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        } else {
            // First launch: default to true and register
            launchAtLogin = true
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        }

        if UserDefaults.standard.object(forKey: "dragThreshold") != nil {
            dragThreshold = UserDefaults.standard.double(forKey: "dragThreshold")
        }

        assumeExternalMouse = UserDefaults.standard.bool(forKey: "assumeExternalMouse")
        debugLogging = UserDefaults.standard.bool(forKey: "debugLogging")
        perMouseSettingsEnabled = UserDefaults.standard.bool(forKey: "perMouseSettingsEnabled")

        // Load the default profile from the legacy keys, then per-mouse profiles
        loadDefaultProfile()
        loadMouseProfiles()

        // Wire persistence AFTER loading so bulk assignment doesn't re-save
        defaultProfile.onChange = { [weak self] in self?.saveDefaultProfile() }
        for profile in mouseProfiles.values {
            profile.onChange = { [weak self] in self?.saveMouseProfiles() }
        }

        isLoading = false
    }

    // MARK: - Default Profile Persistence (legacy keys)

    private let customMouseButtonMappingsKey = "customMouseButtonMappings"
    private let middleDragMappingsKey = "middleDragMappings"
    private let mouseProfilesKey = "mouseProfiles"

    private func loadDefaultProfile() {
        let defaults = UserDefaults.standard
        let p = defaultProfile

        // Bool/enum settings default to true (or .verySmooth) when not set
        if defaults.object(forKey: "reverseScrollEnabled") != nil {
            p.reverseScrollEnabled = defaults.bool(forKey: "reverseScrollEnabled")
        }
        if let rawValue = defaults.string(forKey: "smoothScrolling"),
           let value = SmoothScrolling(rawValue: rawValue) {
            p.smoothScrolling = value
        }
        if defaults.object(forKey: "shiftHorizontalScroll") != nil {
            p.shiftHorizontalScroll = defaults.bool(forKey: "shiftHorizontalScroll")
        }
        if defaults.object(forKey: "optionPrecisionScroll") != nil {
            p.optionPrecisionScroll = defaults.bool(forKey: "optionPrecisionScroll")
        }
        if defaults.object(forKey: "precisionScrollMultiplier") != nil {
            p.precisionScrollMultiplier = defaults.double(forKey: "precisionScrollMultiplier")
        }
        if defaults.object(forKey: "controlFastScroll") != nil {
            p.controlFastScroll = defaults.bool(forKey: "controlFastScroll")
        }
        if defaults.object(forKey: "fastScrollMultiplier") != nil {
            p.fastScrollMultiplier = defaults.double(forKey: "fastScrollMultiplier")
        }
        if defaults.object(forKey: "commandZoomScroll") != nil {
            p.commandZoomScroll = defaults.bool(forKey: "commandZoomScroll")
        }
        if defaults.object(forKey: "continuousGestures") != nil {
            p.continuousGestures = defaults.bool(forKey: "continuousGestures")
        }

        if let data = defaults.data(forKey: customMouseButtonMappingsKey),
           let mappings = try? JSONDecoder().decode([CustomMouseButtonMapping].self, from: data) {
            p.customMouseButtonMappings = mappings
        }

        if let data = defaults.data(forKey: middleDragMappingsKey),
           let mappings = try? JSONDecoder().decode([DragDirection: MouseAction].self, from: data) {
            p.middleDragMappings = mappings
        }

        if p.middleDragMappings.isEmpty {
            p.middleDragMappings = [
                .up: .missionControl,
                .down: .appExpose,
                .left: .switchSpaceRight,
                .right: .switchSpaceLeft
            ]
        }
    }

    private func saveDefaultProfile() {
        let defaults = UserDefaults.standard
        let p = defaultProfile

        defaults.set(p.reverseScrollEnabled, forKey: "reverseScrollEnabled")
        defaults.set(p.smoothScrolling.rawValue, forKey: "smoothScrolling")
        defaults.set(p.shiftHorizontalScroll, forKey: "shiftHorizontalScroll")
        defaults.set(p.optionPrecisionScroll, forKey: "optionPrecisionScroll")
        defaults.set(p.precisionScrollMultiplier, forKey: "precisionScrollMultiplier")
        defaults.set(p.controlFastScroll, forKey: "controlFastScroll")
        defaults.set(p.fastScrollMultiplier, forKey: "fastScrollMultiplier")
        defaults.set(p.commandZoomScroll, forKey: "commandZoomScroll")
        defaults.set(p.continuousGestures, forKey: "continuousGestures")

        if let data = try? JSONEncoder().encode(p.customMouseButtonMappings) {
            defaults.set(data, forKey: customMouseButtonMappingsKey)
        }
        if let data = try? JSONEncoder().encode(p.middleDragMappings) {
            defaults.set(data, forKey: middleDragMappingsKey)
        }
    }

    // MARK: - Mouse Profile Persistence

    private func loadMouseProfiles() {
        guard let data = UserDefaults.standard.data(forKey: mouseProfilesKey),
              let decoded = try? JSONDecoder().decode([String: ProfileData].self, from: data) else {
            return
        }
        mouseProfiles = decoded.mapValues { ProfileSettings(data: $0) }
    }

    private func saveMouseProfiles() {
        let snapshot = mouseProfiles.mapValues { $0.data }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: mouseProfilesKey)
        }
    }
}
