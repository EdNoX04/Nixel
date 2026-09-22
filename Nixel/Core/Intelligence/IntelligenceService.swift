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

    private(set) var availability: IntelligenceAvailability = .osTooOld

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var session: LanguageModelSession? {
        get { _session as? LanguageModelSession }
        set { _session = newValue }
    }
    private var _session: AnyObject?
    #endif

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .osTooOld
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:          availability = .deviceNotEligible
            case .appleIntelligenceNotEnabled: availability = .notEnabled
            case .modelNotReady:              availability = .modelNotReady
            @unknown default:                 availability = .modelNotReady
            }
        }
        #else
        availability = .osTooOld
        #endif
    }

    // MARK: Screenshot triage

    /// Classifies a screenshot from the text found in it.
    ///
    /// The model returns a *typed* value via `@Generable` rather than free text, so there
    /// is no parsing step that can silently fail — an answer either conforms to the schema
    /// or it throws.
    func triage(text: String) async -> ScreenshotVerdict? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return nil }

        let trimmed = String(text.prefix(600))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        do {
            let session = try activeSession()
            let response = try await session.respond(
                to: "Screenshot text:\n\(trimmed)",
                generating: GeneratedVerdict.self
            )
            let content = response.content
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
    static func keywordVerdict(for text: String) -> ScreenshotVerdict? {
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
    func summarise(duplicates: Int, screenshots: Int, videos: Int, bytes: Int64) async -> String? {
        let fallback = Self.plainSummary(duplicates: duplicates, screenshots: screenshots,
                                         videos: videos, bytes: bytes)
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }

        let prompt = """
        Write one friendly sentence, 16 words or fewer, for a phone storage-cleaning app.
        Meaning to convey: deleting these items would RECOVER \(Bytes.string(bytes)) of storage.
        Items found: \(duplicates) duplicate photos, \(screenshots) screenshots, \(videos) large videos.
        Rules: use only the numbers given, never invent others. Do not say the space is         "kept", "saved" or "safe to keep" — the space is recovered by removing the items.         Do not claim anything has been deleted yet.
        """

        do {
            let session = try activeSession()
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.isTrustworthy(text, bytes: bytes) ? text : fallback
        } catch {
            return fallback
        }
        #else
        return fallback
        #endif
    }

    /// Rejects a generated sentence that inverts the meaning or invents figures.
    static func isTrustworthy(_ text: String, bytes: Int64) -> Bool {
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
    static func plainSummary(duplicates: Int, screenshots: Int, videos: Int, bytes: Int64) -> String {
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
    @available(iOS 26.0, *)
    private func activeSession() throws -> LanguageModelSession {
        if let existing = session { return existing }
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
