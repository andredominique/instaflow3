import SwiftUI
import AppKit

// MARK: - Drive Theme Palette with Dark Mode Support
fileprivate enum DriveTheme {
    static let pageBG = Color.adaptiveBackground
    static let panelBG = Color.adaptivePanelBackground
    static let line = Color.adaptiveLine
    static let buttonBlue = Color.blue // Add this new color definition
}

// MARK: - Color Extensions for Dark Mode
extension Color {
    static let adaptiveBackground = Color(nsColor: .controlBackgroundColor)
    static let adaptivePanelBackground = Color(nsColor: .windowBackgroundColor)
    static let adaptiveLine = Color(nsColor: .separatorColor)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText: String = ""

    // UPDATED: Reduced right pane width and increased left min width
    private let rightPaneWidth: CGFloat = 290  // Restored to previous value
    private let leftMinWidth: CGFloat  = 0   // Reduced by a further 300px
    private let dividerWidth: CGFloat  = 1

    private let steps: [(title: String, id: Int, icon: String)] = [
        ("Pick Folders",    1, "folder"),
        ("Cull, Reorder & Style Images", 2, "square.on.square"),
        ("Generate Caption",   3, "text.quote"),
        ("Export",     4, "arrow.down.doc")
    ]

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: main flow
            VStack(spacing: 0) {
                header
                    .background(DriveTheme.pageBG) // breadcrumb/nav matches page background

                Divider()
                    .background(DriveTheme.line)

                content
                    .background(DriveTheme.panelBG)

                Divider()
                    .background(DriveTheme.line)

                footer
                    .background(DriveTheme.panelBG)
            }
            .frame(minWidth: leftMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1) // <- ensure left column wins hit-testing

            // VERTICAL DIVIDER
            Rectangle()
                .fill(DriveTheme.line)
                .frame(width: dividerWidth)
                .zIndex(1)

            // RIGHT: preview pane (now narrower)
            RightPreviewPane()
                .frame(width: rightPaneWidth)
                .background(DriveTheme.pageBG)
                .clipped()   // <- prevent overflow blocking clicks
                .zIndex(0)
        }
        .background(DriveTheme.pageBG)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            // Logo on the left (from Assets.xcassets -> InstaFlowLogo)
            HStack {
                Image("InstaFlowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 50)     // adjust 36–44 to taste
                    .padding(.vertical, 10) // top/bottom padding for the logo
                Spacer()
            }
            .padding(.leading, 8)

            // Center navigation
            HStack(spacing: 6) {
                ForEach(steps, id: \.id) { s in
                    Button { model.currentStep = s.id } label: {
                        Text(s.title)
                            .font(model.currentStep == s.id ? .title2 : .headline) // Active page gets bigger font
                            .fontWeight(model.currentStep == s.id ? .semibold : .regular) // Optional: make it bold too
                            .foregroundStyle(model.currentStep == s.id ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    if s.id != steps.last?.id {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 120)
        }
        .padding(.horizontal, 12)
        .frame(height: 70) // Set consistent header height
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        switch model.currentStep {
        case 1: FolderPickerView().padding(12)
        case 2: SelectionsView()
                  .padding(.leading, 12)  // Left padding
                  .padding(.trailing, 12) // Right padding
                  .padding(.top, 12)      // Top padding
                  .padding(.bottom, 0)    // No bottom padding
        case 3: CaptionsView().padding(0)
        case 4: FinalPreviewView().padding(12)
        default: FolderPickerView().padding(12)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            // Custom divider with no padding
            Rectangle()
                .fill(DriveTheme.line)
                .frame(height: 1)
            
            // Footer content with no top padding
            HStack {
                // Only show back button if we're not on step 1 (FolderPickerView)
                if model.currentStep > 1 {
                    Button {
                        model.currentStep = max(1, model.currentStep - 1)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DriveTheme.buttonBlue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [])
                } else {
                    // Add an empty view with the same width to maintain layout
                    Color.clear.frame(width: 80, height: 0)
                }

                Spacer()

                Text("Step \(model.currentStep) of 4")
                    .foregroundStyle(.secondary)

                Spacer()

                if model.currentStep != 4 {
                    Button {
                        model.currentStep = min(4, model.currentStep + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DriveTheme.buttonBlue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(DriveTheme.panelBG)
    }
}
