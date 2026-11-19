import NaturalLanguage
import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

struct NewDeckView: View {
    var startWithSample = false
    var onCreated: (Deck) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingScanner = false
    @State private var isReadingPhotos = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var photoMessage: String?
    @FocusState private var notesFocused: Bool

    private var wordCount: Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = notes
        return tokenizer.tokens(for: notes.startIndex..<notes.endIndex).count
    }
    private var wordCountText: String {
        let count = "\(wordCount) \(wordCount == 1 ? "word" : "words")"
        return (1..<15).contains(wordCount) ? "\(count) · Add a few full sentences or definitions for better flashcards." : count
    }
    private var canGenerate: Bool { !notes.trimmed.isEmpty && !isGenerating && !isReadingPhotos }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField(notes.trimmed.isEmpty ? "e.g. Biology – The Cell" : defaultTitle, text: $title)
                        .accessibilityIdentifier("deckTitleField")
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("notesEditor")
                        .focused($notesFocused)
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Paste or type your notes here…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Your notes")
                } footer: {
                    Text(wordCountText).accessibilityIdentifier("wordCountLabel")
                }
                Section("Add from a photo") {
                    if VNDocumentCameraViewController.isSupported {
                        Button { showingScanner = true } label: {
                            Label("Scan notes with the camera", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Label("Choose photos of notes", systemImage: "photo.on.rectangle")
                    }
                    if isReadingPhotos {
                        HStack {
                            ProgressView()
                            Text("Reading text from your photos…").foregroundStyle(.secondary)
                        }
                    } else if let photoMessage {
                        Label(photoMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("photoTextAdded")
                    }
                }
                Section {
                    Button {
                        title = SampleNotes.title
                        notes = SampleNotes.text
                    } label: {
                        Label("Try with sample notes", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("sampleNotesButton")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isGenerating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { Task { await generate() } }
                        .disabled(!canGenerate)
                        .accessibilityIdentifier("generateButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }
                }
            }
            .overlay {
                if isGenerating {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Creating flashcards and a quiz…").font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("generatingIndicator")
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    Task { await addText(from: images) }
                }
                .ignoresSafeArea()
            }
            .interactiveDismissDisabled(isGenerating)
            .onAppear {
                guard startWithSample, notes.isEmpty else { return }
                title = SampleNotes.title
                notes = SampleNotes.text
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isReadingPhotos = true
        defer { isReadingPhotos = false }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        await addText(from: images)
    }

    private func addText(from images: [UIImage]) async {
        guard !images.isEmpty else { return }
        notesFocused = false
        photoMessage = nil
        isReadingPhotos = true
        defer { isReadingPhotos = false }
        do {
            let text = try await TextRecognizer.recognizeText(in: images)
            if text.trimmed.isEmpty {
                errorMessage = "Couldn't find any text in those photos. Try a clearer, well-lit shot."
            } else {
                errorMessage = nil
                notes = notes.trimmed.isEmpty ? text : notes + "\n\n" + text
                let photos = images.count == 1 ? "1 photo" : "\(images.count) photos"
                photoMessage = "Added text from \(photos) to your notes. Check it for misread words before generating."
            }
        } catch {
            errorMessage = "Couldn't read the photos: \(error.localizedDescription)"
        }
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        let source = notes
        let deckTitle = title.trimmed.isEmpty ? defaultTitle : title.trimmed
        let outcome = await StudyAI.makeStudySet(notes: source, title: deckTitle)
        let deck = Deck(title: deckTitle, notes: source.trimmed, engine: outcome.engine.displayName)
        context.insert(deck)
        deck.apply(outcome.set, engine: outcome.engine, note: outcome.note)
        isGenerating = false
        do {
            try context.save()
        } catch {
            context.delete(deck)
            errorMessage = "Couldn't save the deck: \(error.localizedDescription)"
            return
        }
        dismiss()
        onCreated(deck)
    }

    private var defaultTitle: String {
        let firstLine = notes.trimmed.components(separatedBy: .newlines).first ?? ""
        let words = firstLine.split(separator: " ").prefix(5).joined(separator: " ")
            .replacingOccurrences(of: #"[\s!?.:;,*#-]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[#*\s-]+|\*\*"#, with: "", options: .regularExpression)
        return words.isEmpty ? "Untitled deck" : words
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
