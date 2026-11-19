import SwiftData
import SwiftUI

struct TutorChatView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    private let suggestions = ["Explain the main ideas simply", "Quiz me on this", "What should I focus on?"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Bubble(text: "Hi! I'm your tutor for “\(deck.title)”. Ask me anything about your notes.", isUser: false)
                    if deck.messages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { send(suggestion) }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                    ForEach(deck.sortedMessages) { message in
                        Bubble(text: message.text, isUser: message.isUser)
                            .id(message.order)
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .id(-1)
                        .accessibilityIdentifier("tutorThinking")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: deck.messages.count) {
                withAnimation { proxy.scrollTo(deck.messages.count - 1, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle("AI tutor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deck.messages.isEmpty {
                Button("Clear") { deck.messages.forEach(context.delete) }
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
        deck.messages.append(ChatMessage(isUser: true, text: question, order: deck.messages.count))
        draft = ""
        isThinking = true
        Task {
            let reply = await StudyAI.tutorReply(notes: deck.notes, title: deck.title, history: history, question: question)
            deck.messages.append(ChatMessage(isUser: false, text: reply, order: deck.messages.count))
            isThinking = false
        }
    }
}

private struct Bubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(text)
                .padding(12)
                .foregroundStyle(isUser ? .white : .primary)
                .background(isUser ? Color.indigo : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
                .accessibilityIdentifier(isUser ? "userMessage" : "assistantMessage")
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
