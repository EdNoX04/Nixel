import SwiftUI

/// Attaches a drag gesture only to the top card. A `condition ? gesture : nil` ternary
/// type-checks but does not reliably attach, so the branch is made explicit here.
private struct SwipeGestureModifier<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(gesture)
        } else {
            content
        }
    }
}

/// One-at-a-time triage: swipe right to keep, left to mark for removal.
///
/// The grid is better for bulk work; this is better for the photos you actually have to
/// look at. Nothing here deletes — a left swipe adds to the same selection the review
/// screen shows, so the safety model is unchanged and a mistake costs one tap to undo.
struct SwipeReviewView: View {
    let category: CleanupCategory
    let assets: [PhotoAsset]

    @Environment(CleanupSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var decisions: [(asset: PhotoAsset, kept: Bool)] = []
    /// Whether the current drag has gone far enough to count — flips once each way, which
    /// is what the haptic keys off.
    @State private var armed = false
    /// True while a card is flying off. Taps in that window used to decide the same photo
    /// twice and skip the next one.
    @State private var deciding = false

    private var remaining: [PhotoAsset] { Array(assets.dropFirst(index)) }
    private var current: PhotoAsset? { remaining.first }

    /// How far a card must travel before the swipe counts.
    private let commitDistance: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ZStack {
                if remaining.isEmpty {
                    finishedState
                } else {
                    // Draw a couple of cards behind the top one for depth.
                    ForEach(Array(remaining.prefix(3).enumerated()).reversed(), id: \.element.id) { offset, asset in
                        card(asset, depth: offset)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if !remaining.isEmpty { controls }
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, isArmed in isArmed }
        .sensoryFeedback(.selection, trigger: decisions.count)
        .navigationTitle("Quick Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Header

    private var progressHeader: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                Label("\(decisions.filter(\.kept).count) kept", systemImage: "heart.fill")
                    .foregroundStyle(Theme.success)
                Spacer()
                Text("\(min(index + 1, assets.count)) of \(assets.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(decisions.filter { !$0.kept }.count) to remove", systemImage: "trash.fill")
                    .foregroundStyle(Theme.danger)
            }
            .font(.caption.weight(.medium))

            ProgressView(value: Double(index), total: Double(max(assets.count, 1)))
                .tint(Theme.indigo)
                .animation(.easeOut(duration: 0.25), value: index)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }

    // MARK: Card

    private func card(_ asset: PhotoAsset, depth: Int) -> some View {
        let isTop = depth == 0
        let progress = min(1, abs(drag.width) / commitDistance)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return GeometryReader { proxy in
            ZStack {
                AssetThumbnailView(asset: asset, side: proxy.size.width,
                                   isSelected: false, showsChrome: false) { }
                    .allowsHitTesting(false)

                // Verdict stamps fade in as the card travels.
                if isTop {
                    stamp("KEEP", colour: Theme.success, alignment: .topLeading,
                          rotation: -14, opacity: drag.width > 0 ? progress : 0)
                    stamp("REMOVE", colour: Theme.danger, alignment: .topTrailing,
                          rotation: 14, opacity: drag.width < 0 ? progress : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .overlay(alignment: .bottom) { if isTop { sizeBadge(asset) } }
            .clipShape(shape)
            // The thumbnail disables hit testing so it cannot swallow the drag, which
            // leaves the stack with no hittable area of its own. This gives it one.
            .contentShape(shape)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .scaleEffect(1 - CGFloat(depth) * 0.04)
            .offset(y: CGFloat(depth) * 10)
            // The top card follows the finger exactly — no implicit animation on the drag,
            // which made it trail behind like it was on a spring. Releases and decisions
            // animate explicitly instead.
            .offset(x: isTop ? drag.width : 0, y: isTop ? drag.height * 0.25 : 0)
            .rotationEffect(.degrees(isTop && !reduceMotion ? Double(drag.width / 18) : 0),
                            anchor: .bottom)
            .modifier(SwipeGestureModifier(enabled: isTop, gesture: swipeGesture(asset)))
            // Swiping has a non-gesture path for VoiceOver: the card offers Keep and Remove.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Item \(index + 1) of \(assets.count), \(Bytes.string(asset.bytes))")
            .accessibilityHidden(!isTop)
            .accessibilityAction(named: "Keep") { decide(asset, keep: true) }
            .accessibilityAction(named: "Remove") { decide(asset, keep: false) }
        }
        .padding(.horizontal, Theme.Space.xl)
    }

    private func stamp(_ text: String, colour: Color, alignment: Alignment,
                       rotation: Double, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(colour)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colour, lineWidth: 4))
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func sizeBadge(_ asset: PhotoAsset) -> some View {
        Text(Bytes.string(asset.bytes))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(.bottom, 14)
    }

    private func swipeGesture(_ asset: PhotoAsset) -> some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
                armed = abs(value.translation.width) > commitDistance
            }
            .onEnded { value in
                // A quick flick counts even if it didn't travel far.
                let projected = value.predictedEndTranslation.width
                if abs(value.translation.width) > commitDistance || abs(projected) > commitDistance * 2.5 {
                    decide(asset, keep: (abs(value.translation.width) > commitDistance
                                         ? value.translation.width : projected) > 0)
                } else {
                    // Settles back without the overshoot when Reduce Motion is on.
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                                               : .spring(response: 0.35, dampingFraction: 0.72)) {
                        drag = .zero
                    }
                }
                armed = false
            }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: Theme.Space.xl) {
            circleButton("xmark", tint: Theme.danger) {
                if let current { decide(current, keep: false) }
            }
            .accessibilityLabel("Remove")
            circleButton("arrow.uturn.backward", tint: .secondary, small: true) { undo() }
                .disabled(decisions.isEmpty)
                .opacity(decisions.isEmpty ? 0.35 : 1)
                .accessibilityLabel("Undo")
            circleButton("heart.fill", tint: Theme.success) {
                if let current { decide(current, keep: true) }
            }
            .accessibilityLabel("Keep")
        }
        .padding(.vertical, Theme.Space.xl)
    }

    private func circleButton(_ icon: String, tint: Color, small: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: small ? 18 : 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: small ? 48 : 66, height: small ? 48 : 66)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Decisions

    private func decide(_ asset: PhotoAsset, keep: Bool) {
        guard !deciding else { return }
        if reduceMotion {
            // No fling: record the decision and cross-fade to the next card.
            if keep { selection.deselect([asset], in: category) }
            else { selection.select([asset], in: category) }
            decisions.append((asset, keep))
            drag = .zero
            withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
            return
        }
        deciding = true
        // Fling the card off-screen before advancing, so the motion reads as a decision.
        withAnimation(.easeIn(duration: 0.2)) {
            drag = CGSize(width: keep ? 700 : -700, height: drag.height)
        }

        if keep {
            selection.deselect([asset], in: category)
        } else {
            selection.select([asset], in: category)
        }
        decisions.append((asset, keep))

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            drag = .zero
            // The cards behind move up into place.
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { index += 1 }
            deciding = false
        }
    }

    private func undo() {
        guard !deciding, let last = decisions.popLast() else { return }
        selection.deselect([last.asset], in: category)
        if reduceMotion {
            drag = .zero
            withAnimation(.easeInOut(duration: 0.2)) { index = max(0, index - 1) }
            return
        }
        // Bring the card back in from the side it left by. The off-screen position has to
        // render for a frame first; set and animated back in one update, the two changes
        // cancel out and the card just pops in.
        drag = CGSize(width: last.kept ? 700 : -700, height: 0)
        index = max(0, index - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { drag = .zero }
        }
    }

    // MARK: Finished

    private var finishedState: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.success)
            Text("All reviewed")
                .font(.title3.weight(.semibold))
            let marked = decisions.filter { !$0.kept }
            Text(marked.isEmpty
                 ? "You kept everything."
                 : "\(marked.count) marked · \(Bytes.string(marked.reduce(0) { $0 + $1.asset.bytes })) to free")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.top, Theme.Space.sm)
        }
    }
}
