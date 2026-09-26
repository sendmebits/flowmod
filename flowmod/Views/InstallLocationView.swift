import AppKit
import SwiftUI

/// Blocks first launch until FlowMod is copied into Applications. Closing the
/// window quits, so the menu bar app does not keep running from a disk image,
/// Downloads, or an App Translocation path.
@MainActor
final class InstallLocationWindowController: NSObject, NSWindowDelegate {
    static let shared = InstallLocationWindowController()

    private var windowController: NSWindowController?
    private var isMoving = false

    func show() {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = InstallLocationView()
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Move FlowMod to Applications"
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

    func setMoving(_ moving: Bool) {
        isMoving = moving
        windowController?.window?.standardWindowButton(.closeButton)?.isEnabled = !moving
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // A close in the middle of the copy would leave a partial bundle behind.
        guard !isMoving else { return false }
        NSApp.terminate(nil)
        return false
    }
}

struct InstallLocationView: View {
    @State private var isMoving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Label("Move FlowMod to Applications", systemImage: "folder")
                    .font(.title.bold())
                    .foregroundStyle(Color.accentColor)

                Text("FlowMod has to live in your Applications folder so input access and updates keep working.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                if isMoving {
                    ProgressView()
                        .controlSize(.small)
                    Text("Moving to Applications…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button(errorMessage == nil ? "Move to Applications" : "Try Again") {
                    moveToApplications()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isMoving)
            }
        }
        .padding(32)
        .frame(width: 480, height: 280)
        .background(.regularMaterial)
    }

    private func moveToApplications() {
        isMoving = true
        errorMessage = nil
        InstallLocationWindowController.shared.setMoving(true)

        Task {
            do {
                let destination = try await Task.detached {
                    try InstallLocation.moveToApplications()
                }.value
                try InstallLocation.relaunchInstalledCopy(at: destination)
            } catch {
                errorMessage = error.localizedDescription
                isMoving = false
                InstallLocationWindowController.shared.setMoving(false)
            }
        }
    }
}
