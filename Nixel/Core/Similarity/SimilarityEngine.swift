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

        guard !missing.isEmpty else {
            progress(1)
            return
        }

        let concurrency = min(6, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
        var done = 0

        await withTaskGroup(of: (String, Date?, Descriptor?).self) { group in
            var next = 0

            func schedule() {
                guard next < missing.count else { return }
                let asset = missing[next]
                next += 1
                group.addTask {
                    // An unreadable asset (iCloud-only original, corrupt file) yields nil,
                    // which we still cache so it is not retried on every scan.
                    let descriptor = await Self.descriptor(for: asset.phAsset)
                    return (asset.id, asset.phAsset.modificationDate, descriptor)
                }
            }

            for _ in 0..<concurrency { schedule() }

            while let (id, modified, descriptor) = await group.next() {
                store.store(descriptor, for: id, modified: modified)
                done += 1
                if done % 20 == 0 || done == missing.count {
                    progress(Double(done) / Double(missing.count))
                }
                if Task.isCancelled { break }
                schedule()
            }
        }

        store.prune(keeping: Set(assets.map(\.id)))
        store.save()
    }

    /// Groups prepared assets into sets of near-identical photos.
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
            usable.append(asset)
            vectors.append(record.vector)
        }

        guard let kind, usable.count > 1 else { return [] }
        let dimensions = vDSP_Length(kind.dimensions)
        let stride = kind.dimensions
        let similarThreshold = threshold ?? kind.similarThreshold

        let order = usable.indices.sorted {
            let l = usable[$0].creationDate ?? .distantPast
            let r = usable[$1].creationDate ?? .distantPast
            return l == r ? usable[$0].id < usable[$1].id : l < r
        }

        var flat = [Float](); flat.reserveCapacity(order.count * stride)
        for index in order { flat.append(contentsOf: vectors[index]) }

        var union = UnionFind(count: order.count)

        // Pass 1 — sliding window over time. Catches bursts, retakes and edits.
        let squaredThreshold = similarThreshold * similarThreshold
        flat.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for i in 0..<order.count {
                let limit = min(i + timeWindow, order.count - 1)
                guard limit > i else { continue }
                for j in (i + 1)...limit {
                    var squared: Float = 0
                    vDSP_distancesq(base + i * stride, 1, base + j * stride, 1, &squared, dimensions)
                    if squared <= squaredThreshold { union.union(i, j) }
                }
            }
        }

        // Pass 2 — exact re-saves regardless of when they happened. A true re-save keeps
        // its pixel dimensions, so bucketing by dimensions is a cheap way to catch the
        // same picture downloaded twice months apart, which the time window would miss.
        var buckets: [Int: [Int]] = [:]
        for (position, index) in order.enumerated() {
            let asset = usable[index]
            buckets[asset.pixelWidth << 16 ^ asset.pixelHeight, default: []].append(position)
        }
        let duplicateSquared = kind.duplicateThreshold * kind.duplicateThreshold
        flat.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for (_, positions) in buckets where positions.count > 1 && positions.count <= 2_000 {
                for a in 0..<positions.count {
                    for b in (a + 1)..<positions.count {
                        let i = positions[a], j = positions[b]
                        if union.find(i) == union.find(j) { continue }
                        var squared: Float = 0
                        vDSP_distancesq(base + i * stride, 1, base + j * stride, 1, &squared, dimensions)
                        if squared <= duplicateSquared { union.union(i, j) }
                    }
                }
            }
        }

        var components: [Int: [Int]] = [:]
        for position in 0..<order.count {
            components[union.find(position), default: []].append(position)
        }

        var groups: [PhotoGroup] = []
        for (_, positions) in components where positions.count > 1 {
            let members = positions.map { usable[order[$0]] }
            let best = Self.pickBest(from: members)
            let id = members.map(\.id).sorted().first ?? UUID().uuidString
            groups.append(PhotoGroup(id: id, assets: Self.sortForDisplay(members, bestID: best), bestID: best))
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
    nonisolated static func analysisImage(for asset: PHAsset, side: CGFloat = 224) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false     // never pull originals from iCloud mid-scan
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    nonisolated static func descriptor(for asset: PHAsset) async -> Descriptor? {
        guard let cgImage = await analysisImage(for: asset) else { return nil }
        return DescriptorEngine.compute(for: cgImage)
    }
}

/// Classic disjoint-set with path compression — turns "these two photos match" pairs into
/// groups without ever materialising an N x N matrix.
private struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var current = x
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        if rank[ra] < rank[rb] { parent[ra] = rb }
        else if rank[ra] > rank[rb] { parent[rb] = ra }
        else { parent[rb] = ra; rank[ra] += 1 }
    }
}
