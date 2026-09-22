import WidgetKit
import SwiftUI

/// Home Screen and Lock Screen widget showing device storage.
///
/// ## Why it doesn't show reclaimable space
///
/// A widget runs in its own process and can only read the host app's data through an App
/// Group container. App Groups require a paid Apple Developer membership; declaring that
/// entitlement on a free personal team breaks device signing outright. Rather than make
/// the whole app unbuildable for the sake of one number, the widget computes what it can
/// reach on its own — volume capacity, which any process can read — and taps through to
/// the app for the rest.
///
/// Wiring up the richer figures later is a small change: add the App Group, have the app
/// write a snapshot on each scan, and read it in `Provider`. The layouts already leave
/// room for it.
struct StorageEntry: TimelineEntry {
    let date: Date
    let snapshot: StorageSnapshot

    var usedFraction: Double { snapshot.usedFraction }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(date: .now, snapshot: StorageSnapshot(total: 512_000_000_000,
                                                           available: 128_000_000_000))
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(StorageEntry(date: .now, snapshot: DeviceStorage.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let entry = StorageEntry(date: .now, snapshot: DeviceStorage.snapshot())
        // Storage moves slowly; hourly is plenty and keeps the widget off the budget list.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NixelStorageWidget", provider: Provider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ContainerRelativeShape().fill(Theme.brandGradient.opacity(0.10))
                }
        }
        .configurationDisplayName("Storage")
        .description("How much room is left on your iPhone.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct StorageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StorageEntry

    var body: some View {
        switch family {
        case .systemSmall:        small
        case .systemMedium:       medium
        case .systemLarge:        large
        case .accessoryCircular:  circularAccessory
        case .accessoryRectangular: rectangularAccessory
        case .accessoryInline:    Text("\(Bytes.string(entry.snapshot.available)) free")
        default:                  small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(spacing: 6) {
            ring(lineWidth: 9)
                .frame(width: 74, height: 74)
            Text("\(Bytes.string(entry.snapshot.available)) free")
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ring(lineWidth: 11)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text("iPhone Storage")
                    .font(.caption).foregroundStyle(.secondary)
                Text(Bytes.string(entry.snapshot.available))
                    .font(.title2.weight(.bold))
                Text("free of \(Bytes.string(entry.snapshot.total))")
                    .font(.caption2).foregroundStyle(.secondary)
                usedBar
            }
            Spacer(minLength: 0)
        }
    }

    private var large: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Nixel", systemImage: "internaldrive.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.indigo)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            ring(lineWidth: 15)
                .frame(width: 150, height: 150)

            VStack(spacing: 4) {
                Text("\(Bytes.string(entry.snapshot.available)) free")
                    .font(.title3.weight(.semibold))
                Text("of \(Bytes.string(entry.snapshot.total)) · \(Int(entry.usedFraction * 100))% used")
                    .font(.caption).foregroundStyle(.secondary)
            }

            usedBar

            Text("Open Nixel to find what's worth clearing")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Lock Screen

    private var circularAccessory: some View {
        Gauge(value: entry.usedFraction) {
            Image(systemName: "internaldrive.fill")
        } currentValueLabel: {
            Text("\(Int(entry.usedFraction * 100))")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangularAccessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("iPhone Storage", systemImage: "internaldrive.fill")
                .font(.caption2)
            Text("\(Bytes.string(entry.snapshot.available)) free")
                .font(.headline)
            ProgressView(value: entry.usedFraction).tint(Theme.indigo)
        }
    }

    // MARK: Pieces

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: entry.usedFraction)
                .stroke(Theme.brandGradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if family == .systemLarge {
                VStack(spacing: 0) {
                    Text("\(Int(entry.usedFraction * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("used").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usedBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Theme.brandGradient)
                    .frame(width: proxy.size.width * entry.usedFraction)
            }
        }
        .frame(height: 6)
    }
}
