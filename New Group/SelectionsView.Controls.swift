//
// Auto-split: controls
//
import SwiftUI
extension SelectionsView {
var controls: some View {
        HStack(spacing: 12) {
            Text("Style Images:")
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // UPDATED: Zoom to Fill button with standard bordered style when inactive
            Group {
                if model.project.zoomToFill {
                    // Active state - blue background with white text
                    Button {
                        model.project.zoomToFill.toggle()
                    } label: {
                        Label("Zoom to Fill", systemImage: "rectangle.inset.filled")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 120)
                    .help("Images fill the aspect ratio (may crop)")
                } else {
                    // Inactive state - standard bordered style
                    Button {
                        model.project.zoomToFill.toggle()
                    } label: {
                        Label("Zoom to Fill", systemImage: "viewfinder")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .padding(.vertical, 4)
                    .frame(minWidth: 120)
                    .help("Images fit within aspect ratio (no cropping)")
                }
            }
            
            // NEW: Background color selector with quick options - ALWAYS ACTIVE
            HStack(spacing: 4) {
                Text("Background:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80) // Ensures 'Background:' text stays intact when resizing
                
                // Quick color buttons and custom picker with REDUCED SIZE
                HStack(spacing: 2) {
                    ForEach(ColorOption.allCases.filter { $0 != .custom }, id: \ .self) { option in
                        Button {
                            if selectedColorOption != option || backgroundColor != option.color {
                                selectedColorOption = option
                                backgroundColor = option.color
                                // Sync to global project color
                                let ns = NSColor(option.color)
                                let colorData = ColorData(
                                    red: Double(ns.redComponent),
                                    green: Double(ns.greenComponent),
                                    blue: Double(ns.blueComponent),
                                    opacity: 1
                                )
                                if model.project.aspect == .story9x16 {
                                    model.project.reelBorderColor = colorData
                                } else {
                                    model.project.carouselBorderColor = colorData
                                }
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(option.color)
                                .frame(width: 20, height: 20) // REDUCED from 24x24
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(
                                            selectedColorOption == option ? Color.blue : Color.gray.opacity(0.3),
                                            lineWidth: selectedColorOption == option ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }

                    // Custom color picker button with paintpalette icon - DIRECT MAC COLOR PICKER
                    Button {
                        selectedColorOption = .custom
                        openMacColorPicker()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.clear)
                                .frame(width: 20, height: 20) // REDUCED from 24x24
                                .overlay(
                                    Image(systemName: "paintpalette")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16) // REDUCED from 18x18
                                        .foregroundColor(.accentColor)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(
                                            selectedColorOption == .custom ? Color.blue : Color.gray.opacity(0.3),
                                            lineWidth: selectedColorOption == .custom ? 2 : 1
                                        )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Custom color")
                }
                // REMOVED disabled and opacity modifiers to keep always active
                .help("Background color for images and borders")
            }
            
            // NEW: Border width slider
            HStack(spacing: 4) {
                Text("Border:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60) // Ensures 'Border:' text stays intact when resizing
                
                Slider(
                    value: $borderWidth,
                    in: 0...20,
                    step: 1
                )
                .onChange(of: borderWidth) { _, newVal in
                    // Sync to global project border width on every change
                    if model.project.aspect == .story9x16 {
                        model.project.reelBorderPx = Int(newVal)
                    } else {
                        model.project.carouselBorderPx = Int(newVal)
                    }
                }
                .frame(width: 80)
                .help("Add border around images")
                
                Text("\(Int(borderWidth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
            }
            
            Text("Aspect:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60) // Ensures 'Aspect:' text stays intact when resizing

            // UPDATED: Aspect ratio buttons with standard bordered style when inactive
            HStack(spacing: 4) {
                Group {
                    if model.project.aspect == .feed4x5 {
                        // Active state - blue background with white text
                        Button {
                            model.setAspectRatio(.feed4x5)
                        } label: {
                            Text("4:5")
                                .frame(minWidth: 40) // Ensures button stays intact when resizing
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Instagram Feed Post aspect ratio")
                    } else {
                        // Inactive state - standard bordered style
                        Button {
                            model.setAspectRatio(.feed4x5)
                        } label: {
                            Text("4:5")
                                .frame(minWidth: 40) // Ensures button stays intact when resizing
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .padding(.vertical, 4)
                        .help("Instagram Feed Post aspect ratio")
                    }
                }
                
                Group {
                    if model.project.aspect == .story9x16 {
                        // Active state - blue background with white text
                        Button {
                            model.setAspectRatio(.story9x16)
                        } label: {
                            Text("9:16")
                                .frame(minWidth: 40) // Ensures button stays intact when resizing
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Instagram Story aspect ratio")
                    } else {
                        // Inactive state - standard bordered style
                        Button {
                            model.setAspectRatio(.story9x16)
                        } label: {
                            Text("9:16")
                                .frame(minWidth: 40) // Ensures button stays intact when resizing
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .padding(.vertical, 4)
                        .help("Instagram Story aspect ratio")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
