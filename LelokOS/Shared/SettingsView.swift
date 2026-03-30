import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var shell: ShellManager
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    @AppStorage("terminalTheme") private var theme: String = "dark"
    
    var body: some View {
        TabView {
            // General Settings
            Form {
                Section("Terminal") {
                    Slider(value: $fontSize, in: 10...24, step: 1) {
                        Text("Font Size: \(Int(fontSize))pt")
                    }
                    
                    Picker("Theme", selection: $theme) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Lelock Blue").tag("blue")
                    }
                }
                
                Section("Workspace") {
                    LabeledContent("Home Directory") {
                        Text("~/Documents/LelockUniverse/")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .frame(width: 450, height: 300)
            
            // AI Settings (Phase 2)
            Form {
                Section("Claude API") {
                    SecureField("API Key", text: .constant(""))
                        .disabled(true)
                    Text("Coming in Phase 2")
                        .foregroundColor(.secondary)
                }
                
                Section("GitHub Copilot") {
                    SecureField("API Key", text: .constant(""))
                        .disabled(true)
                    Text("Coming in Phase 2")
                        .foregroundColor(.secondary)
                }
            }
            .tabItem {
                Label("AI Agents", systemImage: "brain")
            }
            .frame(width: 450, height: 300)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(ShellManager())
}
