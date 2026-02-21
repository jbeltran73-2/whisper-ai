import SwiftUI

struct PreferencesView: View {
    @State private var selectedLanguage: String = "auto"
    @State private var shortcutText: String = "Cmd+Shift+D"
    @State private var enableCodeSwitching: Bool = false
    @State private var showDockIcon: Bool = true

    // Provider selections
    @State private var sttProvider: STTProvider = .groq
    @State private var dictationLLMProvider: LLMProvider = .cerebras
    @State private var promptLLMProvider: LLMProvider = .openrouter

    // Models
    @State private var sttModel: String = ""
    @State private var dictationLLMModel: String = ""
    @State private var promptModel: String = ""

    // API Keys
    @State private var groqKey: String = ""
    @State private var cerebrasKey: String = ""
    @State private var openrouterKey: String = ""
    @State private var showGroqKey: Bool = false
    @State private var showCerebrasKey: Bool = false
    @State private var showOpenRouterKey: Bool = false
    @State private var savedKey: String? = nil // which key was just saved

    private let languages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish")
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
                }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            loadSettings()
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("Transcription Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .onChange(of: selectedLanguage) { newValue in
                    saveLanguage(newValue)
                }
                .disabled(enableCodeSwitching)

                Toggle("Code-Switching Mode", isOn: $enableCodeSwitching)
                    .onChange(of: enableCodeSwitching) { newValue in
                        saveCodeSwitching(newValue)
                    }
                    .help("Enable mixed-language dictation (e.g., switching between English and Spanish mid-sentence)")

                if enableCodeSwitching {
                    Text("Language selection is disabled in code-switching mode. The system will auto-detect languages as you switch between them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Keyboard Shortcut")
                    Spacer()
                    Text(shortcutText)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                .help("Shortcut to toggle dictation (configurable in future update)")

                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { newValue in
                        saveShowDockIcon(newValue)
                    }
                    .help("Keep Hola-AI visible in the Dock while running.")
            } header: {
                Text("Dictation")
            }

            Section {
                HStack {
                    Text("Microphone")
                    Spacer()
                    if DictationManager.shared.hasMicrophonePermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Request Access") {
                            Task {
                                await DictationManager.shared.requestMicrophonePermission()
                            }
                        }
                    }
                }

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if DictationManager.shared.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Request Access") {
                            DictationManager.shared.requestAccessibilityPermission()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var apiTab: some View {
        Form {
            // STT Provider
            Section {
                Picker("Provider", selection: $sttProvider) {
                    ForEach(STTProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .onChange(of: sttProvider) { newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: "sttProvider")
                    if sttModel.isEmpty || STTProvider.allCases.contains(where: { $0.defaultModel == sttModel && $0 != newValue }) {
                        sttModel = newValue.defaultModel
                        UserDefaults.standard.set(sttModel, forKey: "sttModel")
                    }
                }

                TextField("Model", text: $sttModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: sttModel) { newValue in
                        UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "sttModel")
                    }
            } header: {
                Text("Transcription (STT)")
            } footer: {
                Text("Groq uses native Whisper API (fastest). OpenRouter uses audio via chat completions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Dictation LLM
            Section {
                Picker("Provider", selection: $dictationLLMProvider) {
                    ForEach(LLMProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .onChange(of: dictationLLMProvider) { newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: "dictationLLMProvider")
                    if dictationLLMModel.isEmpty || LLMProvider.allCases.contains(where: { $0.defaultModel == dictationLLMModel && $0 != newValue }) {
                        dictationLLMModel = newValue.defaultModel
                        UserDefaults.standard.set(dictationLLMModel, forKey: "dictationLLMModel")
                    }
                }

                TextField("Model", text: $dictationLLMModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: dictationLLMModel) { newValue in
                        UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "dictationLLMModel")
                    }
            } header: {
                Text("Text Cleanup (Dictation)")
            } footer: {
                Text("Fast model for punctuation, capitalization, and self-correction cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Prompt LLM
            Section {
                Picker("Provider", selection: $promptLLMProvider) {
                    ForEach(LLMProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .onChange(of: promptLLMProvider) { newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: "promptLLMProvider")
                    if promptModel.isEmpty || LLMProvider.allCases.contains(where: { $0.defaultModel == promptModel && $0 != newValue }) {
                        promptModel = newValue.defaultModel
                        UserDefaults.standard.set(promptModel, forKey: "promptEnhancementModel")
                    }
                }

                TextField("Model", text: $promptModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: promptModel) { newValue in
                        UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "promptEnhancementModel")
                    }
            } header: {
                Text("Prompt Enhancement")
            } footer: {
                Text("More capable model for translating and rewriting prompts to English.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // API Keys
            Section {
                apiKeyRow(label: "Groq", key: $groqKey, show: $showGroqKey, account: "groq-api-key")
                apiKeyRow(label: "Cerebras", key: $cerebrasKey, show: $showCerebrasKey, account: "cerebras-api-key")
                apiKeyRow(label: "OpenRouter", key: $openrouterKey, show: $showOpenRouterKey, account: "openrouter-api-key")
            } header: {
                Text("API Keys")
            } footer: {
                Text("Keys are stored securely in the macOS Keychain. Only keys for providers you use are required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Get Groq API key", destination: URL(string: "https://console.groq.com/keys")!)
                Link("Get Cerebras API key", destination: URL(string: "https://cloud.cerebras.ai/")!)
                Link("Get OpenRouter API key", destination: URL(string: "https://openrouter.ai/keys")!)
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func apiKeyRow(label: String, key: Binding<String>, show: Binding<Bool>, account: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .frame(width: 80, alignment: .leading)

                if show.wrappedValue {
                    TextField("API key...", text: key)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("API key...", text: key)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)

                Button("Save") {
                    saveProviderKey(key.wrappedValue, account: account)
                }
                .disabled(key.wrappedValue.isEmpty || key.wrappedValue == "********")

                if savedKey == account {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                if KeychainService.shared.hasKey(for: account) {
                    Button(role: .destructive) {
                        KeychainService.shared.deleteKey(for: account)
                        key.wrappedValue = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Load / Save

    private func loadSettings() {
        // Language
        if let saved = UserDefaults.standard.string(forKey: "transcriptionLanguage") {
            selectedLanguage = saved
        }
        enableCodeSwitching = UserDefaults.standard.bool(forKey: "enableCodeSwitching")

        // Dock
        if let savedDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedDock
        } else {
            showDockIcon = true
            UserDefaults.standard.set(true, forKey: "showDockIcon")
        }

        // Providers
        if let raw = UserDefaults.standard.string(forKey: "sttProvider"), let p = STTProvider(rawValue: raw) {
            sttProvider = p
        }
        if let raw = UserDefaults.standard.string(forKey: "dictationLLMProvider"), let p = LLMProvider(rawValue: raw) {
            dictationLLMProvider = p
        }
        if let raw = UserDefaults.standard.string(forKey: "promptLLMProvider"), let p = LLMProvider(rawValue: raw) {
            promptLLMProvider = p
        }

        // Models (use defaults if empty)
        sttModel = UserDefaults.standard.string(forKey: "sttModel") ?? sttProvider.defaultModel
        dictationLLMModel = UserDefaults.standard.string(forKey: "dictationLLMModel") ?? dictationLLMProvider.defaultModel
        promptModel = UserDefaults.standard.string(forKey: "promptEnhancementModel") ?? promptLLMProvider.defaultModel

        // API Keys - show placeholder if stored
        if KeychainService.shared.hasKey(for: "groq-api-key") { groqKey = "********" }
        if KeychainService.shared.hasKey(for: "cerebras-api-key") { cerebrasKey = "********" }
        if KeychainService.shared.hasKey(for: "openrouter-api-key") { openrouterKey = "********" }
    }

    private func saveProviderKey(_ key: String, account: String) {
        guard key != "********" && !key.isEmpty else { return }

        if KeychainService.shared.saveKey(key, for: account) {
            withAnimation {
                savedKey = account
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    if savedKey == account { savedKey = nil }
                }
            }
            // Replace with placeholder
            switch account {
            case "groq-api-key": groqKey = "********"
            case "cerebras-api-key": cerebrasKey = "********"
            case "openrouter-api-key": openrouterKey = "********"
            default: break
            }
        }
    }

    private func saveLanguage(_ language: String) {
        let languageValue = language == "auto" ? nil : language
        DictationManager.shared.transcriptionLanguage = languageValue
    }

    private func saveCodeSwitching(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "enableCodeSwitching")
    }

    private func saveShowDockIcon(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "showDockIcon")
        NotificationCenter.default.post(
            name: .showDockIconChanged,
            object: nil,
            userInfo: ["showDockIcon": enabled]
        )
    }
}

#Preview {
    PreferencesView()
}
