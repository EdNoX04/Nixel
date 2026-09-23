import SwiftUI

/// Palette picker.
///
/// Presented as a sheet from the dashboard so that swapping palettes can rebuild the view
/// tree underneath without throwing the user out of a navigation stack — the dashboard is
/// already the root, so the refresh is invisible.
struct AppearanceView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var theme = theme

        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: Binding(
                        get: { theme.mode },
                        set: { theme.setMode($0) }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                } header: {
                    Text("Light & Dark")
                } footer: {
                    Text("System follows your iPhone's setting. Every palette below is tuned separately for light and dark, so nothing washes out either way.")
                }

                Section {
                    ForEach(AppPalette.allCases) { palette in
                        Button {
                            theme.setPalette(palette)
                        } label: {
                            row(palette, selected: theme.palette == palette)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Palette")
                } footer: {
                    Text("Every palette ships a light and a dark rendition, so accents stay legible whichever appearance your iPhone is using.")
                }

                Section {
                    HStack(spacing: Theme.Space.lg) {
                        iconPreview(theme.matchesIcon ? theme.palette : .forest)
                        Toggle(isOn: $theme.matchesIcon) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Match palette")
                                Text("\((theme.matchesIcon ? theme.palette : .forest).title) icon")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.opacity)
                            }
                        }
                        .tint(Theme.indigo)
                    }
                    .animation(.easeInOut(duration: 0.25), value: theme.matchesIcon)
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("The Home Screen icon changes when you close this screen. iOS confirms each change with a short alert.")
                }

                Section {
                    preview
                        // Palette colours are dynamic UIColors that SwiftUI's diff treats as
                        // unchanged, so an in-place re-render leaves the old palette showing.
                        // The main tree rebuilds for this reason; the sheet sits outside that
                        // rebuild so it can stay open, which means the preview needs its own.
                        // It holds no state, so rebuilding it costs nothing.
                        .id(theme.palette)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            // Applied once, on the way out, instead of per palette tap.
            .onDisappear { theme.applyIcon() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.body.weight(.semibold))
                }
            }
        }
    }

    /// The palette's app icon, drawn with the same colours as the icon file.
    private func iconPreview(_ palette: AppPalette) -> some View {
        let colours = colorScheme == .dark ? palette.iconColours.dark : palette.iconColours.light
        return RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(colours.ground)
            .frame(width: 58, height: 58)
            .overlay {
                NotchedMark(side: 24, colour: colours.mark)
                    .offset(x: 2, y: 2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .id(palette)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func row(_ palette: AppPalette, selected: Bool) -> some View {
        HStack(spacing: Theme.Space.lg) {
            HStack(spacing: 3) {
                ForEach(Array(palette.swatches.enumerated()), id: \.offset) { _, colour in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(colour)
                        .frame(width: 15, height: 30)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(palette.title).font(.body)
                Text(palette.subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.indigo)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    /// A live miniature of the dashboard, so the choice is judged on the real thing.
    private var preview: some View {
        VStack(spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.lg) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle().trim(from: 0, to: 0.68)
                        .stroke(Theme.brandGradient,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().trim(from: 0.52, to: 0.68)
                        .stroke(Theme.success, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(CleanupCategory.allCases.prefix(4)) { category in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(category.tint.opacity(0.18))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: category.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(category.tint))
                            Text(category.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: Theme.Space.sm) {
                Text("Scan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.indigo.gradient))
                Text("Delete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.danger.gradient))
            }
        }
        .padding(.vertical, 4)
    }
}
