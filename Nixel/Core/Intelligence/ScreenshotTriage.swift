import Foundation
import Vision
import Photos

/// Reads the text in screenshots and asks the on-device model what each one is.
///
/// Pipeline per screenshot: local thumbnail -> Vision OCR -> Apple Intelligence -> typed
/// verdict, cached by asset id. Nothing leaves the phone at any step.
///
/// Why this exists: the difference between "40 screenshots, 180 MB" and "37 memes you can
/// clear, plus 3 that look like receipts — check those first" is the difference between a
/// list and a decision. It also removes the main reason people don't trust cleaners, which
/// is deleting the boarding pass along with the memes.
actor ScreenshotTriage {

    private var cache: [String: ScreenshotVerdict] = [:]
    private let cacheURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("screenshot-verdicts.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: ScreenshotVerdict].self, from: data) {
            cache = decoded
        }
    }

    func verdict(for id: String) -> ScreenshotVerdict? { cache[id] }

    func allVerdicts() -> [String: ScreenshotVerdict] { cache }

    /// Triages every screenshot that hasn't been classified yet.
    ///
    /// There is no cap: the whole set gets read. It runs after the grid is already on
    /// screen and writes its cache incrementally, so the user never waits on the model to
    /// see their screenshots — categories simply fill in as they are decided. `limit` only
    /// exists as a safety valve for pathological libraries.
    func triage(
        _ assets: [PhotoAsset],
        limit: Int = 5_000,
        progress: @Sendable @escaping (Double) -> Void
    ) async {
        let pending = assets.filter { cache[$0.id] == nil }.prefix(limit)
        guard !pending.isEmpty else {
            progress(1)
            return
        }

        var done = 0
        for asset in pending {
            if Task.isCancelled { break }

            if let text = await Self.recognisedText(in: asset.phAsset),
               let verdict = await IntelligenceService.shared.triage(text: text) {
                cache[asset.id] = verdict
            } else {
                // Unreadable or the model is unavailable — record a neutral verdict so we
                // don't retry it every scan, and never claim it's safe to delete.
                cache[asset.id] = ScreenshotVerdict(kind: .other, safeToDelete: false,
                                                    reason: "Not analysed")
            }

            done += 1
            progress(Double(done) / Double(pending.count))
            if done % 10 == 0 { persist() }
        }

        persist()
    }

    func forget(ids: Set<String>) {
        for id in ids { cache.removeValue(forKey: id) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: OCR

    /// Pulls text out of a screenshot. `.fast` is the right level here: we only need enough
    /// words to tell a receipt from a meme, not a faithful transcription.
    private static func recognisedText(in asset: PHAsset) async -> String? {
        guard let cgImage = await SimilarityEngine.analysisImage(
            for: asset, side: 900, contentMode: .aspectFit) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}
