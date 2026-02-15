import SwiftUI

struct PreferencesView: View {
    @State private var apiKey: String = ""
    @State private var selectedLanguage: String = "auto"
    @State private var shortcutText: String = "Cmd+Shift+D"
    @State private var showAPIKey: Bool = false
    @State private var apiKeySaved: Bool = false
    @State private var enableCodeSwitching: Bool = false
    @State private var showDockIcon: Bool = true
    @State private var sttModel: String = ""
    @State private var promptModel: String = ""

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
        .frame(width: 480, height: 380)
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
                .disabled(enableCodeSwitching) // Disable when code-switching is on

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
            Section {
                HStack {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)

                    if apiKeySaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    Spacer()

                    if KeychainService.shared.hasAPIKey {
                        Button("Clear", role: .destructive) {
                            clearAPIKey()
                        }
                    }
                }
            } header: {
                Text("OpenRouter API Key")
            } footer: {
                Text("Your API key is stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("STT model (e.g., openai/whisper-1)", text: $sttModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: sttModel) { newValue in
                        saveSTTModel(newValue)
                    }

                TextField("Prompt enhancement model (e.g., openai/gpt-4o-mini)", text: $promptModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: promptModel) { newValue in
                        savePromptModel(newValue)
                    }
            } header: {
                Text("Models")
            } footer: {
                Text("STT model must support audio inputs on OpenRouter. The prompt model is used for prompt enhancement and translations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Get an API key from OpenRouter",
                     destination: URL(string: "https://openrouter.ai/keys")!)

                Link("Browse OpenRouter models",
                     destination: URL(string: "https://openrouter.ai/models")!)
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadSettings() {
        // Load API key (show placeholder if exists)
        if KeychainService.shared.hasAPIKey {
            apiKey = "********"  // Don't show actual key
        }

        // Load language preference
        if let savedLanguage = UserDefaults.standard.string(forKey: "transcriptionLanguage") {
            selectedLanguage = savedLanguage
        }

        // Load code-switching preference
        enableCodeSwitching = UserDefaults.standard.bool(forKey: "enableCodeSwitching")

        // Load model preferences
        sttModel = UserDefaults.standard.string(forKey: "sttModel") ?? ""
        promptModel = UserDefaults.standard.string(forKey: "promptEnhancementModel") ?? ""

        if let savedDockPreference = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedDockPreference
        } else {
            showDockIcon = true
            UserDefaults.standard.set(true, forKey: "showDockIcon")
        }
    }

    private func saveAPIKey() {
        // Don't save if it's the placeholder
        guard apiKey != "********" && !apiKey.isEmpty else { return }

        if KeychainService.shared.saveAPIKey(apiKey) {
            withAnimation {
                apiKeySaved = true
            }
            // Reset after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    apiKeySaved = false
                }
            }
            // Replace with placeholder
            apiKey = "********"
        }
    }

    private func clearAPIKey() {
        KeychainService.shared.deleteAPIKey()
        apiKey = ""
    }

    private func saveLanguage(_ language: String) {
        let languageValue = language == "auto" ? nil : language
        DictationManager.shared.transcriptionLanguage = languageValue
    }

    private func saveCodeSwitching(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "enableCodeSwitching")
    }

    private func saveSTTModel(_ model: String) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "sttModel")
    }

    private func savePromptModel(_ model: String) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "promptEnhancementModel")
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
