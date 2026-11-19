import Foundation

struct GeminiProvider: StudyAIProvider {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    func makeStudySet(from notes: String, title: String) async throws -> GeneratedStudySet {
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": StudyAI.studySetInstructions]]],
            "contents": [["role": "user", "parts": [["text": "Title: \(title)\n\nNotes:\n\(notes)"]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.studySetSchema,
            ],
        ]
        let text = try await generate(body)
        guard let data = text.data(using: .utf8) else { throw StudyAIError.badResponse("not text") }
        do {
            return try JSONDecoder().decode(GeneratedStudySet.self, from: data)
        } catch {
            throw StudyAIError.badResponse("invalid JSON")
        }
    }

    func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async throws -> String {
        let contents = (history + [TutorTurn(isUser: true, text: question)]).map { turn in
            ["role": turn.isUser ? "user" : "model", "parts": [["text": turn.text]]] as [String: Any]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": StudyAI.tutorInstructions(title: title, notes: notes)]]],
            "contents": contents,
        ]
        return try await generate(body)
    }

    private func generate(_ body: [String: Any]) async throws -> String {
        guard !apiKey.isEmpty else { throw StudyAIError.missingAPIKey }
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            throw StudyAIError.badResponse("bad model name")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw StudyAIError.badResponse(message ?? "HTTP \(status)")
        }
        return try Self.text(from: json)
    }

    static func text(from json: [String: Any]?) throws -> String {
        guard
            let candidates = json?["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { throw StudyAIError.badResponse("no candidates") }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw StudyAIError.badResponse("empty reply") }
        return text
    }

    static let studySetSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "flashcards": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": ["front": ["type": "STRING"], "back": ["type": "STRING"]],
                    "required": ["front", "back"],
                ],
            ],
            "quiz": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "question": ["type": "STRING"],
                        "options": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "answerIndex": ["type": "INTEGER"],
                        "explanation": ["type": "STRING"],
                    ],
                    "required": ["question", "options", "answerIndex", "explanation"],
                ],
            ],
        ],
        "required": ["flashcards", "quiz"],
    ]
}
