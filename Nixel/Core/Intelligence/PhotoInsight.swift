import Foundation
import Photos
import CoreGraphics
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A one-line description of what a set of near-identical photos actually shows.
struct GroupInsight: Codable, Hashable {
    var label: String        // e.g. "Sunset over the harbour"
    var keeperIndex: Int?    // which shot the model would keep, if it had a view
}

/// Describes photo *content* using the on-device model's image input.
///
/// iOS 27's foundation model accepts images directly (`Attachment(cgImage)`), not just
/// text, so this reaches past the OCR-only path used for screenshots: it looks at the
/// actual photograph. That is what lets a duplicate group say "Four shots of the harbour
/// at sunset" instead of "4 similar".
///
/// Everything stays on the device — the model is local, and a photo library is about the
/// most private thing on a phone.
actor PhotoInsight {

    private var cache: [String: GroupInsight] = [:]
    private let cacheURL: URL

    /// Describing every group up front would stall the scan, so groups are described
    /// lazily as they come into view and the answer is kept.
    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("group-insights.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: GroupInsight].self, from: data) {
            cache = decoded
        }
    }

    func insight(for groupID: String) -> GroupInsight? { cache[groupID] }

    /// Describes one group. Returns nil when the model is unavailable or declines.
    @discardableResult
    func describe(group: PhotoGroup) async -> GroupInsight? {
        if let cached = cache[group.id] { return cached }

        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *),
              await IntelligenceService.shared.availability.isAvailable else { return nil }

        // Show the model the suggested keeper — one image is enough to name the scene,
        // and sending four costs four times as much for no extra insight.
        let anchor = group.best ?? group.assets[0]
        guard let image = await SimilarityEngine.analysisImage(
            for: anchor.phAsset, side: 512, contentMode: .aspectFit) else { return nil }

        do {
            let session = LanguageModelSession(
                instructions: """
                You name what a photo shows, for a storage-cleaning app that has found \
                several near-identical copies of it. Reply with a short noun phrase of at \
                most five words, sentence case, no trailing full stop. Describe only what \
                is visible. Do not mention people's identities.
                """
            )
            let response = try await session.respond(
                to: Prompt {
                    "Name the scene in this photo."
                    Attachment(image)
                },
                generating: GeneratedLabel.self
            )
            let cleaned = Self.tidy(response.content.label)
            guard !cleaned.isEmpty else { return nil }

            let insight = GroupInsight(label: cleaned, keeperIndex: nil)
            cache[group.id] = insight
            persist()
            return insight
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    func forget(groupIDs: Set<String>) {
        for id in groupIDs { cache.removeValue(forKey: id) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
            cacheURL.excludeFromBackup()
        }
    }

    /// Small models like to answer in a sentence however firmly you ask for a phrase.
    private static func tidy(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\"", with: "")
        if text.hasSuffix(".") { text.removeLast() }
        let words = text.split(separator: " ")
        if words.count > 6 { text = words.prefix(6).joined(separator: " ") }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    #if canImport(FoundationModels)
    @available(iOS 27.0, *)
    @Generable
    struct GeneratedLabel {
        @Guide(description: "At most five words naming what the photo shows")
        let label: String
    }
    #endif
}
