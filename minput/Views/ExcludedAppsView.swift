import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings for apps excluded from keyboard remapping
struct ExcludedAppsView: View {
    @Bindable var settings: Settings
    @State private var showingAppPicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Excluded Apps")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        showingAppPicker = true
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text("Keyboard mappings will be disabled in these apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if settings.excludedApps.isEmpty {
                    emptyState
                } else {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(settings.excludedApps) { app in
                                appRow(for: app)
                                
                                if app.id != settings.excludedApps.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(settings: settings, isPresented: $showingAppPicker)
        }
    }
    
    private var emptyState: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "xmark.app")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                
                Text("No excluded apps")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Keyboard mappings apply to all apps.\nAdd apps here to disable mappings for specific apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
    
    private func appRow(for app: ExcludedApp) -> some View {
        HStack {
            // App icon
            if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.appName)
                    .font(.callout)
                
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                removeApp(app)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
    
    private func removeApp(_ app: ExcludedApp) {
        settings.excludedApps.removeAll { $0.id == app.id }
    }
}

/// View for selecting an app to exclude
struct AppPickerView: View {
    @Bindable var settings: Settings
    @Binding var isPresented: Bool
    
    @State private var runningApps: [NSRunningApplication] = []
    @State private var searchText = ""
    
    var filteredApps: [NSRunningApplication] {
        let apps = runningApps.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            // Exclude already excluded apps and self
            guard !settings.excludedApps.contains(where: { $0.bundleIdentifier == bundleID }) else { return false }
            guard bundleID != Bundle.main.bundleIdentifier else { return false }
            return true
        }
        
        if searchText.isEmpty {
            return apps
        }
        
        return apps.filter { app in
            let name = app.localizedName ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            return name.localizedCaseInsensitiveContains(searchText) ||
                   bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select App to Exclude")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(8)
            .padding()
            
            // App list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps, id: \.processIdentifier) { app in
                        Button {
                            addApp(app)
                        } label: {
                            runningAppRow(app)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            
            Divider()
            
            // Browse button
            HStack {
                Button {
                    browseForApp()
                } label: {
                    Label("Browse...", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadRunningApps()
        }
    }
    
    private func runningAppRow(_ app: NSRunningApplication) -> some View {
        HStack {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.localizedName ?? "Unknown")
                    .font(.callout)
                    .foregroundStyle(.primary)
                
                Text(app.bundleIdentifier ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
    
    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    private func addApp(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        
        let iconData = app.icon?.tiffRepresentation
        
        let excludedApp = ExcludedApp(
            bundleIdentifier: bundleID,
            appName: app.localizedName ?? bundleID,
            iconData: iconData
        )
        
        settings.excludedApps.append(excludedApp)
        isPresented = false
    }
    
    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an application to exclude from keyboard mappings"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url),
               let bundleID = bundle.bundleIdentifier {
                
                let appName = bundle.infoDictionary?["CFBundleName"] as? String ??
                              bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                              url.deletingPathExtension().lastPathComponent
                
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let iconData = icon.tiffRepresentation
                
                let excludedApp = ExcludedApp(
                    bundleIdentifier: bundleID,
                    appName: appName,
                    iconData: iconData
                )
                
                settings.excludedApps.append(excludedApp)
                isPresented = false
            }
        }
    }
}

#Preview {
    ExcludedAppsView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
