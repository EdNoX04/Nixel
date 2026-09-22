import Foundation
import Vision
import CoreGraphics

/// Counts the people in an image, on device.
///
/// ## Why a cleaner cares
///
/// Every other signal in this app is about whether a photo is *redundant*. This one is
/// about whether it is *replaceable*, which is a different question. A duplicate landscape
/// is genuinely disposable; a duplicate of the only photo of someone is not, and no amount
/// of perceptual similarity tells you the difference.
///
/// So faces act as a brake rather than a category: photos containing people are excluded
/// from bulk "select all" actions and marked, and within a group the shot with more faces
/// wins the keeper slot. The user can still select them one at a time — the point is that
/// a fast tap never sweeps a person's photo into a delete list by accident.
///
/// Face rectangles are cheap and run on the same thumbnail everything else uses. Body
/// detection is a second pass, only when no face was found, for the back-of-head and
/// figure-in-the-distance cases a face detector misses.
enum PeopleDetector {

    /// Whether face detection actually ran, as opposed to returning nothing.
    ///
    /// Vision's detectors are neural and do not run in the iOS Simulator — they fail with
    /// "Failed to create espresso context", exactly as the feature-print model does. A
    /// silent 0 would be indistinguishable from "no people in this library", and the app
    /// would go on implying it was protecting photos of people when it was not. So the
    /// first failure is recorded and surfaced rather than swallowed.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var failed = false

    static var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return !failed
    }

    private static func markUnavailable() {
        lock.lock(); failed = true; lock.unlock()
    }

    /// Number of people visible. 0 means none were found, not that none are there.
    static func count(in cgImage: CGImage) -> Int {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([faceRequest])
        } catch {
            markUnavailable()
            return 0
        }

        let faces = faceRequest.results?.count ?? 0
        if faces > 0 { return faces }

        // No face — try for a body. Catches people turned away or far from the camera.
        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false
        do {
            try handler.perform([bodyRequest])
        } catch {
            markUnavailable()
            return 0
        }
        return bodyRequest.results?.count ?? 0
    }
}

extension PhotoAsset {
    var hasPeople: Bool { (peopleCount ?? 0) > 0 }

    var peopleLabel: String? {
        guard let count = peopleCount, count > 0 else { return nil }
        return count == 1 ? "1 person" : "\(count) people"
    }
}
