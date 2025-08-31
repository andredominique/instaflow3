import SwiftUI

struct OptionsCaptionsView: View {
    // Keep the model in case you use it elsewhere in this view later
    @EnvironmentObject private var model: AppModel

    @State private var prompt: String = ""
    @State private var caption: String = ""
    @State private var isLoading = false
    @State private var errorText: String?

    // Local settings sheet toggle (no dependency on AppModel.showSettings)
    @State private var showSettingsSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captions")
                    .font(.title2).bold()
                Spacer()
                Button("Settings") { showSettingsSheet = true }
            }

            Text("Write a prompt for your caption:")
                .font(.headline)

            TextEditor(text: $prompt)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))

            HStack {
                Button {
                    Task { await generate() }
                } label: {
                    if isLoading { ProgressView() } else { Text("Generate Caption") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let err = errorText {
                    Spacer()
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Result")
                .font(.headline)

            ScrollView {
                Text(caption.isEmpty ? "No caption yet." : caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
    }

    // MARK: - Actions

    private func generate() async {
        errorText = nil

        guard OpenAIService.shared.apiKeyAvailable else {
            errorText = "Add your API key in Settings."
            return
        }

        isLoading = true
        do {
            let text = try await OpenAIService.shared.generateCaption(prompt: prompt)
            caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
