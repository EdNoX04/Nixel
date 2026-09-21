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
            return nil
        }
        #else
        return nil
        #endif
    }

    /// One plain sentence describing what a scan turned up, for the daily notification.
    func summarise(duplicates: Int, screenshots: Int, videos: Int, bytes: Int64) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return nil }
        let prompt = """
        Write one short, friendly sentence (max 18 words) telling someone what a phone \
        storage scan found. Do not invent numbers. Findings: \(duplicates) duplicate photos, \
        \(screenshots) screenshots, \(videos) large videos, \(Bytes.string(bytes)) recoverable.
        """
        do {
            let session = try activeSession()
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
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
