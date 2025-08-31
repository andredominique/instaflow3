import SwiftUI

@main
struct InstaFlowApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                    // Restored minimum window size constraints (previously reduced for smaller resizing)
                    // To allow smaller resizing again, set minWidth: 400, idealWidth: 800, minHeight: 300, idealHeight: 600
                    // Reduced minWidth by 200px to allow left window to be smaller
                    .frame(
                        minWidth: 1000,  // Reduced by 200px from 1200
                        idealWidth: 1280, // Reduced by 200px from 1480
                        maxWidth: 1600,
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
            .defaultSize(width: 1480, height: 820) // Restored from 800x600
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
