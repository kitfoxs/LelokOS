import SwiftUI

@main
struct LelokOSApp: App {
    @StateObject private var shellManager = ShellManager()
    
    var body: some Scene {
        WindowGroup("Lelock OS") {
            TerminalView()
                .environmentObject(shellManager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    // Future: multi-tab support
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(shellManager)
        }
    }
}
