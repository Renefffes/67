import SwiftData
import SwiftUI

@main
struct StudyMateApp: App {
    let container: ModelContainer

    init() {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: AppEnvironment.isUITesting)
        do {
            container = try ModelContainer(
                for: Deck.self, Flashcard.self, QuizQuestion.self, ChatMessage.self,
                configurations: configuration
            )
        } catch {
            fatalError("Could not open the study library: \(error)")
        }
        if AppEnvironment.isUITesting {
            UIView.setAnimationsEnabled(false)
            UserDefaults.standard.removeObject(forKey: StudyAI.engineKey)
            UserDefaults.standard.removeObject(forKey: StudyAI.geminiModelKey)
            Keychain.geminiAPIKey = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            DeckListView()
        }
        .modelContainer(container)
    }
}

enum AppEnvironment {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
