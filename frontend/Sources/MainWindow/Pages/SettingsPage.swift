import SwiftUI

// MARK: - SettingsContentView namespace (used by DesktopHomeView)
enum SettingsContentView {
    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case hermes = "Hermes Agent"
        case byok = "API Keys (BYOK)"
    }
}

struct SettingsPage: View {
    @ObservedObject var appState: AppState
    @Binding var selectedSection: SettingsContentView.SettingsSection
    @Binding var highlightedSettingId: String?
    var chatProvider: ChatProvider? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(SettingsContentView.SettingsSection.allCases, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        Text(section.rawValue)
                            .font(.system(size: 14))
                            .foregroundColor(selectedSection == section ? .white : .gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedSection == section ? Color.accentColor.opacity(0.3) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
                Spacer()
            }
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedSection {
                    case .general:
                        GeneralSettingsSection()
                    case .shortcuts:
                        ShortcutsSettingsSection()
                    case .hermes:
                        HermesSettingsSection()
                    case .byok:
                        BYOKSettingsSection()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - General Settings
private struct GeneralSettingsSection: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            SettingsRow(title: "Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            SettingsRow(title: "Backend", value: "http://localhost:10201")

            Divider()

            Text("Software Updates")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Text("Actualiza con `git pull` y ejecuta `./run.sh` de nuevo.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Shortcuts Settings
private struct ShortcutsSettingsSection: View {
    @ObservedObject private var settings = ShortcutSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Ask Umi shortcut", isOn: $settings.askOmiEnabled)
                    .font(.system(size: 14)).foregroundColor(.white).toggleStyle(.switch)
                Text(settings.askOmiShortcut.displayLabel)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.gray)

                Divider()

                Toggle("Push-to-talk", isOn: $settings.pttEnabled)
                    .font(.system(size: 14)).foregroundColor(.white).toggleStyle(.switch)
                Text(settings.pttShortcut.displayLabel)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.gray)

                Divider()

                Toggle("Draggable floating bar", isOn: $settings.draggableBarEnabled)
                    .font(.system(size: 14)).foregroundColor(.white).toggleStyle(.switch)
                Toggle("PTT sounds", isOn: $settings.pttSoundsEnabled)
                    .font(.system(size: 14)).foregroundColor(.white).toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Hermes Agent Settings
private struct HermesSettingsSection: View {
    // Provider
    @AppStorage("hermes_provider") private var provider = HermesProvider.fireworks.rawValue
    @AppStorage("hermes_api_key") private var apiKey = ""
    @AppStorage("hermes_model") private var model = HermesProvider.fireworks.defaultModel
    @AppStorage("hermes_api_url") private var apiURL = HermesProvider.fireworks.apiURL
    // Agent params
    @AppStorage("hermes_system_prompt") private var systemPrompt = ""
    @AppStorage("hermes_reasoning_effort") private var reasoningEffort = "medium"
    @AppStorage("hermes_max_turns") private var maxTurns = 10

    @State private var status: HermesStatus = .checking
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showAdvanced = false

    private var selectedProvider: HermesProvider {
        HermesProvider(rawValue: provider) ?? .fireworks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Text("Hermes Agent")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                HermesStatusBadge(status: status)
                Button { Task { await refreshStatus() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Verificar estado del sidecar")
            }

            Text("LLM cloud directo — sin bucle de agente para el chat. El sidecar Hermes Agent corre en puerto 8642 para tareas avanzadas.")
                .font(.system(size: 13))
                .foregroundColor(.gray)

            // Provider & credentials
            SettingsGroupBox(title: "Provider") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: $provider) {
                        ForEach(HermesProvider.allCases) { p in
                            Text(p.rawValue).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220, alignment: .leading)
                    .onChange(of: provider) { _, _ in applyPreset() }

                    APIKeyField(label: "API Key", placeholder: selectedProvider.keyPlaceholder, value: $apiKey)

                    if selectedProvider == .fireworks {
                        Text("fireworks.ai \u{2192} Account \u{2192} API Keys")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    SettingsTextField(label: "Model", placeholder: selectedProvider.defaultModel, value: $model)

                    SettingsTextField(
                        label: "API URL",
                        placeholder: selectedProvider.apiURL,
                        value: $apiURL,
                        isDisabled: selectedProvider != .custom
                    )
                }
            }

            // Advanced agent params
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System prompt")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 72, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        Text("Vacío usa el prompt por defecto: \"Eres Umi, un asistente de escritorio conciso y útil.\"")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reasoning effort")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Picker("Reasoning effort", selection: $reasoningEffort) {
                            Text("None").tag("none")
                            Text("Minimal").tag("minimal")
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 400)
                        Text("Controla cuánto \"piensa\" el modelo antes de responder. None = más rápido.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max agent turns: \(maxTurns)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Slider(value: Binding(
                            get: { Double(maxTurns) },
                            set: { maxTurns = Int($0) }
                        ), in: 1...30, step: 1)
                        .frame(maxWidth: 300)
                        Text("Iteraciones máximas del bucle de herramientas (solo en modo agente).")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Parámetros avanzados del agente")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            // Save
            HStack(spacing: 12) {
                Button {
                    Task { await saveConfig() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .disabled(isSaving || apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Tras guardar, reinicia: Ctrl+C en terminal \u{2192} ./run.sh")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 12))
                    .foregroundColor(saveMessage.contains("Error") ? .red : .gray)
            }

            // Quick start
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Setup rapido")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("1. Crea cuenta en fireworks.ai")
                        Text("2. Account \u{2192} API Keys \u{2192} Create key")
                        Text("3. Pega la key arriba y pulsa Save")
                        Text("4. Reinicia: Ctrl+C \u{2192} ./run.sh")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                }
            }
        }
        .task {
            applyPresetIfNeeded()
            await refreshStatus()
        }
    }

    private func applyPresetIfNeeded() {
        if apiURL.isEmpty || model.isEmpty { applyPreset() }
    }

    private func applyPreset() {
        let preset = selectedProvider
        guard preset != .custom else { return }
        apiURL = preset.apiURL
        model = preset.defaultModel
    }

    @MainActor
    private func refreshStatus() async {
        status = .checking
        do {
            let response: HermesHealthResponse = try await APIClient.shared.get("/v1/hermes/health")
            status = response.hermes ? .healthy : .unavailable
        } catch {
            status = .unavailable
        }
    }

    @MainActor
    private func saveConfig() async {
        isSaving = true
        saveMessage = nil
        defer { isSaving = false }
        do {
            let request = HermesConfigRequest(
                apiKey: apiKey,
                apiURL: apiURL,
                model: model,
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                reasoningEffort: reasoningEffort,
                maxTurns: maxTurns
            )
            let response: HermesConfigResponse = try await APIClient.shared.post("/v1/hermes/config", body: request)
            saveMessage = response.message
            await refreshStatus()
        } catch {
            saveMessage = "Error al guardar: \(error.localizedDescription)"
        }
    }
}

private enum HermesProvider: String, CaseIterable, Identifiable {
    case fireworks = "Fireworks AI"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case custom = "Custom"

    var id: String { rawValue }

    var apiURL: String {
        switch self {
        case .fireworks:
            return "https://api.fireworks.ai/inference/v1"
        case .openAI:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .custom:
            return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .fireworks:
            return "accounts/fireworks/routers/kimi-k2p5-turbo"
        case .openAI:
            return "gpt-4o"
        case .anthropic:
            return "claude-sonnet-4-20250514"
        case .custom:
            return ""
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .fireworks:
            return "fw_..."
        case .openAI:
            return "sk-..."
        case .anthropic:
            return "sk-ant-..."
        case .custom:
            return "API key"
        }
    }
}

private enum HermesStatus {
    case checking
    case healthy
    case unavailable
}

private struct HermesHealthResponse: Decodable {
    let status: String
    let hermes: Bool
}

private struct HermesConfigRequest: Encodable {
    let apiKey: String
    let apiURL: String
    let model: String
    let systemPrompt: String?
    let reasoningEffort: String
    let maxTurns: Int

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case apiURL = "api_url"
        case model
        case systemPrompt = "system_prompt"
        case reasoningEffort = "reasoning_effort"
        case maxTurns = "max_turns"
    }
}

private struct HermesConfigResponse: Decodable {
    let status: String
    let message: String
}

private struct HermesStatusBadge: View {
    let status: HermesStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
    }

    private var color: Color {
        switch status {
        case .checking:
            return .yellow
        case .healthy:
            return .green
        case .unavailable:
            return .red
        }
    }

    private var label: String {
        switch status {
        case .checking:
            return "Checking"
        case .healthy:
            return "Online"
        case .unavailable:
            return "Offline"
        }
    }
}

// MARK: - BYOK Settings
private struct BYOKSettingsSection: View {
    @AppStorage("dev_openai_api_key") var openaiKey = ""
    @AppStorage("dev_anthropic_api_key") var anthropicKey = ""
    @AppStorage("dev_gemini_api_key") var geminiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Keys (BYOK)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text("Añade tus propias claves. Se guardan localmente en tu Mac.")
                .font(.system(size: 13))
                .foregroundColor(.gray)

            APIKeyField(label: "OpenAI API Key", placeholder: "sk-...", value: $openaiKey)
            APIKeyField(label: "Anthropic API Key", placeholder: "sk-ant-...", value: $anthropicKey)
            APIKeyField(label: "Google Gemini API Key", placeholder: "AIza...", value: $geminiKey)

            Text("Las claves se usan como LLM_API_KEY en el backend local.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Helpers
private struct SettingsGroupBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            content()
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(size: 14, design: .monospaced)).foregroundColor(.white)
        }
    }
}

private struct APIKeyField: View {
    let label: String
    let placeholder: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
            SecureField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
        }
    }
}

private struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .disabled(isDisabled)
        }
    }
}
