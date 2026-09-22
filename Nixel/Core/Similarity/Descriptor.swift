import Foundation
import Vision
import Accelerate
import CoreGraphics

/// Which engine produced a descriptor.
///
/// Vectors from different engines are not comparable, so the kind travels with the vector
/// everywhere — in the cache, and when grouping.
enum DescriptorKind: UInt16 {
    case vision = 1        // Vision feature print, 768 dims, neural
    case grayscale = 2     // 32x32 mean-removed grayscale, 1024 dims, pure CPU

    var dimensions: Int {
        switch self {
        case .vision: return 768
        case .grayscale: return 144
        }
    }

    /// Distances are Euclidean over unit vectors, so they live in 0...2.
    /// Both sets were measured against a fixture library with known duplicate groups
    /// rather than guessed.
    var duplicateThreshold: Float {
        switch self {
        case .vision: return 0.10
        case .grayscale: return 0.10
        }
    }

    var similarThreshold: Float {
        switch self {
        case .vision: return 0.26
        case .grayscale: return 0.425
        }
    }

    var displayName: String {
        switch self {
        case .vision: return "Neural (Vision)"
        case .grayscale: return "Compatibility"
        }
    }
}

struct Descriptor {
    let kind: DescriptorKind
    let vector: [Float]
}

/// Turns an image into a comparable vector.
///
/// Vision's feature print is the real engine: it is robust to crops, exposure changes and
/// re-encoding because it is a learned embedding. But it runs on the neural engine, which
/// **is not available in the iOS Simulator** — there it fails with "Failed to create
/// espresso context". Rather than have the app look broken during development, we fall
/// back to a mean-removed downscaled-luminance descriptor computed entirely on the CPU.
///
/// The fallback is genuinely weaker (it is sensitive to crops and rotation in a way the
/// neural embedding is not), so it is a safety net, not a peer. The app reports which
/// engine produced the results rather than pretending they are equivalent.
enum DescriptorEngine {

    /// Set once per process after the first attempt, so we don't retry a failing neural
    /// path thousands of times on a device where it will never work.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var resolvedKind: DescriptorKind?

    static var activeKind: DescriptorKind? {
        lock.lock(); defer { lock.unlock() }
        return resolvedKind
    }

    static func compute(for cgImage: CGImage) -> Descriptor? {
        lock.lock()
        let known = resolvedKind
        lock.unlock()

        // Once we know Vision works (or doesn't), stop probing.
        if known != .grayscale, let vector = visionPrint(for: cgImage) {
            if known == nil {
                lock.lock(); resolvedKind = .vision; lock.unlock()
            }
            return Descriptor(kind: .vision, vector: vector)
        }

        if known == nil {
            lock.lock(); resolvedKind = .grayscale; lock.unlock()
        }

        let vector = grayscaleDescriptor(for: cgImage)
        return vector.isEmpty ? nil : Descriptor(kind: .grayscale, vector: vector)
    }

    // MARK: Vision

    private static func visionPrint(for cgImage: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNFeaturePrintObservation else { return nil }
        return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: CPU fallback

    /// 12x12 luminance, mean-removed and L2-normalised.
    ///
    /// Removing the mean makes it ignore overall brightness (so an exposure tweak still
    /// matches), and normalising makes Euclidean distance behave like cosine distance —
    /// the same maths the Vision path uses, so downstream code needs no special case.
    ///
    /// The grid is deliberately coarse. Measured against a fixture library, a 32x32 grid
    /// put a 93% recrop at distance 0.614 — further apart than two completely different
    /// photos (0.549), so no threshold could work. Blurring the detail away by dropping to
    /// 12x12 brings the same recrop to 0.382 against an across-scene floor of 0.471, which
    /// separates. Vision needs none of this; it is robust to crops by construction.
    private static func grayscaleDescriptor(for cgImage: CGImage, side: Int = 12) -> [Float] {
        let count = side * side
        var pixels = [UInt8](repeating: 0, count: count)

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        var vector = [Float](repeating: 0, count: count)
        vDSP.convertElements(of: pixels, to: &vector)

        var mean: Float = 0
        vDSP_meanv(vector, 1, &mean, vDSP_Length(count))
        var negativeMean = -mean
        vDSP_vsadd(vector, 1, &negativeMean, &vector, 1, vDSP_Length(count))

        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(count))
        let norm = sqrt(sumSquares)
        guard norm > 1e-6 else { return [] }
        var inverse = 1 / norm
        vDSP_vsmul(vector, 1, &inverse, &vector, 1, vDSP_Length(count))

        return vector
    }
}
