import SwiftData
import SwiftUI

struct TutorChatView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var isThinking = false
    @State private var confirmingClear = false
    @State private var conversationID = UUID()
    @FocusState private var inputFocused: Bool

    private let suggestions = ["Explain the main ideas simply", "Quiz me on this", "What should I focus on?"]
    private static let thinkingID = "thinking"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Bubble(text: "Hi! I'm your tutor for “\(deck.title)”. Ask me anything about your notes.", isUser: false)
                    if deck.messages.isEmpty {
                        VStack(alignment: .trailing, spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { send(suggestion) }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    ForEach(deck.sortedMessages) { message in
                        Bubble(text: message.text, isUser: message.isUser)
                            .id(message.persistentModelID)
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .id(Self.thinkingID)
                        .accessibilityIdentifier("tutorThinking")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: deck.messages.count) { scrollToLatest(proxy) }
            .onChange(of: isThinking) { scrollToLatest(proxy) }
            .onChange(of: inputFocused) { if inputFocused { scrollToLatest(proxy, delay: .milliseconds(350)) } }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle("AI tutor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deck.messages.isEmpty {
                Button("Clear") { confirmingClear = true }
                    .disabled(isThinking)
                    .accessibilityIdentifier("chatClearButton")
            }
        }
        .alert("Clear this conversation?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                conversationID = UUID()
                deck.messages.forEach(context.delete)
                deck.messages.removeAll()
            }
        } message: {
            Text("All messages with the tutor for this deck will be deleted.")
        }
    }

    /// Shows the newest message; a long tutor reply is shown from its first line so the student can read it top-down.
    private func scrollToLatest(_ proxy: ScrollViewProxy, delay: Duration = .milliseconds(50)) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            withAnimation {
                if isThinking {
                    proxy.scrollTo(Self.thinkingID, anchor: .bottom)
                } else if let last = deck.sortedMessages.last {
                    proxy.scrollTo(last.persistentModelID, anchor: last.isUser ? .bottom : .top)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your notes…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .accessibilityIdentifier("chatInput")
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
            }
            .disabled(draft.trimmed.isEmpty || isThinking)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        let question = text.trimmed
        guard !question.isEmpty, !isThinking else { return }
        let history = deck.sortedMessages.map { TutorTurn(isUser: $0.isUser, text: $0.text) }
        deck.messages.append(ChatMessage(isUser: true, text: question, order: nextOrder))
        draft = ""
        isThinking = true
        let conversation = conversationID
        Task {
            let reply = await StudyAI.tutorReply(notes: deck.notes, title: deck.title, history: history, question: question)
            isThinking = false
            guard conversation == conversationID else { return }
            deck.messages.append(ChatMessage(isUser: false, text: reply, order: nextOrder))
        }
    }

    private var nextOrder: Int { (deck.messages.map(\.order).max() ?? -1) + 1 }
}

private struct Bubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(isUser ? AttributedString(text) : TutorText.attributed(text))
                .padding(12)
                .foregroundStyle(isUser ? .white : .primary)
                .background(isUser ? Color.indigo : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
                .accessibilityIdentifier(isUser ? "userMessage" : "assistantMessage")
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

/// Turns the Markdown that Gemini and Apple Intelligence write (bold, lists, headings) into styled text.
enum TutorText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            var isHeading = false
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), hashes != trimmed.startIndex, trimmed[hashes] == " " {
                line = String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)
                isHeading = true
            } else if let marker = ["* ", "- ", "+ "].first(where: trimmed.hasPrefix) {
                let indent = rawLine.prefix { $0 == " " }.count >= 2 ? "    " : ""
                line = indent + "• " + trimmed.dropFirst(marker.count)
            }
            var piece = (try? AttributedString(
                markdown: escapingLiteralMarks(line),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(line)
            if isHeading { piece.font = .headline }
            result += piece
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }

    /// Escapes blanks and in-word `*` (as in 2*3) so they aren't read as emphasis, leaving `code spans` untouched.
    private static func escapingLiteralMarks(_ line: String) -> String {
        line.components(separatedBy: "`").enumerated().map { index, part in
            index.isMultiple(of: 2)
                ? part
                    .replacingOccurrences(of: "_____", with: "\\_\\_\\_\\_\\_")
                    .replacingOccurrences(of: #"(?<=[A-Za-z0-9])\*(?=[A-Za-z0-9])"#, with: #"\\*"#, options: .regularExpression)
                : part
        }.joined(separator: "`")
    }
}
