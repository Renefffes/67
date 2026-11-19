import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StudyAI.engineKey) private var engine: AIEngine = .automatic
    @AppStorage(StudyAI.geminiModelKey) private var geminiModel = StudyAI.defaultGeminiModel
    @State private var savedKey = Keychain.geminiAPIKey ?? ""
    @State private var keyDraft = ""
    @State private var keyCheck: KeyCheck = .idle

    private enum KeyCheck: Equatable {
        case idle, checking, ok(String), failed(String)
    }

    private var hasKey: Bool { !savedKey.isEmpty }
    private var activeEngine: AIEngine { StudyAI.effectiveEngine(engine, hasGeminiKey: hasKey) }

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                appleIntelligenceSection
                geminiSection
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if saveDraftKey() { dismiss() }
                    }
                    .accessibilityIdentifier("settingsDoneButton")
                }
            }
        }
    }

    private var engineSection: some View {
        Section {
            Picker("AI engine", selection: $engine) {
                ForEach(AIEngine.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("enginePicker")
            LabeledContent("Currently using", value: activeEngine.displayName)
                .accessibilityIdentifier("activeEngineLabel")
            if let warning = engineWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("engineWarning")
            }
        } header: {
            Text("AI engine")
        } footer: {
            Text("Automatic uses Apple Intelligence when your iPhone supports it, then Gemini if you added a key, and otherwise offline mode, which builds cards from your notes without AI.")
        }
    }

    private var engineWarning: String? {
        switch engine {
        case .gemini where !hasKey:
            "Add your Gemini API key below to use Gemini. Until then StudyMate uses offline mode."
        case .appleIntelligence where !StudyAI.appleIntelligenceUsable:
            "Apple Intelligence isn't available here (\(StudyAI.appleIntelligenceDisplayStatus.lowercased())), so StudyMate uses offline mode."
        default:
            nil
        }
    }

    private var appleIntelligenceSection: some View {
        Section {
            LabeledContent("Status", value: StudyAI.appleIntelligenceDisplayStatus)
                .accessibilityIdentifier("appleIntelligenceStatus")
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Runs privately on your device. Needs iPhone 15 Pro or newer with Apple Intelligence turned on.")
        }
    }

    private var geminiSection: some View {
        Section {
            if hasKey {
                LabeledContent("API key", value: "Saved ••••\(savedKey.suffix(4))")
                    .accessibilityIdentifier("geminiKeySaved")
                    .accessibilityValue("Saved, ending in \(savedKey.suffix(4).map(String.init).joined(separator: " "))")
                Button {
                    Task { await checkKey() }
                } label: {
                    HStack {
                        Label("Check key", systemImage: "checkmark.shield")
                        if keyCheck == .checking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(keyCheck == .checking)
                .accessibilityIdentifier("checkGeminiKeyButton")
                switch keyCheck {
                case .ok(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("geminiKeyCheckResult")
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("geminiKeyCheckResult")
                case .idle, .checking:
                    EmptyView()
                }
                Button("Remove key", role: .destructive) {
                    Keychain.geminiAPIKey = nil
                    savedKey = ""
                    keyCheck = .idle
                }
                .accessibilityIdentifier("removeGeminiKeyButton")
            } else {
                TextField("Paste your API key", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { saveDraftKey() }
                    .accessibilityLabel("Gemini API key")
                    .accessibilityIdentifier("geminiKeyField")
                if !keyDraft.trimmed.isEmpty && !keyDraft.trimmed.hasPrefix("AIza") {
                    Text("Gemini keys usually start with “AIza”. Check that you copied the whole key.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("geminiKeyFormatHint")
                }
                Button("Save key") { saveDraftKey() }
                    .disabled(keyDraft.trimmed.isEmpty)
                    .accessibilityIdentifier("saveGeminiKeyButton")
                if case .failed(let message) = keyCheck {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("geminiKeySaveError")
                }
            }
            LabeledContent("Model") {
                TextField(StudyAI.defaultGeminiModel, text: $geminiModel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Gemini model")
                    .accessibilityIdentifier("geminiModelField")
            }
        } header: {
            Text("Google Gemini (optional)")
        } footer: {
            Text("Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), copy it and paste it here. It's stored only in your device's Keychain.")
        }
    }

    @discardableResult
    private func saveDraftKey() -> Bool {
        let key = keyDraft.filter { !$0.isWhitespace }
        guard !key.isEmpty else { return true }
        Keychain.geminiAPIKey = key
        guard let stored = Keychain.geminiAPIKey, stored == key else {
            keyCheck = .failed("Couldn't save the key to this device's Keychain. Try again.")
            return false
        }
        savedKey = stored
        keyDraft = ""
        keyCheck = .idle
        return true
    }

    private func checkKey() async {
        keyCheck = .checking
        let model = StudyAI.geminiModel
        do {
            try await GeminiKeyChecker.check(apiKey: savedKey, model: model)
            keyCheck = .ok("Key works with \(model)")
        } catch {
            keyCheck = .failed(error.localizedDescription)
        }
    }
}

extension StudyAI {
    /// The engine the student picked in Settings, ignoring the offline override used for UI tests.
    static var storedEngine: AIEngine {
        AIEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .automatic
    }

    /// The engine that will actually make cards for a given choice, after falling back to offline mode.
    static func effectiveEngine(_ engine: AIEngine, hasGeminiKey: Bool) -> AIEngine {
        switch engine {
        case .automatic: appleIntelligenceUsable ? .appleIntelligence : (hasGeminiKey ? .gemini : .offline)
        case .appleIntelligence: appleIntelligenceUsable ? .appleIntelligence : .offline
        case .gemini: hasGeminiKey ? .gemini : .offline
        case .offline: .offline
        }
    }

    /// UI tests behave like an iPhone without Apple Intelligence so results don't depend on the test machine.
    static var appleIntelligenceUsable: Bool { !AppEnvironment.isUITesting && appleIntelligenceAvailable && !appleIntelligenceFailed }

    static var appleIntelligenceDisplayStatus: String {
        AppEnvironment.isUITesting ? "This device doesn't support Apple Intelligence" : appleIntelligenceStatus
    }
}

enum GeminiKeyChecker {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func check(apiKey: String, model: String, session: URLSession = .shared) async throws {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel)") else {
            throw Failure(errorDescription: "“\(model)” isn't a valid model name")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure(errorDescription: "Couldn't reach Google. Check your internet connection.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if (200..<300).contains(status) {
            if let methods = json?["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") {
                throw Failure(errorDescription: "Model “\(model)” can't write flashcards. Try \(StudyAI.defaultGeminiModel).")
            }
            return
        }
        let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
        switch status {
        case 400 where message.localizedCaseInsensitiveContains("api key"), 401, 403:
            throw Failure(errorDescription: "Google didn't accept this key. Copy it again from AI Studio.")
        case 404:
            throw Failure(errorDescription: "Model “\(model)” wasn't found. Try \(StudyAI.defaultGeminiModel).")
        default:
            throw Failure(errorDescription: message.isEmpty ? "Google returned an error (HTTP \(status))" : message)
        }
    }
}
