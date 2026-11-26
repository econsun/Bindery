import AppKit
import SwiftUI

struct FinderIntakeSheet: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let intake: FinderIntake

    @State private var mode: FinderIntakeMode
    @State private var selectedStoreID: UUID?
    @State private var selectedBindingID: UUID?
    @State private var search = ""

    init(intake: FinderIntake) {
        self.intake = intake
        _mode = State(initialValue: intake.mode)
    }

    private var bindings: [BackupBinding] {
        let sorted = state.bindings
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return sorted }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
                || (state.store(for: $0)?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedBinding: BackupBinding? {
        state.bindings.first { $0.id == selectedBindingID }
    }

    private var selectedStore: StoreRef? {
        state.stores.first { $0.id == selectedStoreID }
    }

    private var canApply: Bool {
        switch mode {
        case .unmanaged: return selectedStore?.isOnline == true
        case .binding: return selectedBinding != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fileList
                    modePicker
                    if mode == .unmanaged {
                        unmanagedOptions
                    } else {
                        bindingOptions
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 760, height: 640)
        .background(Color.appBackground)
        .onAppear {
            if selectedStoreID == nil {
                selectedStoreID = state.stores.first(where: \.isOnline)?.id ?? state.stores.first?.id
            }
            if selectedBindingID == nil {
                selectedBindingID = state.bindings.first(where: { !$0.isArchived })?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Use Bindery")
                    .font(.bindery(20, .bold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                Text("\(intake.urls.count) item\(intake.urls.count == 1 ? "" : "s") selected in Finder")
                    .font(.bindery(12.5))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer()
            Button {
                cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.50))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("FROM FINDER")
                .font(.bindery(10.5, .semibold))
                .foregroundStyle(Color.appTertiaryText)
                .tracking(0.7)
            VStack(spacing: 0) {
                ForEach(Array(intake.urls.prefix(6).enumerated()), id: \.offset) { _, url in
                    HStack(spacing: 9) {
                        Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(url.hasDirectoryPath ? Color.appOrange : Color.appSecondaryText)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.bindery(12.5, .medium))
                                .foregroundStyle(Color.primary.opacity(0.84))
                                .lineLimit(1)
                            Text(presentPath(url.path).short)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.appTertiaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    if url != intake.urls.prefix(6).last {
                        Divider().padding(.leading, 38).opacity(0.45)
                    }
                }
                if intake.urls.count > 6 {
                    Text("and \(intake.urls.count - 6) more")
                        .font(.bindery(11.5))
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                }
            }
            .background(Color.appPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(FinderIntakeMode.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { mode = item }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item == .unmanaged ? "tray" : "link")
                            .font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item == .unmanaged ? "Add to Unmanaged" : "Back Up to Binding")
                                .font(.bindery(12.5, .semibold))
                            Text(item == .unmanaged ? "Keep it loose in a store" : "Create a snapshot in a binding")
                                .font(.bindery(10.5))
                                .foregroundStyle(mode == item ? Color.white.opacity(0.72) : Color.appSecondaryText)
                        }
                    }
                    .foregroundStyle(mode == item ? Color.white : Color.primary.opacity(0.78))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(
                        mode == item ? Color.accentColor : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var unmanagedOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a store. Items are copied into its Unmanaged folder and will appear in Unmanaged after the next scan.")
                .font(.bindery(12))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if state.stores.isEmpty {
                inlineEmpty("No stores yet. Add a store before sending files to Unmanaged.")
            } else {
                VStack(spacing: 0) {
                    ForEach(state.stores) { store in
                        Button {
                            selectedStoreID = store.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "externaldrive")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.appSecondaryText)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.name)
                                        .font(.bindery(13, .medium))
                                        .foregroundStyle(Color.primary.opacity(0.88))
                                    Text(presentPath(store.path).short)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Color.appTertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if !store.isOnline {
                                    Text("Offline")
                                        .font(.bindery(10.5, .medium))
                                        .foregroundStyle(Color.appOrange)
                                }
                                Image(systemName: selectedStoreID == store.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(selectedStoreID == store.id ? Color.accentColor : Color.primary.opacity(0.22))
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isOnline)
                        if store.id != state.stores.last?.id {
                            Divider().padding(.leading, 39).opacity(0.45)
                        }
                    }
                }
                .background(Color.appPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var bindingOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the binding that should own the new snapshot\(intake.urls.count == 1 ? "" : "s"). The selected item becomes the source for this backup.")
                .font(.bindery(12))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.50))
                TextField(
                    "",
                    text: $search,
                    prompt: Text("Search bindings")
                        .font(.bindery(12.5))
                        .foregroundColor(Color.appSecondaryText)
                )
                .textFieldStyle(.plain)
                .font(.bindery(12.5))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if bindings.isEmpty {
                inlineEmpty("No matching bindings. Create a binding first, or use Add to Unmanaged.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bindings) { binding in
                            Button {
                                selectedBindingID = binding.id
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(appSettings.baseColor(for: binding.tone, scheme: .dark).opacity(0.9))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(binding.name.isEmpty ? "Untitled" : binding.name)
                                            .font(.bindery(13, .medium))
                                            .foregroundStyle(Color.primary.opacity(0.88))
                                            .lineLimit(1)
                                        Text("\(leafCategoryName(binding.category)) · \(state.store(for: binding)?.name ?? "No store")")
                                            .font(.bindery(11))
                                            .foregroundStyle(Color.appSecondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: selectedBindingID == binding.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(selectedBindingID == binding.id ? Color.accentColor : Color.primary.opacity(0.22))
                                }
                                .padding(.horizontal, 11)
                                .frame(height: 46)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if binding.id != bindings.last?.id {
                                Divider().padding(.leading, 39).opacity(0.45)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Color.appPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(mode == .unmanaged ? "Copies files; originals stay where they are." : "Uses the binding's category, store, compression, and filename rules.")
                .font(.bindery(11.5))
                .foregroundStyle(Color.appSecondaryText)
            Spacer()
            Button("Cancel") { cancel() }
                .buttonStyle(.plain)
                .font(.bindery(12.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, 12)
            Button(mode == .unmanaged ? "Add to Unmanaged" : "Back Up") {
                apply()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canApply)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private func inlineEmpty(_ text: String) -> some View {
        Text(text)
            .font(.bindery(12))
            .foregroundStyle(Color.appSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func apply() {
        switch mode {
        case .unmanaged:
            guard let selectedStoreID else { return }
            state.copyFinderItemsToUnmanaged(intake.urls, storeID: selectedStoreID)
        case .binding:
            guard let selectedBinding else { return }
            state.backupFinderItems(intake.urls, to: selectedBinding, style: appSettings.filenameStyle)
        }
        dismiss()
    }

    private func cancel() {
        state.finderIntake = nil
        dismiss()
    }
}
