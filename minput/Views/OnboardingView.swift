import SwiftUI

/// Onboarding view shown when accessibility permission is not granted
struct OnboardingView: View {
    var permissionManager: PermissionManager
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)
                
                Text("Welcome to minput")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("A lightweight input remapper for external mice and keyboards")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Divider()
            
            // Permission explanation
            VStack(alignment: .leading, spacing: 16) {
                Text("Accessibility Permission Required")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    permissionRow(
                        icon: "hand.tap",
                        title: "Intercept Input Events",
                        description: "To remap mouse buttons and keyboard keys"
                    )
                    
                    permissionRow(
                        icon: "scroll",
                        title: "Modify Scroll Direction",
                        description: "To reverse scrolling for external mice"
                    )
                    
                    permissionRow(
                        icon: "keyboard",
                        title: "Send Key Commands",
                        description: "To trigger Mission Control and other actions"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary)
            .cornerRadius(12)
            
            // Status
            HStack {
                if permissionManager.hasAccessibilityPermission {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Permission granted!")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Permission not yet granted")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            
            // Action buttons
            VStack(spacing: 12) {
                if permissionManager.hasAccessibilityPermission {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        permissionManager.openAccessibilitySettings()
                    } label: {
                        Text("Open System Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("After granting permission, return here to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(32)
        .frame(width: 420)
    }
    
    private func permissionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView(
        permissionManager: PermissionManager.shared,
        isPresented: .constant(true)
    )
}
