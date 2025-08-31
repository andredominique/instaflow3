import SwiftUI

@main
struct InstaFlowApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                    // Reduce minimum window size constraints to allow smaller resizing
                    .frame(
                        minWidth: 400,  // Reduced from 1200
                        idealWidth: 800, // Reduced from 1480
                        maxWidth: 1600,
                        minHeight: 300, // Reduced from 720
                        idealHeight: 600,
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
            .defaultSize(width: 800, height: 600) // Reduced from 1480x820
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
