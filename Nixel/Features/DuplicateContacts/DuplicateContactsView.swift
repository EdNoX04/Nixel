import SwiftUI
import Contacts

/// Duplicate contacts, grouped, with merge or delete per group.
///
/// Merging is the default action rather than deleting, because for contacts the safe
/// outcome is keeping everything: fold the details together and remove only the emptied
/// husks. Delete stays available for the cases where a record is genuinely junk.
struct DuplicateContactsView: View {
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(PermissionCenter.self) private var permissions

    @State private var working: Set<String> = []
    @State private var errorMessage: String?
    @State private var mergedCount = 0
    @State private var cleaned = 0

    var body: some View {
        Group {
            if !permissions.contacts.canScan {
                permissionPrompt
            } else if scanner.summary(.duplicateContacts).state.isScanning {
                ProgressView("Looking for duplicates…")
            } else if scanner.contactGroups.isEmpty {
                ContentUnavailableView(
                    "No duplicates",
                    systemImage: "person.2",
                    description: Text(mergedCount > 0
                        ? "You merged \(mergedCount) duplicate\(mergedCount == 1 ? "" : "s"). Nothing else looks repeated."
                        : "Nothing in your contacts looks repeated.")
                )
            } else {
                list
            }
        }
        .sensoryFeedback(.success, trigger: cleaned)
        .navigationTitle("Duplicate Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't merge", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if permissions.contacts == .notDetermined {
                let access = await permissions.requestContacts()
                if access.canScan { scanner.scanContacts(access: access) }
            } else if permissions.contacts.canScan, scanner.contactGroups.isEmpty {
                scanner.scanContacts(access: permissions.contacts)
            }
        }
    }

    // MARK: Permission

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Contacts access needed", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Nixel needs to read your contacts to find duplicates. They never leave this iPhone.")
        } actions: {
            Button(permissions.contacts == .notDetermined ? "Allow Access" : "Open Settings") {
                Task {
                    if permissions.contacts == .notDetermined {
                        let access = await permissions.requestContacts()
                        if access.canScan { scanner.scanContacts(access: access) }
                    } else {
                        permissions.openSettings()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                ForEach(scanner.contactGroups) { group in
                    ContactGroupRow(
                        group: group,
                        isWorking: working.contains(group.id),
                        onMerge: { merge(group) },
                        onDeleteExtras: { deleteExtras(group) }
                    )
                }
            } header: {
                Text("\(scanner.contactGroups.count) group\(scanner.contactGroups.count == 1 ? "" : "s") found")
                    .contentTransition(.numericText())
            } footer: {
                Text("Merging keeps every phone number, email and address from all copies, then removes the empty duplicates.")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Actions

    private func merge(_ group: ContactDuplicateGroup) {
        working.insert(group.id)
        Task {
            defer { working.remove(group.id) }
            do {
                let removed = try ContactMerger.merge(group)
                mergedCount += removed.count
                cleaned += 1
                withAnimation(.snappy(duration: 0.35)) { scanner.removeContactGroup(group.id) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteExtras(_ group: ContactDuplicateGroup) {
        working.insert(group.id)
        Task {
            defer { working.remove(group.id) }
            do {
                let removed = try ContactMerger.delete(group.others)
                mergedCount += removed.count
                cleaned += 1
                withAnimation(.snappy(duration: 0.35)) { scanner.removeContactGroup(group.id) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ContactGroupRow: View {
    let group: ContactDuplicateGroup
    let isWorking: Bool
    let onMerge: () -> Void
    let onDeleteExtras: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    Circle().fill(Theme.contacts.opacity(0.15))
                    Text(initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.contacts)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.mergedName)
                        .font(.headline)
                    Label("\(group.records.count) copies · \(group.reason.rawValue)",
                          systemImage: group.reason.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(group.records) { record in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: record.id == group.keeperID
                                  ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.caption)
                                .foregroundStyle(record.id == group.keeperID ? Theme.success : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.id == group.keeperID ? "Keeping this one" : "Will be merged in")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(record.id == group.keeperID ? Theme.success : .secondary)
                                let details = (record.phones + record.emails)
                                if details.isEmpty {
                                    Text("No phone or email").font(.caption2).foregroundStyle(.tertiary)
                                } else {
                                    Text(details.prefix(3).joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }

            HStack(spacing: Theme.Space.sm) {
                Button(action: onMerge) {
                    if isWorking {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.contacts)
                .disabled(isWorking)

                Button(role: .destructive, action: onDeleteExtras) {
                    Text("Delete extras")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 6)
    }

    private var initials: String {
        let name = group.mergedName
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
