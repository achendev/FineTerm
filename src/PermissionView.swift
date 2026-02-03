import Cocoa
import SwiftUI

struct PermissionManager {
    static func checkAccessibility() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    static func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
}

struct PermissionView: View {
    @State private var isAccessibilityGranted = PermissionManager.checkAccessibility()
    let onPermissionGranted: () -> Void
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(radius: 4)
            
            VStack(spacing: 8) {
                Text("Permissions Required")
                    .font(.headline)
                Text("FineTerm needs Accessibility permissions to intercept keyboard shortcuts and control Terminal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Accessibility",
                    isGranted: isAccessibilityGranted,
                    action: {
                        PermissionManager.requestAccessibility()
                    }
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 380)
        .onReceive(timer) { _ in
            let granted = PermissionManager.checkAccessibility()
            if granted && !isAccessibilityGranted {
                isAccessibilityGranted = true
                // Add a small delay so the user sees the green checkmark
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onPermissionGranted()
                }
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            if !isGranted {
                Button("Fix...") {
                    action()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
