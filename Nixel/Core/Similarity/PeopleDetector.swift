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

    /// Whether this device should be able to detect people at all. The Simulator can't;
    /// a real iPhone can. Where it can, a photo whose count is unknown is treated as
    /// possibly having someone in it — the brake fails closed, never open.
    static var isExpected: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Stored in the cache for "detection failed": retried on the next scan.
    static let unknown = -1

    /// Number of people visible, or `unknown` if detection failed. 0 means none were
    /// found, not that none are there.
    static func count(in cgImage: CGImage) -> Int {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([faceRequest])
        } catch {
            if !isExpected { markUnavailable() }
            return isExpected ? unknown : 0
        }

        let faces = faceRequest.results?.count ?? 0
        if faces > 0 { return faces }

        // No face — try for a body. Catches people turned away or far from the camera.
        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false
        do {
            try handler.perform([bodyRequest])
        } catch {
            if !isExpected { markUnavailable() }
            return isExpected ? unknown : 0
        }
        return bodyRequest.results?.count ?? 0
    }
}

extension PhotoAsset {
    var hasPeople: Bool { (peopleCount ?? 0) > 0 }

    /// Whether a bulk action should leave this photo alone: it has people in it, or on a
    /// device that can detect people we don't know yet. Videos aren't checked.
    var mightHavePeople: Bool {
        if hasPeople { return true }
        return PeopleDetector.isExpected && !isVideo && peopleCount == nil
    }

    var peopleLabel: String? {
        guard let count = peopleCount, count > 0 else { return nil }
        return count == 1 ? "1 person" : "\(count) people"
    }
}
