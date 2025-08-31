import SwiftUI
import AppKit

// MARK: - CaptionsView

struct CaptionsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var store   = ChatStore.shared
    @StateObject private var presets = PromptStore.shared

    // UI state - Changed to @AppStorage for persistence
    @AppStorage("captions_input_text") private var input: String = ""
    @State private var isSending = false
    @FocusState private var inputFocused: Bool

    // Attach images
    @State private var attachSelectedImages = false

    // Preset sheet state
    @State private var presetSheetShown = false
    @State private var presetTitle: String = ""
    @State private var presetText: String = ""
    @State private var presetMode: PresetMode = .add
    @State private var presetEditing: PromptPreset? = nil

    // Settings sheet
    @State private var showSettingsSheet = false
    
    // Refresh chat confirmation
    @State private var showingRefreshConfirmation = false
    
    // Auto-trim tracking
    @State private var lastAutoTrimCount = 0

    enum PresetMode { case add, rename, edit }

    // Fallback messages buffer so bubbles show even if ChatStore/current is nil
    @State private var localMessages: [ChatMessage] = []

    // Enabled image URLs used by the attach toggle
    private var enabledImageURLs: [URL] {
        model.project.images.filter { !$0.disabled }.map { $0.url }
    }

    // Messages source for the view: prefer store, fallback to local
    private var messagesView: [ChatMessage] {
        if let msgs = store.current?.messages { return msgs }
        return localMessages
    }

    // Build stamp: Info.plist "BUILD_TIMESTAMP" if present; else current time
    private var buildStamp: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BUILD_TIMESTAMP") as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            chatArea
        }
        .sheet(isPresented: $showSettingsSheet) { SettingsView() }
        .sheet(isPresented: $presetSheetShown, onDismiss: {
            presetTitle = ""; presetText = ""; presetEditing = nil
        }) { presetSheet }
        .confirmationDialog("Clear Chat History", isPresented: $showingRefreshConfirmation) {
            Button("Clear \(messagesView.count) Messages", role: .destructive) {
                performRefresh()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all conversation history. This action cannot be undone.")
        }
        .onAppear {
            dlog("CaptionsView appeared — Build: \(buildStamp)")
            NSLog("=== TEST LOG: CaptionsView appeared ===")
            dlog("CaptionsView appeared — Build: \(buildStamp)")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 12) {
                Text("Captions").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8)

            Divider()

            // Presets header
            HStack {
                Text("Presets").font(.subheadline)
                Spacer()
                Button { startAddPreset() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.top, 8)

            // Presets list
            List {
                ForEach(presets.presets) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(.subheadline).bold()
                        Text(p.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { insertPresetText(p.text, sendNow: false) }
                    .contextMenu {
                        Button("Insert") { insertPresetText(p.text, sendNow: false) }
                        Button("Insert & Send") { insertPresetText(p.text, sendNow: true) }
                        Button("Rename") { promptRenamePreset(p) }
                        Button("Edit Text") { promptEditPresetText(p) }
                        Divider()
                        Button("Delete", role: .destructive) { presets.delete(p) }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            // Current Caption
            HStack {
                Text("Current Caption").font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 4)

            VStack {
                TextEditor(text: $model.project.caption)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .foregroundColor(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    // Restored sidebar width (previously reduced for smaller window)
    // To allow smaller resizing again, set width: 120
    .frame(width: 320)
        .padding(8)
        .background(Color.gray.opacity(0.06))
    }

    // MARK: - Chat area

    private var chatArea: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatGPT").font(.headline)
                    HStack(spacing: 4) {
                        Text("Build: \(buildStamp)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if messagesView.count > 0 {
                            Text("• \(messagesView.count) msgs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if lastAutoTrimCount > 0 {
                            Text("(auto-trimmed \(lastAutoTrimCount))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
                
                // Refresh button
                Button {
                    refreshChat()
                } label: {
                    Label("Clear Chat", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Clear conversation history (\(messagesView.count) messages)")
                
                Button("Settings") { showSettingsSheet = true }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12).padding(.top, 8)

            // Auto-trim info banner
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Old messages are automatically cleared after 40 messages to optimize performance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)

            // Scrollback
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messagesView, id: \.id) { msg in
                            chatBubble(for: msg).id(msg.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: messagesView.count) { _, _ in
                    if let lastID = messagesView.last?.id {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastID = messagesView.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            // Input + Send (Enter sends, Shift+Enter newline)
            HStack(alignment: .bottom, spacing: 8) {
                EnterSendingTextEditor(
                    text: $input,
                    onCommit: { Task { await performSend() } }
                )
                .frame(minHeight: 30, maxHeight: 100)
                .background(Color(nsColor: .textBackgroundColor)) // Use system color that adapts to appearance
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                .focused($inputFocused)
                .onAppear {
                    // Focus input field when view appears and there's no input text
                    if input.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            inputFocused = true
                        }
                    }
                }

                Button(isSending ? "Sending…" : "Send") {
                    Task { await performSend() }
                }
                .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)

            // Attach toggle
            if !enabledImageURLs.isEmpty {
                HStack(spacing: 8) {
                    Toggle("Attach Selects", isOn: $attachSelectedImages)
                    Text("\(enabledImageURLs.count) image(s) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Chat bubble

    @ViewBuilder
    private func chatBubble(for msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == "assistant" { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(msg.role == "user" ? "You" : "Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.project.caption = cleanTextForCaption(msg.content)
                    } label: {
                        Label("Use as caption", systemImage: "text.append")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button {
                        startAddPreset(with: msg.content)
                    } label: {
                        Label("Add to presets", systemImage: "star")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                Text(msg.content).textSelection(.enabled)
            }
            .padding(10)
            .background(msg.role == "user" ? Color.gray.opacity(0.1) : Color.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if msg.role == "user" { Spacer(minLength: 0) }
        }
        .padding(.horizontal)
    }

    // MARK: - Preset sheet UI

    private var presetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presetMode == .add ? "Add Prompt Preset"
                 : (presetMode == .rename ? "Rename Prompt" : "Edit Prompt Text"))
            .font(.title3.bold())

            if presetMode != .edit {
                TextField("Preset name", text: $presetTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                Text("Preset: \(presetTitle)").font(.subheadline)
            }

            TextEditor(text: $presetText)
                .frame(width: 420, height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                .opacity(presetMode == .rename ? 0.4 : 1.0)
                .disabled(presetMode == .rename)

            HStack {
                Spacer()
                Button("Cancel") { presetSheetShown = false }
                Button(presetMode == .add ? "Add" : "Save") { confirmPresetSheet() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    .frame(minWidth: 0)
    }

    // MARK: - Text Cleaning for Caption

    private func cleanTextForCaption(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove starting quotation marks - using Unicode escape sequences
        let startingQuotes = ["\"", "\u{201C}", "'", "\u{2018}"]
        for quote in startingQuotes {
            if cleaned.hasPrefix(quote) {
                cleaned = String(cleaned.dropFirst(quote.count))
                break
            }
        }
        
        // Remove ending quotation marks - using Unicode escape sequences
        let endingQuotes = ["\"", "\u{201D}", "'", "\u{2019}"]
        for quote in endingQuotes {
            if cleaned.hasSuffix(quote) {
                cleaned = String(cleaned.dropLast(quote.count))
                break
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Auto-trim History Function

    private func autoTrimHistoryIfNeeded() {
        let maxMessages = 40 // Keep last 40 messages
        let currentCount = messagesView.count
        
        if currentCount > maxMessages {
            let messagesToRemove = currentCount - maxMessages
            
            dlog("Auto-trimming chat history: \(currentCount) → \(maxMessages) messages")
            
            // Clear from store
            if var current = store.current {
                current.messages.removeFirst(messagesToRemove)
                store.replace(current)
            }
            
            // Clear from local fallback
            localMessages.removeFirst(messagesToRemove)
            
            lastAutoTrimCount = messagesToRemove
            dlog("Auto-trimmed \(messagesToRemove) old messages")
            
            // Clear the auto-trim indicator after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                lastAutoTrimCount = 0
            }
        }
    }

    // MARK: - Chat Refresh Functions

    private func refreshChat() {
        if messagesView.count > 5 {
            showingRefreshConfirmation = true
        } else {
            performRefresh()
        }
    }

    private func performRefresh() {
        dlog("Refreshing chat - clearing \(messagesView.count) messages")
        
        // Clear store messages if available
        if var current = store.current {
            current.messages.removeAll()
            store.replace(current)
        }
        
        // Clear local fallback messages
        localMessages.removeAll()
        
        // Reset auto-trim indicator
        lastAutoTrimCount = 0
        
        dlog("Chat refreshed. Message count now: \(messagesView.count)")
    }

    // MARK: - Preset helpers

    private func startAddPreset() {
        presetMode = .add
        presetTitle = ""
        presetText = ""
        presetEditing = nil
        presetSheetShown = true
    }

    private func startAddPreset(with text: String) {
        presetMode = .add
        presetText = text
        presetTitle = makeTitleSuggestion(from: text)
        presetEditing = nil
        presetSheetShown = true
    }

    private func promptRenamePreset(_ p: PromptPreset) {
        presetMode = .rename
        presetTitle = p.title
        presetText = p.text
        presetEditing = p
        presetSheetShown = true
    }

    private func promptEditPresetText(_ p: PromptPreset) {
        presetMode = .edit
        presetTitle = p.title
        presetText = p.text
        presetEditing = p
        presetSheetShown = true
    }

    private func confirmPresetSheet() {
        let title = presetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body  = presetText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch presetMode {
        case .add:
            guard !title.isEmpty, !body.isEmpty else { return }
            presets.add(title: title, text: body)
        case .rename:
            if let p = presetEditing, !title.isEmpty { presets.rename(p, to: title) }
        case .edit:
            if let p = presetEditing { presets.updateText(p, to: body) }
        }
        presetSheetShown = false
        presetEditing = nil
    }

    private func insertPresetText(_ text: String, sendNow: Bool) {
        if sendNow {
            input = input.isEmpty ? text : (input + "\n" + text)
            Task { await performSend() }
        } else {
            input.append(input.isEmpty ? text : "\n" + text)
            inputFocused = true
        }
    }

    private func makeTitleSuggestion(from text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstLine.count <= 30 { return firstLine }
        return "\(firstLine.prefix(27))…"
    }

    // MARK: - Logging helper

    private func dlog(_ s: String) {
        print("[CaptionsView] \(s)")
    }

    // MARK: - Send (diagnostic + store-fallback to guarantee bubbles)

    private func performSend() async {
        dlog("performSend() tapped")

        let rawInput = input
        let prompt = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        dlog("Input captured. raw len=\(rawInput.count), trimmed len=\(prompt.count)")

        // AUTO-TRIM HISTORY BEFORE SENDING
        autoTrimHistoryIfNeeded()

        await MainActor.run {
            input = ""
            isSending = true

            let userShown = !prompt.isEmpty ? prompt : "(empty prompt)"
            appendMessage(role: "user", content: userShown)
            appendMessage(role: "assistant", content: "(thinking…)")

            dlog("User + placeholder assistant appended. viewCount=\(messagesView.count)")
        }

        func updateAssistant(_ text: String) {
            Task { @MainActor in
                replaceLastAssistant(with: text)
            }
        }

        if prompt.isEmpty {
            dlog("Prompt was empty → showing message and exiting.")
            updateAssistant("⚠️ No prompt provided. Type something and press Send.")
            await MainActor.run { isSending = false }
            return
        }

        // Build history from the exact set the UI sees (store or local fallback)
        let textHistory: [(role: String, content: String)] = messagesView.map { ($0.role, $0.content) }
        dlog("Built history with \(textHistory.count) messages.")

        // Attachable images
        let allowedExts = Set(["jpg","jpeg","png","webp"])
        let attachableImages = enabledImageURLs.filter { allowedExts.contains($0.pathExtension.lowercased()) }
        dlog("Attach toggle=\(attachSelectedImages), attachableImages=\(attachableImages.count)")

        // Stream helpers with "silent stream" timeout
        struct SilentStreamError: Error {}
        let firstChunkTimeout: UInt64 = 3_000_000_000 // 3 seconds

        func streamText() async throws {
            dlog("streamText(): starting")
            var assembled = ""
            var gotFirstChunk = false

            let streamTask = Task {
                try await OpenAIService.shared.chatStream(history: textHistory) { chunk in
                    if !gotFirstChunk { gotFirstChunk = true; dlog("streamText(): first chunk received") }
                    assembled += chunk
                    updateAssistant(assembled)
                }
            }

            try? await Task.sleep(nanoseconds: firstChunkTimeout)
            if !gotFirstChunk {
                dlog("streamText(): no chunks → cancelling")
                streamTask.cancel()
                throw SilentStreamError()
            }
            _ = try await streamTask.value
            dlog("streamText(): completed normally")
        }

        func streamWithImages() async throws {
            dlog("streamWithImages(): starting")
            var assembled = ""
            var gotFirstChunk = false

            let streamTask = Task {
                try await OpenAIService.shared.chatStreamWithImages(
                    preHistory: Array(textHistory.dropLast()),
                    userPrompt: prompt,
                    imageURLs: attachableImages
                ) { chunk in
                    if !gotFirstChunk { gotFirstChunk = true; dlog("streamWithImages(): first chunk received") }
                    assembled += chunk
                    updateAssistant(assembled)
                }
            }

            try? await Task.sleep(nanoseconds: firstChunkTimeout)
            if !gotFirstChunk {
                dlog("streamWithImages(): no chunks → cancelling")
                streamTask.cancel()
                throw SilentStreamError()
            }
            _ = try await streamTask.value
            dlog("streamWithImages(): completed normally")
        }

        // Try streaming first, then fall back; log everything
        do {
            if attachSelectedImages, !attachableImages.isEmpty {
                await MainActor.run { attachSelectedImages = false }
                dlog("Sending WITH images (stream first).")
                do {
                    try await streamWithImages()
                    dlog("Result: STREAM (images) success")
                } catch {
                    dlog("STREAM (images) failed: \(error.localizedDescription) → fallback to one-shot")
                    let full = try await OpenAIService.shared.chatOnceWithImages(
                        preHistory: Array(textHistory.dropLast()),
                        userPrompt: prompt,
                        imageURLs: attachableImages
                    )
                    updateAssistant(full)
                    dlog("Result: FALLBACK (images) success, \(full.count) chars")
                }
            } else {
                dlog("Sending TEXT-ONLY (stream first).")
                do {
                    try await streamText()
                    dlog("Result: STREAM (text) success")
                } catch {
                    dlog("STREAM (text) failed: \(error.localizedDescription) → fallback to one-shot")
                    let full = try await OpenAIService.shared.chatOnce(history: textHistory)
                    updateAssistant(full)
                    dlog("Result: FALLBACK (text) success, \(full.count) chars")
                }
            }
        } catch {
            let msg = "(Caption error: \(error.localizedDescription))"
            updateAssistant(msg)
            dlog("UNHANDLED ERROR: \(error.localizedDescription)")
        }

        await MainActor.run { isSending = false }
        dlog("performSend() finished (viewCount=\(messagesView.count))")
    }

    // MARK: - Message helpers (store + local fallback)

    /// Append a message to the store if possible, and always to local fallback
    @MainActor private func appendMessage(role: String, content: String) {
        // Store path (only if it has a current thread & append works)
        store.append(role: role, content: content)
        // Local fallback mirrors the store so bubbles always show
        localMessages.append(ChatMessage(role: role, content: content))
    }

    /// Replace the last assistant message (store if possible, always local)
    @MainActor private func replaceLastAssistant(with text: String) {
        if var cur = store.current,
           !cur.messages.isEmpty,
           cur.messages.last?.role == "assistant" {
            cur.messages[cur.messages.count - 1].content = text
            store.replace(cur)
        }
        if let last = localMessages.indices.last,
           localMessages[last].role == "assistant" {
            localMessages[last].content = text
        }
    }
}

// MARK: - EnterSendingTextEditor (macOS) — Enter to send, Shift+Enter newline

private struct EnterSendingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let tv = context.coordinator.textView
        tv.string = text
        
        // Use system background color that adapts to appearance mode
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        
        // Configure text color to adapt to appearance mode
        tv.textColor = .textColor
        
        // Configure appearance observation
        context.coordinator.setupAppearanceObserver()

        // Allow vertical growth; outer SwiftUI .frame controls visible height
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.containerSize = NSSize(width: 0,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true

        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tv = nsView.documentView as? NSTextView, tv.string != text {
            tv.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EnterSendingTextEditor
        let textView: NSTextView
        private var appearanceObserver: NSKeyValueObservation?
        
        deinit {
            appearanceObserver?.invalidate()
        }

        init(_ parent: EnterSendingTextEditor) {
            self.parent = parent
            self.textView = NSTextView()
            super.init()

            textView.delegate = self
            textView.isRichText = false
            textView.usesFontPanel = false
            textView.usesFindPanel = true
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
            textView.allowsUndo = true
            textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textView.textContainerInset = NSSize(width: 6, height: 6)
        }
        
        func setupAppearanceObserver() {
            // Listen for appearance changes
            appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async {
                    // Update colors when appearance changes
                    self?.textView.backgroundColor = .textBackgroundColor
                    self?.textView.textColor = .textColor
                }
            }
            
            // Also observe notification for appearance changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appearanceChanged),
                name: Notification.Name("AppearanceChanged"),
                object: nil
            )
        }
        
        @objc func appearanceChanged(_ notification: Notification) {
            DispatchQueue.main.async {
                // Update colors when appearance changes
                self.textView.backgroundColor = .textBackgroundColor
                self.textView.textColor = .textColor
            }
        }

        func textDidChange(_ notification: Notification) {
            parent.text = textView.string
        }

        // Enter sends, Shift+Enter newline
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    // Ensure binding has latest text BEFORE onCommit()
                    parent.text = self.textView.string
                    parent.onCommit()
                }
                return true
            }
            return false
        }
    }
}
