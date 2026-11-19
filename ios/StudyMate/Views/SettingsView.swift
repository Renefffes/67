import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StudyAI.engineKey) private var engine: AIEngine = .automatic
    @AppStorage(StudyAI.geminiModelKey) private var geminiModel = StudyAI.defaultGeminiModel
    @State private var geminiKey = Keychain.geminiAPIKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("AI engine", selection: $engine) {
                        ForEach(AIEngine.allCases) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("enginePicker")
                    LabeledContent("Currently using", value: StudyAI.resolvedEngine(StudyAI.selectedEngine).displayName)
                        .accessibilityIdentifier("activeEngineLabel")
                } header: {
                    Text("AI engine")
                } footer: {
                    Text("Automatic uses Apple Intelligence when your iPhone supports it, then Gemini if you added a key, and otherwise offline mode, which builds cards from your notes without AI.")
                }

                Section {
                    LabeledContent("Status", value: StudyAI.appleIntelligenceStatus)
                } header: {
                    Text("Apple Intelligence")
                } footer: {
                    Text("Runs privately on your device. Needs iPhone 15 Pro or newer with Apple Intelligence turned on.")
                }

                Section {
                    SecureField("API key", text: $geminiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("geminiKeyField")
                    TextField("Model", text: $geminiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Google Gemini (optional)")
                } footer: {
                    Text("Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey). It's stored in your device's Keychain.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDoneButton")
                }
            }
            .onChange(of: geminiKey) { _, newValue in
                Keychain.geminiAPIKey = newValue.trimmed
            }
        }
    }
}
