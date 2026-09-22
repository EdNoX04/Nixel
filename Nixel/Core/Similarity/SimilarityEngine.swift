import Foundation
import Vision
import Accelerate
import UIKit
import Photos

/// A set of photos the engine believes are the same shot.
struct PhotoGroup: Identifiable, Hashable {
    let id: String
    var assets: [PhotoAsset]
    /// The one we suggest keeping. Never deleted by a "select all" action.
    var bestID: String

    var best: PhotoAsset? { assets.first { $0.id == bestID } }
    var others: [PhotoAsset] { assets.filter { $0.id != bestID } }

    /// Space freed if the user keeps only the best shot.
    var reclaimableBytes: Int64 { others.reduce(0) { $0 + $1.bytes } }

    static func == (a: PhotoGroup, b: PhotoGroup) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Groups near-identical photos using Vision feature prints.
///
/// Measured facts this design rests on (benchmarked against the iOS 27 SDK before building):
///
///  * A feature print is 768 `Float32`s and is already L2-normalised.
///  * `VNFeaturePrintObservation.computeDistance` is *exactly* Euclidean distance over
///    those floats — so we can skip Vision entirely when comparing and use `vDSP`, which
///    measured ~8.8M comparisons/sec. Vision runs once per new photo and never again.
///  * Generating a print costs ~1000x more than comparing two, so the cache
///    (`FeaturePrintStore`) is where scan speed actually comes from.
actor SimilarityEngine {

    /// Photos taken around the same moment are overwhelmingly where near-duplicates live,
    /// so we compare each photo against its neighbours in time rather than against all
    /// N photos. This turns an O(N^2) scan into O(N*W) and is what keeps a 20k-photo
    /// library fast. True re-saves that sit far apart in time are caught separately by
    /// the dimension-bucket pass below.
    private let timeWindow = 240

    private let store = FeaturePrintStore()

    // MARK: - Public API

    /// Ensures a feature print exists for every asset, reporting progress 0...1.
    ///
    /// Decoding a thumbnail is I/O bound and generating a print is compute bound, so the
    /// two overlap well — we keep a fixed number of assets in flight rather than walking
    /// the library one at a time. The cap is deliberate: an unbounded task group on a
    /// 20,000 photo library would try to decode 20,000 images at once.
    func prepare(_ assets: [PhotoAsset], progress: @Sendable @escaping (Double) -> Void) async {
        let missing = assets.filter { store.record(for: $0.id, modified: $0.phAsset.modificationDate) == nil }

        trace("prepare: \(assets.count) assets, \(missing.count) need analysis")
        guard !missing.isEmpty else {
            progress(1)
            return
        }

        // Warm the models once, serially, instead of cold-loading them in parallel.
        await VisionWork.warmUp()

        // Image loading is I/O and suspends properly, so it can run wider than the Vision
        // queue behind it; the queue caps the neural work at two regardless.
        let concurrency = 6
        var done = 0

        await withTaskGroup(of: (String, Date?, Descriptor?, Double, Int).self) { group in
            var next = 0

            func schedule() {
                guard next < missing.count else { return }
                let asset = missing[next]
                next += 1
                group.addTask {
                    // An unreadable asset (iCloud-only original, corrupt file) yields nil,
                    // which we still cache so it is not retried on every scan.
                    let (descriptor, sharpness, people) = await Self.analyse(asset.phAsset)
                    return (asset.id, asset.phAsset.modificationDate, descriptor, sharpness, people)
                }
            }

            for _ in 0..<concurrency { schedule() }

            while let (id, modified, descriptor, sharpness, people) = await group.next() {
                store.store(descriptor, sharpness: sharpness, people: people,
                            for: id, modified: modified)
                done += 1
                // Fine-grained: on a large library a 20-photo step left the ring frozen
                // long enough to look hung.
                if done % 4 == 0 || done == missing.count {
                    progress(Double(done) / Double(missing.count))
                }
                // Save as we go. The cache used to be written only once the whole pass
                // finished, so backgrounding the app partway through a big library threw
                // every analysed photo away.
                if done % 150 == 0 { store.save() }
                if done == 1 || done % 25 == 0 { trace("prepare: \(done)/\(missing.count) engine=\(descriptor?.kind.rawValue ?? 0)") }
                if Task.isCancelled { break }
                schedule()
            }
        }

        store.prune(keeping: Set(assets.map(\.id)))
        store.save()
    }

    /// Cached sharpness per asset id, for blur detection and best-of-group ranking.
    func sharpnessScores(for assets: [PhotoAsset]) -> [String: Double] {
        var scores: [String: Double] = [:]
        for asset in assets {
            guard let record = store.record(for: asset.id, modified: asset.phAsset.modificationDate)
            else { continue }
            scores[asset.id] = record.sharpness
        }
        return scores
    }

    /// People counts per asset id, for the bulk-selection brake and the badge.
    func peopleCounts(for assets: [PhotoAsset]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for asset in assets {
            guard let record = store.record(for: asset.id, modified: asset.phAsset.modificationDate)
            else { continue }
            counts[asset.id] = record.people
        }
        return counts
    }

    /// Groups prepared assets into sets of near-identical photos.
    ///
    /// ## Why this is not union-find any more
    ///
    /// The first implementation linked any pair under the threshold and let union-find
    /// merge the components. On a small fixture set that was fine. On a 266-photo library
    /// it produced a single 23-member "group" containing hay bales, a shoreline and a
    /// forest: transitivity means one bad link welds two unrelated groups together, and a
    /// chain of near-misses drags in everything along the way.
    ///
    /// This uses leader clustering instead. Every photo is compared against a cluster's
    /// *anchor*, never against an arbitrary member, so membership cannot chain: to join a
    /// group a photo must resemble the one shot that defines it. A false link can add one
    /// wrong photo; it can no longer merge two groups.
    func group(_ assets: [PhotoAsset], threshold: Float? = nil) -> [PhotoGroup] {
        // Only compare vectors produced by the same engine — a Vision print and a
        // grayscale descriptor live in different spaces and distances between them
        // are meaningless.
        var usable: [PhotoAsset] = []
        var vectors: [[Float]] = []
        var kind: DescriptorKind?

        for asset in assets {
            guard let record = store.record(for: asset.id, modified: asset.phAsset.modificationDate),
                  !record.vector.isEmpty,
                  record.vector.count == record.kind.dimensions else { continue }
            if kind == nil { kind = record.kind }
            guard record.kind == kind else { continue }
            var enriched = asset
            enriched.sharpness = record.sharpness
            enriched.peopleCount = record.people
            usable.append(enriched)
            vectors.append(record.vector)
        }

        guard let kind, usable.count > 1 else { return [] }
        let dimensions = vDSP_Length(kind.dimensions)
        let stride = kind.dimensions
        let similarThreshold = threshold ?? kind.similarThreshold
        let squaredThreshold = similarThreshold * similarThreshold
        let duplicateSquared = kind.duplicateThreshold * kind.duplicateThreshold

        // Time order: near-duplicates overwhelmingly sit next to each other in time.
        let order = usable.indices.sorted {
            let l = usable[$0].creationDate ?? .distantPast
            let r = usable[$1].creationDate ?? .distantPast
            return l == r ? usable[$0].id < usable[$1].id : l < r
        }

        var flat = [Float](); flat.reserveCapacity(order.count * stride)
        for index in order { flat.append(contentsOf: vectors[index]) }

        /// position -> cluster id; clusters keyed by their anchor position.
        var clusterOf = [Int](repeating: -1, count: order.count)
        var anchors: [Int] = []                 // positions that define a cluster
        var members: [Int: [Int]] = [:]         // anchor position -> member positions

        flat.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!

            func distanceSquared(_ a: Int, _ b: Int) -> Float {
                var value: Float = 0
                vDSP_distancesq(base + a * stride, 1, base + b * stride, 1, &value, dimensions)
                return value
            }

            for position in 0..<order.count {
                var bestAnchor = -1
                var bestDistance = Float.greatestFiniteMagnitude

                // Only anchors still inside the time window are candidates.
                for anchor in anchors.reversed() {
                    guard position - anchor <= timeWindow else { break }
                    let d = distanceSquared(anchor, position)
                    if d <= squaredThreshold && d < bestDistance {
                        bestDistance = d
                        bestAnchor = anchor
                    }
                }

                if bestAnchor >= 0 {
                    clusterOf[position] = bestAnchor
                    members[bestAnchor, default: [bestAnchor]].append(position)
                } else {
                    clusterOf[position] = position
                    anchors.append(position)
                    members[position] = [position]
                }
            }

            // Second pass — exact re-saves that fell outside the time window.
            // A true re-save keeps its pixel dimensions, so bucket on those and compare
            // against anchors only, at the much tighter duplicate threshold.
            var buckets: [Int: [Int]] = [:]
            for position in 0..<order.count {
                let asset = usable[order[position]]
                buckets[asset.pixelWidth << 16 ^ asset.pixelHeight, default: []].append(position)
            }
            for (_, positions) in buckets where positions.count > 1 && positions.count <= 2_000 {
                for position in positions where members[position] == nil || members[position]!.count == 1 {
                    for anchor in positions where anchor != position && members[anchor] != nil {
                        guard clusterOf[position] != anchor else { continue }
                        if distanceSquared(anchor, position) <= duplicateSquared {
                            // Move it out of its singleton cluster into the anchor's.
                            let old = clusterOf[position]
                            if old == position { members.removeValue(forKey: position)
                                                 anchors.removeAll { $0 == position } }
                            else { members[old]?.removeAll { $0 == position } }
                            clusterOf[position] = anchor
                            members[anchor]?.append(position)
                            break
                        }
                    }
                }
            }
        }

        var groups: [PhotoGroup] = []
        for (_, positions) in members where positions.count > 1 {
            let unique = Array(Set(positions)).sorted()
            let people = unique.map { usable[order[$0]] }
            guard people.count > 1 else { continue }
            let best = Self.pickBest(from: people)
            let id = people.map(\.id).sorted().first ?? UUID().uuidString
            groups.append(PhotoGroup(id: id,
                                     assets: Self.sortForDisplay(people, bestID: best),
                                     bestID: best))
        }

        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    // MARK: - Best-of-group

    /// Which photo in a group is worth keeping.
    ///
    /// Ordering is deliberate: a favourite is a human judgement and outranks everything;
    /// then measured sharpness, because the usual reason for three near-identical shots is
    /// that two came out soft; then resolution and file size as proxies for "the original
    /// rather than a compressed copy"; then the newest.
    static func pickBest(from assets: [PhotoAsset]) -> String {
        let best = assets.max { a, b in
            if a.isFavorite != b.isFavorite { return !a.isFavorite && b.isFavorite }
            // A shot with more people in it is the one worth keeping, ahead of any
            // measure of technical quality.
            let pa = a.peopleCount ?? 0, pb = b.peopleCount ?? 0
            if pa != pb { return pa < pb }
            if let sa = a.sharpness, let sb = b.sharpness, abs(sa - sb) > 0.05 { return sa < sb }
            if a.pixels != b.pixels { return a.pixels < b.pixels }
            if a.bytes != b.bytes { return a.bytes < b.bytes }
            return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
        return best?.id ?? assets[0].id
    }

    private static func sortForDisplay(_ assets: [PhotoAsset], bestID: String) -> [PhotoAsset] {
        assets.sorted { a, b in
            if a.id == bestID { return true }
            if b.id == bestID { return false }
            return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
    }

    // MARK: - Descriptors

    /// Loads the small analysis image for an asset.
    ///
    /// `isSynchronous = true` combined with `.fastFormat` makes Photos return nil for
    /// every asset — the options contradict each other. `.highQualityFormat` delivers
    /// exactly one callback, so a continuation is correct and safe from double-resume.
    /// Loads a downscaled image for analysis.
    ///
    /// `contentMode` matters more than it looks. `.aspectFill` crops to a centred square,
    /// which is what perceptual hashing wants — every image framed identically. It is
    /// exactly wrong for OCR: a 1290x2796 screenshot squeezed into a 640 square loses most
    /// of its text off the top and bottom, and the model then sees a fragment. Text reading
    /// passes `.aspectFit` so the whole screen survives.
    nonisolated static func analysisImage(
        for asset: PHAsset,
        side: CGFloat = 224,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false     // never pull originals from iCloud mid-scan
        options.isSynchronous = false

        // aspectFit needs a box big enough for the long edge to stay legible.
        let target = contentMode == .aspectFit
            ? CGSize(width: side, height: side * 3)
            : CGSize(width: side, height: side)

        return await withCheckedContinuation { continuation in
            // Photos normally answers every request, but a single asset that never calls
            // back would otherwise hold its slot in the task group forever and freeze the
            // scan at whatever percentage it had reached. A deadline guarantees progress;
            // the gate guarantees the continuation resumes exactly once.
            let gate = ResumeOnce(continuation)
            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                gate.resume(with: image?.cgImage)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6) {
                if gate.resume(with: nil) {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
            }
        }
    }

    /// One decode, two measurements. Loading the thumbnail is the expensive part, so
    /// sharpness is computed from the same image rather than fetching it twice.
    nonisolated static func analyse(_ asset: PHAsset) async -> (Descriptor?, Double, Int) {
        guard let cgImage = await analysisImage(for: asset) else { return (nil, 0, 0) }
        // Suspends while Vision runs on its own queue; never blocks a cooperative thread.
        return await VisionWork.run {
            let descriptor = DescriptorEngine.compute(for: cgImage)
            let sharpness = Sharpness.measure(cgImage) ?? 0
            let people = PeopleDetector.count(in: cgImage)
            return (descriptor, sharpness, people)
        }
    }
}


/// Resumes a continuation at most once, whichever caller gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage?, Never>?

    init(_ continuation: CheckedContinuation<CGImage?, Never>) {
        self.continuation = continuation
    }

    /// Returns true if this call was the one that resumed.
    @discardableResult
    func resume(with value: CGImage?) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return false }
        pending.resume(returning: value)
        return true
    }
}
