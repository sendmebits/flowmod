import SwiftUI
import AppKit
import Observation
import ServiceManagement

/// Tracks whether the current onboarding experience has been completed.
/// Existing users who saw the legacy automatic permission prompt are migrated
/// so an app update doesn't unexpectedly show first-run setup again.
@MainActor
@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()

    private static let currentVersion = 1
    private static let completedVersionKey = "onboardingCompletedVersion"
    private static let legacyPromptedKey = "hasPromptedForAccessibility"

    private(set) var isCompleted: Bool

    private init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Self.completedVersionKey) == nil,
           defaults.bool(forKey: Self.legacyPromptedKey) {
            defaults.set(Self.currentVersion, forKey: Self.completedVersionKey)
        }

        isCompleted = defaults.integer(forKey: Self.completedVersionKey) >= Self.currentVersion
    }

    func complete() {
        if Settings.shared.launchAtLogin {
            try? SMAppService.mainApp.register()
        }
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.completedVersionKey)
        isCompleted = true
    }
}

/// Owns the one setup window without adding a normal app window that would
/// appear on every launch of this menu-bar-only app.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var windowController: NSWindowController?

    func show() {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = OnboardingView {
            OnboardingWindowController.shared.close()
        }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to FlowMod"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.delegate = self
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        windowController?.close()
        windowController = nil
    }
}

struct OnboardingView: View {
    private enum Step {
        case welcome
        case permission
        case verification
    }

    var permissionManager = PermissionManager.shared
    var inputInterceptor = InputInterceptor.shared
    var deviceManager = DeviceManager.shared
    let onClose: () -> Void

    @State private var step: Step = .welcome
    @State private var permissionRequested = false

    private var isReady: Bool {
        permissionManager.hasAccessibilityPermission && inputInterceptor.isRunning
    }

    private var externalMouseName: String? {
        deviceManager.connectedDevices.first(where: { $0.isMouse && !$0.isAppleDevice })?.displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .permission:
                    permissionStep
                case .verification:
                    verificationStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 430)
        .background(.regularMaterial)
        .onAppear {
            permissionManager.checkPermission()
        }
        .onChange(of: permissionManager.hasAccessibilityPermission) { _, granted in
            guard granted else { return }
            startFlowMod()
            step = .verification

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                OnboardingWindowController.shared.show()
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            indicatorDot(active: step == .welcome, completed: step != .welcome)
            Capsule().fill(step == .welcome ? Color.secondary.opacity(0.25) : Color.accentColor)
                .frame(width: 28, height: 2)
            indicatorDot(active: step == .permission, completed: step == .verification)
            Capsule().fill(step == .verification ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 28, height: 2)
            indicatorDot(active: step == .verification, completed: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepAccessibilityLabel)
    }

    private var stepAccessibilityLabel: String {
        switch step {
        case .welcome: return "Setup step 1 of 3, Welcome"
        case .permission: return "Setup step 2 of 3, Accessibility"
        case .verification: return "Setup step 3 of 3, Verification"
        }
    }

    private func indicatorDot(active: Bool, completed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active || completed ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 10, height: 10)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "computermouse.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome to FlowMod")
                    .font(.largeTitle.bold())
                Text("Make your external mouse feel at home on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 28) {
                welcomeFeature(icon: "water.waves", title: "Smooth scrolling")
                welcomeFeature(icon: "button.programmable", title: "Button actions")
                welcomeFeature(icon: "hand.draw", title: "Mouse gestures")
            }

            if let externalMouseName {
                Label("Detected: \(externalMouseName)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label("No external mouse detected yet — you can connect one later", systemImage: "computermouse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            onboardingButtons(primaryTitle: "Continue", primaryAction: continueFromWelcome)
        }
        .padding(28)
    }

    private func welcomeFeature(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Allow Accessibility Access", systemImage: "lock.shield.fill")
                    .font(.title.bold())
                    .foregroundStyle(Color.accentColor)

                Text("FlowMod needs Accessibility access to customize external-mouse scrolling, buttons, and gestures, and to perform actions you assign.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                permissionDetail(
                    icon: "computermouse",
                    text: "FlowMod intercepts mouse events so it can improve them in real time."
                )
                permissionDetail(
                    icon: "keyboard",
                    text: "It doesn't intercept or remap your physical keyboard."
                )
                permissionDetail(
                    icon: "eye.slash",
                    text: "Your settings and mouse activity stay on your Mac."
                )
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            if permissionRequested {
                Label(
                    "Use the macOS alert to open System Settings, then turn on FlowMod.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Not Now") { onClose() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Open System Settings") {
                    permissionManager.openAccessibilitySettings()
                }

                Button("Grant Access") {
                    permissionRequested = true
                    permissionManager.requestPermission()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }

    private func permissionDetail(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.callout)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
        }
    }

    private var verificationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text(isReady ? "FlowMod is ready" : "Let's verify your setup")
                    .font(.title.bold())
                Text(isReady
                     ? "Your mouse enhancements are active."
                     : "FlowMod is checking the required components.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                verificationRow(
                    title: "Accessibility access",
                    detail: permissionManager.hasAccessibilityPermission ? "Granted" : "Required",
                    success: permissionManager.hasAccessibilityPermission
                )
                Divider().padding(.leading, 44)
                verificationRow(
                    title: "Mouse interceptor",
                    detail: inputInterceptor.isRunning ? "Running" : "Not running",
                    success: inputInterceptor.isRunning
                )
                Divider().padding(.leading, 44)
                verificationRow(
                    title: "External mouse",
                    detail: externalMouseName ?? "Not connected — optional for setup",
                    success: externalMouseName != nil,
                    optional: true
                )
            }
            .padding(.horizontal, 14)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            if let startupError = inputInterceptor.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !inputInterceptor.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting FlowMod…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                if !isReady {
                    Button("Accessibility Settings") {
                        permissionManager.openAccessibilitySettings()
                    }
                }

                Spacer()

                if !inputInterceptor.isRunning {
                    Button("Try Again") { retrySetup() }
                }

                Button("Finish") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isReady)
            }
        }
        .padding(32)
    }

    private func verificationRow(
        title: String,
        detail: String,
        success: Bool,
        optional: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: success ? "checkmark.circle.fill" : optional ? "circle.dashed" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(success ? Color.green : optional ? Color.secondary : Color.orange)
                .frame(width: 24)

            Text(title)
                .font(.callout)

            Spacer()

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
    }

    private func onboardingButtons(primaryTitle: String, primaryAction: @escaping () -> Void) -> some View {
        HStack {
            Button("Not Now") { onClose() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func continueFromWelcome() {
        permissionManager.checkPermission()
        if permissionManager.hasAccessibilityPermission {
            startFlowMod()
            step = .verification
        } else {
            step = .permission
        }
    }

    private func startFlowMod() {
        guard permissionManager.hasAccessibilityPermission else { return }
        inputInterceptor.start(settings: Settings.shared, deviceManager: deviceManager)
    }

    private func retrySetup() {
        permissionManager.checkPermission()
        if permissionManager.hasAccessibilityPermission {
            startFlowMod()
        } else {
            step = .permission
        }
    }

    private func finish() {
        guard isReady else { return }
        OnboardingManager.shared.complete()
        onClose()
    }
}

#Preview {
    OnboardingView(onClose: {})
}
