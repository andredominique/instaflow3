import SwiftUI
import AppKit

struct FolderPickerView: View {
    @EnvironmentObject var model: AppModel

    // UI state
    @State private var subfolders: [URL] = []
    @State private var selection: Set<String> = [] // store by absolute path
    @State private var folderCounts: [String: Int] = [:]

    // For Shift-click range selection
    @State private var lastAnchorIndex: Int? = nil
    
    // Track last known selection to avoid unnecessary reloads
    @State private var lastSelection: Set<String> = []

    // Persist the last root folder
    private let defaultsKeyLastRoot = "InstaFlow.lastRootFolderPath"

    // Image file extensions we count (non-recursive)
    private let imageExts: Set<String> = [
        "jpg","jpeg","png","heic","heif","tif","tiff","gif","bmp","webp"
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folders (\(subfolders.count))")
                        .font(.headline)
                    Text(model.project.watchPath?.path ?? "Not set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    chooseRoot()
                } label: {
                    Label(model.project.watchPath == nil ? "Choose…" : "Change…", systemImage: "folder")
                }
                Button {
                    refreshSubfolders()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.project.watchPath == nil)

                // Always-present Select / Deselect buttons
                Button {
                    selectAll()
                } label: {
                    Label("Select All", systemImage: "checkmark.square")
                }
                .disabled(subfolders.isEmpty || allSelected)

                Button {
                    deselectAll()
                } label: {
                    Label("Deselect All", systemImage: "square")
                }
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Two columns, filled by column-first order (left column fills fully, then right)
            ScrollView {
                HStack(alignment: .top, spacing: 8) {
                    // Left column: first ceil(n/2) items
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(leftColumn, id: \.path) { url in
                            FolderTile(
                                url: url,
                                count: folderCounts[url.path],
                                isSelected: selection.contains(url.path),
                                onClick: { modifiers in
                                    handleClick(path: url.path, modifiers: modifiers)
                                }
                            )
                        }
                    }
                    // Right column: remaining items
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(rightColumn, id: \.path) { url in
                            FolderTile(
                                url: url,
                                count: folderCounts[url.path],
                                isSelected: selection.contains(url.path),
                                onClick: { modifiers in
                                    handleClick(path: url.path, modifiers: modifiers)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            // Restore last root if none set
            if model.project.watchPath == nil,
               let saved = UserDefaults.standard.string(forKey: defaultsKeyLastRoot),
               FileManager.default.fileExists(atPath: saved) {
                model.project.watchPath = URL(fileURLWithPath: saved)
            }

            // Rebuild UI state from model
            selection = Set(model.project.selectedFolders.map { $0.path })
            lastSelection = selection
            
            // Only refresh if we don't have subfolders yet
            if subfolders.isEmpty {
                refreshSubfolders()
            }
        }
    }

    // MARK: - Derived

    private var allSelected: Bool {
        !subfolders.isEmpty && selection.count == subfolders.count
    }

    private var leftColumnCount: Int {
        (subfolders.count + 1) / 2 // ceil(n/2)
    }
    private var leftColumn: ArraySlice<URL> {
        subfolders.prefix(leftColumnCount)
    }
    private var rightColumn: ArraySlice<URL> {
        subfolders.suffix(subfolders.count - leftColumnCount)
    }

    // MARK: - Actions

    // Click handler with modifier support (Shift for range select)
    private func handleClick(path: String, modifiers: NSEvent.ModifierFlags) {
        guard let idx = indexOfPath(path) else {
            toggle(path: path)
            return
        }

        if modifiers.contains(.shift), let anchor = lastAnchorIndex, anchor != idx {
            // Range select: add all items between anchor and current to selection
            let lower = min(anchor, idx)
            let upper = max(anchor, idx)
            let pathsInRange = subfolders[lower...upper].map { $0.path }
            selection.formUnion(pathsInRange)
            applySelection()
        } else {
            // Simple toggle; update anchor
            toggle(path: path)
            lastAnchorIndex = idx
        }
    }

    private func toggle(path: String) {
        if selection.contains(path) {
            selection.remove(path)
        } else {
            selection.insert(path)
        }
        applySelection()
    }

    private func selectAll() {
        selection = Set(subfolders.map { $0.path })
        lastAnchorIndex = subfolders.indices.last
        applySelection()
    }

    private func deselectAll() {
        selection.removeAll()
        lastAnchorIndex = nil
        applySelection()
    }

    private func indexOfPath(_ path: String) -> Int? {
        subfolders.firstIndex(where: { $0.path == path })
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose root folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let picked = panel.urls.first {
            model.project.watchPath = picked
            UserDefaults.standard.set(picked.path, forKey: defaultsKeyLastRoot)

            // Reset selection when root changes (this is expected behavior)
            selection.removeAll()
            model.project.selectedFolders = []
            model.project.images = [] // Clear images when changing root
            lastAnchorIndex = nil
            lastSelection = []
            refreshSubfolders()
        }
    }

    private func refreshSubfolders() {
        folderCounts.removeAll()
        subfolders.removeAll()
        guard let root = model.project.watchPath else { return }

        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: root,
                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles]) {
            subfolders = items.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            // Recompute counts async (keeps UI snappy)
            computeCounts(for: subfolders)
        }

        // Keep selection in sync with available subfolders
        selection = selection.intersection(Set(subfolders.map { $0.path }))
        if let anchor = lastAnchorIndex, !(0..<subfolders.count).contains(anchor) {
            lastAnchorIndex = nil
        }
        applySelection()
    }

    private func computeCounts(for folders: [URL]) {
        let fm = FileManager.default
        let exts = imageExts

        DispatchQueue.global(qos: .userInitiated).async {
            var dict: [String: Int] = [:]
            for folder in folders {
                let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                let count = files.reduce(0) { acc, url in
                    acc + (exts.contains(url.pathExtension.lowercased()) ? 1 : 0)
                }
                dict[folder.path] = count
            }
            DispatchQueue.main.async {
                // Only apply if the subfolders list hasn't changed meanwhile
                if Set(folders.map { $0.path }) == Set(self.subfolders.map { $0.path }) {
                    self.folderCounts = dict
                }
            }
        }
    }

    private func applySelection() {
        model.project.selectedFolders = subfolders.filter { selection.contains($0.path) }
        
        // CRITICAL: Only reload images if selection actually changed
        if selection != lastSelection {
            model.loadImagesFromSelectedFolders()
            lastSelection = selection
        }
    }
}

// MARK: - Tile (clickable + blue hover highlight)
private struct FolderTile: View {
    let url: URL
    let count: Int?
    let isSelected: Bool
    let onClick: (NSEvent.ModifierFlags) -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: {
            // Detect current modifier keys on macOS
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            onClick(modifiers)
        }) {
            HStack(spacing: 10) {
                // Checkbox-like icon (visual only; whole tile toggles)
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)

                // Folder name
                Text(url.lastPathComponent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Count chip or spinner
                Group {
                    if let c = count {
                        Text("\(c)")
                            .font(.caption)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain) // keep it looking like a tile, not a blue NSButton
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isSelected ? "Deselect" : "Select") {
                onClick([])
            }
        }
    }

    private var backgroundColor: Color {
        if hovering { return Color.accentColor.opacity(0.12) }
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.gray.opacity(0.08)
    }

    private var borderColor: Color {
        hovering ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.1)
    }
}
