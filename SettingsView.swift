import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = OpenAIService.shared.currentAPIKey() ?? ""
    @State private var savedBanner: Bool = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.headline)

                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 12) {
                    Button("Save") {
                        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errorText = "API key cannot be empty."
                            savedBanner = false
                        } else {
                            OpenAIService.shared.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            errorText = nil
                            savedBanner = true
                            // Auto-hide banner
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedBanner = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear", role: .destructive) {
                        OpenAIService.shared.clearAPIKey()
                        apiKey = ""
                        savedBanner = false
                        errorText = nil
                    }

                    Spacer()

                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                }

                if savedBanner {
                    Label("Saved", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                if let err = errorText {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 220)
    }
}
