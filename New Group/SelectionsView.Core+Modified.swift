import SwiftUI
import AppKit

extension SelectionsView {
    // Add command key state
    @State var isCommandPressed = false
    @State var commandKeyMonitor: Any?
    
    // MARK: - Modified Key and Scroll Monitoring
    private func setupShiftKeyMonitoring() {
        // Monitor command and shift key states
        shiftKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let flags = event.modifierFlags
            let wasShiftPressed = isShiftPressed
            let wasCommandPressed = isCommandPressed
            
            isShiftPressed = flags.contains(.shift)
            isCommandPressed = flags.contains(.command)
            
            // Update hover state when either modifier changes
            if wasShiftPressed != isShiftPressed || wasCommandPressed != isCommandPressed {
                DispatchQueue.main.async {
                    if !(isShiftPressed || isCommandPressed) {
                        hoveredItemID = nil // Clear hover when neither key is pressed
                    }
                }
            }
            
            return event
        }
        
        // Monitor scroll gestures
        scrollGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            // Allow zoom when either shift or command is pressed
            if (isShiftPressed || isCommandPressed) && hoveredItemID != nil {
                DispatchQueue.main.async {
                    handleZoomGesture(deltaY: event.deltaY, forImageId: hoveredItemID!)
                }
                return nil // Consume the event when we're zooming
            }
            return event // Pass through all other scroll events
        }
    }
    
    private func tearDownShiftKeyMonitoring() {
        if let monitor = shiftKeyMonitor {
            NSEvent.removeMonitor(monitor)
            shiftKeyMonitor = nil
        }
        if let monitor = scrollGestureMonitor {
            NSEvent.removeMonitor(monitor)
            scrollGestureMonitor = nil
        }
    }
}