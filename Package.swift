// swift-tools-version: 6.0
import PackageDescription

// Exercise the real input pipeline without launching the menu-bar app or
// installing an event tap. The injected click sink keeps tests off the desktop.
let package = Package(
    name: "FlowModInputTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FlowModInput",
            path: "flowmod",
            exclude: ["Assets.xcassets", "Views", "FlowModApp.swift", "Info.plist",
                      "flowmod.entitlements", "Managers/PermissionManager.swift", "Managers/UpdateManager.swift"],
            sources: ["Models", "Managers/InputInterceptor.swift", "Managers/MiddleClick.swift",
                      "Managers/DeviceManager.swift", "Managers/DockSwipeSimulator.swift",
                      "Managers/LogManager.swift", "Managers/SymbolicHotkeys.swift"]
        ),
        .testTarget(name: "FlowModInputTests", dependencies: ["FlowModInput"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
