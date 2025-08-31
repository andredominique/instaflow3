import SwiftUI

@main
struct InstaFlowApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // UPDATED: Increased minimum width to prevent overflow
                .frame(
                    minWidth: 1200,  // Increased from 1200
                    idealWidth: 1480, // Increased from 1280
                    maxWidth: 1600,   // Increased from 1400
                    minHeight: 720,
                    idealHeight: 820,
                    maxHeight: 900
                )
        }
        // UPDATED: Use default window style to show title bar with full screen button
        .windowStyle(.automatic)
        // Slim toolbar style (in case any toolbar is ever added)
        .windowToolbarStyle(.unifiedCompact)
        // Allow window resizing
        .windowResizability(.contentMinSize)
        // Start at a nice default size
        .defaultSize(width: 1480, height: 820) // Updated from 1280
        // ENABLE FULL SCREEN - Add commands for full screen support
        .commands {
            CommandGroup(replacing: .windowSize) {
                Button("Enter Full Screen") {
                    if let window = NSApp.keyWindow {
                        window.toggleFullScreen(nil)
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}
