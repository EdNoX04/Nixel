import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a screenshot appears to be.
enum ScreenshotKind: String, Codable, CaseIterable {
    case receipt, ticket, conversation, meme, article, credential, settings, other

    var label: String {
        switch self {
        case .receipt:      return "Receipt"
        case .ticket:       return "Ticket or pass"
        case .conversation: return "Conversation"
        case .meme:         return "Meme or social"
        case .article:      return "Article or reference"
        case .credential:   return "Code or password"
        case .settings:     return "App or settings"
        case .other:        return "Other"
        }
    }

    /// Categories where losing the screenshot could actually cost the user something.
    /// These are never auto-suggested for deletion, regardless of what the model says.
    var isSensitive: Bool {
        switch self {
        case .receipt, .ticket, .credential: return true
        default: return false
        }
    }
}

/// A triaged screenshot.
struct ScreenshotVerdict: Codable, Hashable {
    var kind: ScreenshotKind
    var safeToDelete: Bool
    var reason: String
}

/// Why on-device intelligence isn't usable right now.
enum IntelligenceAvailability: Equatable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case osTooOld

    var isAvailable: Bool { self == .available }

    var explanation: String {
        switch self {
        case .available:         return "On-device intelligence is ready."
        case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
        case .notEnabled:        return "Turn on Apple Intelligence in Settings to enable smart triage."
        case .modelNotReady:     return "Apple Intelligence is still downloading its model."
        case .osTooOld:          return "Smart triage needs iOS 26 or later."
        }
    }
}

/// Wraps Apple's on-device foundation model.
///
/// Everything here runs on the phone — the model is local, so screenshot contents never
/// leave the device. That matters twice over: the brief requires it, and the input is OCR
/// text from someone's private screenshots.
///
/// The app degrades cleanly: on a device without Apple Intelligence every screen still
/// works, it just doesn't offer the category breakdown.
@MainActor
final class IntelligenceService {

    static let shared = IntelligenceService()

    fileprivate(set) var availability: IntelligenceAvailability = .osTooOld

    init() {
        trace("IntelligenceService: init")
        refreshAvailability()
    }

    /// Resolves availability off the main thread and publishes it.
    ///
    /// Asking the system model whether it is ready can touch its assets, which on a real
    /// phone — particularly just after it wakes — is not something to do on the thread that
    /// draws the UI. Until it resolves, `availability` reads as "not ready", which every
    /// caller already handles.
    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .osTooOld
            return
        }
        if availability == .osTooOld { availability = .modelNotReady }
        Task.detached(priority: .utility) {
            let resolved = Self.resolveAvailability()
            await MainActor.run {
                IntelligenceService.shared.availability = resolved
                trace("IntelligenceService: availability \(resolved)")
            }
        }
        #else
        availability = .osTooOld
        #endif
    }

    /// The same answer, computed where the caller is rather than on the main thread.
    nonisolated func currentAvailability() async -> IntelligenceAvailability {
        await Task.detached(priority: .utility) { Self.resolveAvailability() }.value
    }

    nonisolated static func resolveAvailability() -> IntelligenceAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .osTooOld }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady:               return .modelNotReady
            @unknown default:                  return .modelNotReady
            }
        }
        #else
        return .osTooOld
        #endif
    }

    // MARK: Screenshot triage

    /// Classifies a screenshot from the text found in it.
    ///
    /// The model returns a *typed* value via `@Generable` rather than free text, so there
    /// is no parsing step that can silently fail — an answer either conforms to the schema
    /// or it throws.
    nonisolated func triage(text: String) async -> ScreenshotVerdict? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), await availability.isAvailable else { return nil }

        let trimmed = String(text.prefix(600))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        do {
            let content = try await ModelRunner.shared.classify(trimmed)
            let kind = ScreenshotKind(rawValue: content.kind.rawValue) ?? .other
            // Safety override: never mark anything that could cost the user money or
            // access as safe to delete, whatever the model concluded.
            return ScreenshotVerdict(
                kind: kind,
                safeToDelete: content.safeToDelete && !kind.isSensitive,
                reason: content.reason
            )
        } catch {
            // The model declines some content outright. A boarding pass reliably trips it,
            // which is precisely the kind of screenshot we must not get wrong, so fall back
            // to a local keyword read rather than returning "unknown".
            return Self.keywordVerdict(for: text)
        }
        #else
        return Self.keywordVerdict(for: text)
        #endif
    }

    /// A deterministic, offline second opinion.
    ///
    /// Used when the model is unavailable or refuses. It only ever votes for the
    /// *cautious* answer: it can mark something sensitive, never safe to delete. Missing a
    /// meme costs nothing; letting a boarding pass through as "safe" costs a flight.
    nonisolated static func keywordVerdict(for text: String) -> ScreenshotVerdict? {
        let haystack = text.lowercased()
        func any(_ needles: [String]) -> Bool { needles.contains { haystack.contains($0) } }

        if any(["boarding pass", "flight", "gate ", "seat ", "departure", "e-ticket",
                "booking reference", "confirmation code", "pnr"]) {
            return ScreenshotVerdict(kind: .ticket, safeToDelete: false,
                                     reason: "Looks like a travel pass")
        }
        if any(["verification code", "one-time", "one time code", "otp", "2fa",
                "do not share", "never share", "authentication code", "passcode"]) {
            return ScreenshotVerdict(kind: .credential, safeToDelete: false,
                                     reason: "Looks like a security code")
        }
        if any(["subtotal", "total", "vat", "invoice", "receipt", "amount paid",
                "order #", "order no", "paid with"]) {
            return ScreenshotVerdict(kind: .receipt, safeToDelete: false,
                                     reason: "Looks like a receipt")
        }
        return nil
    }

    /// One plain sentence describing what a scan turned up, for the daily notification.
    ///
    /// The model is given the numbers but not trusted with their meaning. An early version
    /// produced "695 KB safe to keep" for a figure that was actually the space *recoverable
    /// by deleting* — exactly inverted, on the one screen where being wrong about a number
    /// destroys trust. So the result is validated before use and a deterministic sentence
    /// is substituted if it looks off.
    nonisolated func summarise(duplicates: Int, screenshots: Int, videos: Int, bytes: Int64) async -> String? {
        let fallback = Self.plainSummary(duplicates: duplicates, screenshots: screenshots,
                                         videos: videos, bytes: bytes)
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), await availability.isAvailable else { return fallback }

        let prompt = """
        Write one friendly sentence, 16 words or fewer, for a phone storage-cleaning app.
        Meaning to convey: deleting these items would RECOVER \(Bytes.string(bytes)) of storage.
        Items found: \(duplicates) duplicate photos, \(screenshots) screenshots, \(videos) large videos.
        Rules: use only the numbers given, never invent others. Do not say the space is         "kept", "saved" or "safe to keep" — the space is recovered by removing the items.         Do not claim anything has been deleted yet.
        """

        do {
            let text = try await ModelRunner.shared.write(prompt)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.isTrustworthy(text, bytes: bytes) ? text : fallback
        } catch {
            return fallback
        }
        #else
        return fallback
        #endif
    }

    /// Rejects a generated sentence that inverts the meaning or invents figures.
    nonisolated static func isTrustworthy(_ text: String, bytes: Int64) -> Bool {
        guard !text.isEmpty, text.count <= 160 else { return false }
        let lower = text.lowercased()

        // The inversion we actually observed, plus its near neighbours.
        let inversions = ["safe to keep", "kept safe", "saved to keep", "space is kept",
                          "freed up already", "have been deleted", "were deleted", "deleted them"]
        if inversions.contains(where: lower.contains) { return false }

        // Any size figure it mentions must be the one we handed it.
        let expected = Bytes.string(bytes).lowercased()
        let sizePattern = #"\d+(\.\d+)?\s?(bytes|kb|mb|gb|tb)"#
        if let regex = try? NSRegularExpression(pattern: sizePattern) {
            let range = NSRange(lower.startIndex..., in: lower)
            for match in regex.matches(in: lower, range: range) {
                guard let r = Range(match.range, in: lower) else { continue }
                let found = lower[r].replacingOccurrences(of: " ", with: "")
                if !expected.replacingOccurrences(of: " ", with: "").contains(found) {
                    return false
                }
            }
        }
        return true
    }

    /// The sentence we can always stand behind.
    nonisolated static func plainSummary(duplicates: Int, screenshots: Int, videos: Int, bytes: Int64) -> String {
        let total = duplicates + screenshots + videos
        guard total > 0 else { return "Nothing to clean up right now." }
        var parts: [String] = []
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if screenshots > 0 { parts.append("\(screenshots) screenshot\(screenshots == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) large video\(videos == 1 ? "" : "s")") }
        return "Removing \(parts.joined(separator: ", ")) would free \(Bytes.string(bytes))."
    }

    // MARK: Session

    #if canImport(FoundationModels)
    // Not `private`: the @Generable macro expands to code that must see these.
    @available(iOS 26.0, *)
    @Generable
    enum GeneratedKind: String {
        case receipt, ticket, conversation, meme, article, credential, settings, other
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedVerdict {
        @Guide(description: "What this screenshot mainly is")
        let kind: GeneratedKind
        @Guide(description: "True only if losing this clearly would not matter to anyone")
        let safeToDelete: Bool
        @Guide(description: "Six words or fewer explaining the call")
        let reason: String
    }
    #endif
}


#if canImport(FoundationModels)
/// Owns the language model session, off the main thread.
///
/// `IntelligenceService` is main-actor bound because views read its availability. The
/// session used to live there too, so creating it — and every request made through it —
/// was scheduled on the thread that draws the UI. It now lives in its own actor: requests
/// are still serialised, which a session requires, but never at the UI's expense.
@available(iOS 26.0, *)
actor ModelRunner {
    static let shared = ModelRunner()

    private var session: LanguageModelSession?

    private func activeSession() -> LanguageModelSession {
        if let existing = session { return existing }
        trace("ModelRunner: creating session")
        let created = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
            You classify iPhone screenshots so a storage-cleaning app can suggest which are \
            safe to delete. You are cautious: anything that looks like proof of purchase, \
            travel, identity, a verification code or a password is never safe to delete. \
            Memes, social posts and app UI screenshots usually are. Keep reasons under six words.
            """
        )
        session = created
        return created
    }

    func classify(_ text: String) async throws -> IntelligenceService.GeneratedVerdict {
        let response = try await activeSession().respond(
            to: "Screenshot text:\n\(text)",
            generating: IntelligenceService.GeneratedVerdict.self
        )
        return response.content
    }

    func write(_ prompt: String) async throws -> String {
        try await activeSession().respond(to: prompt).content
    }

    /// Sessions do not survive the app being suspended reliably; start fresh on return.
    func reset() { session = nil }
}
#endif
