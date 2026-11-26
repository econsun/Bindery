import SwiftUI

/// Searchable command-style picker used by "Move to…" actions. Typing filters
/// by binding name or category; choosing a row immediately reassigns the
/// snapshots and dismisses.
struct BindingPickerSheet: View {
    let title: String
    let subtitle: String
    let bindings: [BackupBinding]
    let apply: (BackupBinding) -> Void
    let cancel: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [BackupBinding] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = term.isEmpty ? bindings : bindings.filter {
            [$0.name, $0.category, $0.kind.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
        return list.sorted { lhs, rhs in
            let category = lhs.category.localizedStandardCompare(rhs.category)
            if category != .orderedSame { return category == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bindery(20, .bold))
                        .foregroundStyle(Color.primary.opacity(0.94))
                    Text(subtitle)
                        .font(.bindery(12.5))
                        .foregroundStyle(Color.primary.opacity(0.42))
                }
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.34))
                TextField("Search bindings by name or category", text: $query)
                    .font(.bindery(13))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand { cancel() }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.28))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.24))
                    Text(bindings.isEmpty ? "No bindings yet" : "No matching bindings")
                        .font(.bindery(13, .semibold))
                        .foregroundStyle(Color.primary.opacity(0.62))
                    Text(bindings.isEmpty ? "Create a binding first, then come back and move these backups." : "Try a different name or category.")
                        .font(.bindery(11.5))
                        .foregroundStyle(Color.primary.opacity(0.36))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filtered) { binding in
                            Button {
                                apply(binding)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: binding.kind.icon)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.accentColor.opacity(0.78))
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(binding.name.isEmpty ? "Untitled" : binding.name)
                                            .font(.bindery(13, .semibold))
                                            .foregroundStyle(Color.primary.opacity(0.90))
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(leafCategoryName(binding.category))
                                            separator
                                            Text("\(binding.backupRecords.count) backup\(binding.backupRecords.count == 1 ? "" : "s")")
                                            if binding.isArchived {
                                                separator
                                                Text("Archived")
                                            }
                                        }
                                        .font(.bindery(10.5))
                                        .foregroundStyle(Color.primary.opacity(0.38))
                                        .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.24))
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 50)
                                .contentShape(Rectangle())
                                .background(Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .scrollIndicators(.visible)
            }

            HStack {
                Text("\(filtered.count) binding\(filtered.count == 1 ? "" : "s")")
                    .font(.bindery(10.5, .medium))
                    .foregroundStyle(Color.primary.opacity(0.32))
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(BindingPickerSecondaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Color.appPanel)
        .onAppear { searchFocused = true }
    }

    private var separator: some View {
        Circle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 2.5, height: 2.5)
    }
}

private struct BindingPickerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(12, .semibold))
            .foregroundStyle(Color.primary.opacity(0.62))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
