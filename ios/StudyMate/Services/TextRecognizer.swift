import UIKit
import Vision

enum TextRecognizer {
    /// Reads printed or handwritten text from photos of notes, on device.
    static func recognizeText(in images: [UIImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let text = try await recognize(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            if !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: reflow(lines))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Joins lines the page wrapped mid-sentence ("…when angry" + "citizens stormed…"),
    /// keeping real line breaks such as headings and bullet points.
    static func reflow(_ lines: [String]) -> String {
        var result: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let previous = result.last ?? ""
            let hyphenated = previous.hasSuffix("-") && previous.dropLast().last?.isLetter == true
            if let last = previous.last, let first = line.first, first.isLowercase,
               !".!?:;。！？".contains(last), hyphenated || !startsDefinition(line) {
                result[result.count - 1] = hyphenated ? String(previous.dropLast()) + line : previous + " " + line
            } else {
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    private static func startsDefinition(_ line: String) -> Bool {
        line.range(of: #"^\S+(\s\S+){0,3}?\s*(:|=>|->|→|=)\s"#, options: .regularExpression) != nil
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }

}
