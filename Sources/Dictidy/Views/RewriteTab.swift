import SwiftUI
import DictidyKit

struct RewriteTab: View {
    var body: some View {
        ScrollView { RewriteConfigurationView().padding() }
    }
}

/// Shared by Settings and onboarding: either or both keys, one model selection.
struct RewriteConfigurationView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add an Anthropic or OpenAI API key, or both. Choose the default model for rewriting below.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(RewriteProvider.allCases, id: \.self) { provider in
                ProviderKeyRow(provider: provider)
                Divider()
            }

            Picker("Default model", selection: $state.selectedModelID) {
                if !state.availableModels.contains(where: { $0.id == state.selectedModelID }) {
                    Text("Choose a model").tag(state.selectedModelID)
                }
                ForEach(RewriteProvider.allCases, id: \.self) { provider in
                    let models = state.availableModels.filter { $0.provider == provider }
                    if !models.isEmpty {
                        Section(provider.displayName) {
                            ForEach(models) { model in Text(model.label).tag(model.id) }
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(state.availableModels.isEmpty)

            Text("Instructions use this model unless you choose an override in Settings → Instructions.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    Task { await state.refreshModels() }
                } label: { Label("Refresh Models", systemImage: "arrow.clockwise") }
                .disabled(state.configuredProviders.isEmpty || !state.refreshingProviders.isEmpty)
                if !state.refreshingProviders.isEmpty { ProgressView().controlSize(.small) }
            }

            if state.availableModels.isEmpty {
                Text(state.configuredProviders.isEmpty ? "Save an API key to load models." : "No models loaded yet. Refresh Models to try again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Selected text is sent to the provider of the model you choose. API usage is billed by that provider. Voice transcription runs on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProviderKeyRow: View {
    @EnvironmentObject var state: AppState
    let provider: RewriteProvider
    // Do not decrypt existing keys just to display settings. Read each key only when its API is used.
    @State private var key = ""
    @State private var reveal = false
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.displayName).font(.headline)
                if state.refreshingProviders.contains(provider) {
                    StatusBadge(.working, label: "Loading models…")
                } else if state.hasAPIKey(for: provider) {
                    StatusBadge(.ready, label: "Key saved")
                }
            }
            Text("Your key is stored in macOS Keychain and used only with \(provider.apiHost).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Group {
                    if reveal { TextField(placeholder, text: $key) }
                    else { SecureField(placeholder, text: $key) }
                }.textFieldStyle(.roundedBorder)
                Button(reveal ? "Hide" : "Show") { reveal.toggle() }.disabled(key.isEmpty)
            }
            HStack {
                Button("Save API Key") {
                    if state.saveAPIKey(trimmedKey, provider: provider) { key = ""; reveal = false }
                }.disabled(trimmedKey.isEmpty)
                Button("Remove") {
                    state.removeAPIKey(provider: provider)
                    if !state.hasAPIKey(for: provider) { key = ""; reveal = false }
                }.disabled(!state.hasAPIKey(for: provider))
                Spacer()
                Link("Get API Key", destination: provider.keyURL)
            }
            if let error = state.modelErrors[provider] {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if let date = state.modelsLastFetched[provider], state.hasAPIKey(for: provider) {
                Text("\(state.models.filter { $0.provider == provider }.count) models · Updated \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var placeholder: String {
        if state.hasAPIKey(for: provider) { return "Key saved. Paste a new key to replace it." }
        return provider == .anthropic ? "sk-ant-…" : "sk-…"
    }
}
