//
// Auto-split: header
//
import SwiftUI
extension SelectionsView {
var header: some View {
        HStack(spacing: 12) {
            Text("Cull & Reorder:")
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer() // Separates left and right sections
            
            Button {
                selectAll()
            } label: {
                Label("Keep All", systemImage: "checkmark.square")
            }
            .buttonStyle(BorderedButtonStyle())
            .padding(.vertical, 4)
            .disabled(model.project.images.isEmpty)

            Button {
                deselectAll()
            } label: {
                Label("Cull All", systemImage: "square")
            }
            .buttonStyle(BorderedButtonStyle())
            .padding(.vertical, 4)
            .disabled(model.project.images.isEmpty)
            
            Divider().frame(height: 18)
            
            // Disabled section with text, hide button, and send to end button
            HStack(spacing: 8) {
                // Disabled label

                // Hide toggle button - Use Group for conditional rendering
                Group {
                    if !showDisabled {
                        // Active state - blue background with white text
                        Button {
                            showDisabled.toggle()
                        } label: {
                            Label(
                                "Hide Culled",
                                systemImage: "eye"
                            )
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(minWidth: 120)
                        .help("Hide culled images (ON)")
                    } else {
                        // Inactive state - standard bordered style
                        Button {
                            showDisabled.toggle()
                        } label: {
                            Label("Hide Culled", systemImage: "eye.slash")
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .padding(.vertical, 4)
                        .frame(minWidth: 120)
                        .help("Hide culled images (OFF)")
                    }
                }
                
                // Auto Send to End toggle button - Updated with conditional rendering
                Group {
                    if autoSendToEnd {
                        // Active state - blue background with white text
                        Button {
                            autoSendToEnd.toggle()
                        } label: {
                            Label(
                                "Send to End",
                                systemImage: "arrow.down.to.line.circle.fill"
                            )
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(minWidth: 140)
                        .help("Auto-send disabled images to end (ON)")
                    } else {
                        // Inactive state - standard bordered style
                        Button {
                            autoSendToEnd.toggle()
                        } label: {
                            Label("Send to End", systemImage: "arrow.down.to.line.circle")
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .padding(.vertical, 4)
                        .frame(minWidth: 140)
                        .help("Auto-send disabled images to end (OFF)")
                    }
                }
                
                Divider().frame(height: 18)
                
                // Randomize button (now has more space)
                Button {
                    randomizeOrder()
                } label: {
                    Label("Randomize", systemImage: "shuffle")
                }
                .buttonStyle(BorderedButtonStyle())
                .padding(.vertical, 4)
                .layoutPriority(1)

                Button {
                    showResetConfirm = true
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(BorderedButtonStyle())
                .padding(.vertical, 4)
                .layoutPriority(1)
                
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
