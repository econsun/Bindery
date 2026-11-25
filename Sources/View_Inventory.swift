import AppKit
import SwiftUI

struct SnapshotInventoryView: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    let search: String
    var categoryFilter: String? = nil
    var bindingFilter: UUID? = nil
    var clearBindingFilter: (() -> Void)? = nil
    var openBinding: (UUID) -> Void = { _ in }

    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var confirmDelete = false
    @State private var deleteTargets: Set<String> = []
    @State private var renameRequest: RenameRequest?
    @State private var moveToRequest: MoveToRequest?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var lastTappedID: String?
    @State private var keyMonitor: Any?

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [SnapshotGroup] {
        let scoped = state.snapshotGroups.filter { group in
            if let bindingFilter, group.record.bindingID != bindingFilter { return false }
            guard let categoryFilter else { return true }
            return group.record.categoryPath == categoryFilter
                || group.record.categoryPath.hasPrefix(categoryFilter + "/")
        }
        guard !query.isEmpty else { return scoped }
        return scoped.filter { group in
            let record = group.record
            let fields = [
                record.renderedName,
                record.fileName,
                record.bindingName,
                record.categoryPath,
                record.sourceName,
                record.id,
                group.storeNames.joined(separator: " "),
                group.copies.map(\.absolutePath).joined(separator: " ")
            ]
            return fields.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var groups: [(day: Date, items: [SnapshotGroup])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { group in
            calendar.startOfDay(for: group.primary.record.capturedAt)
        }
        return grouped
            .map { (day: $0.key, items: $0.value.sorted { $0.primary.record.capturedAt > $1.primary.record.capturedAt }) }
            .sorted { $0.day > $1.day }
    }

    private var allSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selection.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 18) {
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            ForEach(groups, id: \.day) { group in
                                daySection(group)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        if selecting {
                            MarqueeSelectionLayer(
                                rowFrames: rowFrames,
                                selection: $selection,
                                toggle: toggleSelection
                            )
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: "snapshotList")
                .onPreferenceChange(SnapshotRowFramesKey.self) { frames in
                    if frames != rowFrames { rowFrames = frames }
                }
            }
            .scrollIndicators(.hidden)

            if selecting {
                actionBar
                    .padding(.horizontal, 30)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Delete snapshots?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { deleteTargets.removeAll() }
            Button("Delete", role: .destructive) {
                let targets = deleteTargets
                state.deleteSnapshots(targets)
                selection.subtract(targets)
                deleteTargets.removeAll()
                if selection.isEmpty { selecting = false }
            }
        } message: {
            Text("\(deleteTargets.count) snapshot\(deleteTargets.count == 1 ? "" : "s") will be moved to the macOS Trash. Offline copies are skipped.")
        }
        .sheet(item: $renameRequest) { request in
            SnapshotRenameSheet(
                targets: request.targets,
                initialFormat: request.format,
                style: appSettings.filenameStyle,
                apply: { format in
                    state.renameSnapshots(request.targets, format: format, style: appSettings.filenameStyle)
                    selection.subtract(request.targets)
                    if selection.isEmpty { selecting = false }
                    renameRequest = nil
                },
                cancel: { renameRequest = nil }
            )
            .environmentObject(state)
        }
        .sheet(item: $moveToRequest) { request in
            BindingPickerSheet(
                title: "Move to Binding",
                subtitle: "\(request.targets.count) backup\(request.targets.count == 1 ? "" : "s") will be owned by the selected binding",
                bindings: state.bindings,
                apply: { binding in
                    state.assignSnapshots(request.targets, to: binding)
                    selection.subtract(request.targets)
                    if selection.isEmpty { selecting = false }
                    moveToRequest = nil
                },
                cancel: { moveToRequest = nil }
            )
        }
        .onChange(of: bindingFilter) { _, _ in
            selection.removeAll()
            selecting = false
            installKeyMonitor()
        }
        .onChange(of: search) { _, _ in installKeyMonitor() }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    private var orderedIDs: [String] {
        groups.flatMap { group in group.items.map(\.id) }
    }

    private func handleTap(_ id: String) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        selecting = true

        if flags.contains(.shift),
           let anchor = lastTappedID,
           let start = orderedIDs.firstIndex(of: anchor),
           let end = orderedIDs.firstIndex(of: id) {
            let range = start <= end ? start...end : end...start
            selection = Set(range.map { orderedIDs[$0] })
        } else if flags.contains(.command) {
            toggleSelection(id)
            lastTappedID = id
        } else {
            selection = [id]
            lastTappedID = id
        }
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            if event.keyCode == 53, !selection.isEmpty {
                DispatchQueue.main.async {
                    selecting = false
                    selection.removeAll()
                }
                return nil
            }
            guard event.charactersIgnoringModifiers?.lowercased() == "a",
                  flags == .command else { return event }
            DispatchQueue.main.async {
                selecting = true
                selection = Set(filtered.map(\.id))
            }
            return nil
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if bindingFilter != nil {
                    Button {
                        clearBindingFilter?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("All Backups")
                                .font(.bindery(11.5, .semibold))
                        }
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                    .help("Clear the binding filter")
                }
                Text(title)
                    .font(.bindery(34, .bold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                Text(subtitle)
                    .font(.bindery(15, .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 14) {
                    legendDot(color: Color.appGreen, text: "Available")
                    legendDot(color: Color.appOrange, text: "Offline")
                    legendDot(color: Color.appRed, text: "Missing")
                }
                HStack(spacing: 8) {
                    if selecting {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            if allSelected {
                                selection.removeAll()
                            } else {
                                selection.formUnion(filtered.map(\.id))
                            }
                        }
                        .buttonStyle(InventoryTextButtonStyle())
                        Button("Done") {
                            selecting = false
                        }
                        .buttonStyle(InventoryTextButtonStyle(prominent: true))
                    } else {
                        Button {
                            selecting = true
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(InventoryTextButtonStyle())
                    }
                }
            }
            .padding(.top, 3)
        }
    }

    private var title: String {
        if let bindingFilter,
           let binding = state.bindings.first(where: { $0.id == bindingFilter }) {
            return binding.name
        }
        guard let categoryFilter else { return "All Backups" }
        return categoryFilter.split(separator: "/").last.map(String.init) ?? categoryFilter
    }

    private var subtitle: String {
        let stores = Set(filtered.flatMap(\.copies).map(\.storeID)).count
        let offline = filtered.filter { $0.availability == .offline }.count
        let copies = filtered.reduce(0) { $0 + $1.copyCount }
        let bytes = filtered.reduce(Int64(0)) { total, group in
            total + group.copies.compactMap(\.record.byteCount).reduce(0, +)
        }
        var text = "\(filtered.count) snapshot\(filtered.count == 1 ? "" : "s")"
        if bytes > 0 { text += " · \(fileSizeText(bytes))" }
        text += " · \(stores) store\(stores == 1 ? "" : "s")"
        if copies != filtered.count { text += " · \(copies) copies" }
        if offline > 0 { text += " · \(offline) offline" }
        return text
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected")
                .font(.bindery(12.5, .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .monospacedDigit()

            Divider().frame(height: 18)

            Menu {
                ForEach(state.stores) { store in
                    Button(store.name) {
                        state.moveSnapshots(selection, toStore: store)
                        selection.removeAll()
                        selecting = false
                    }
                }
            } label: {
                Label("Store", systemImage: "externaldrive")
                    .font(.bindery(12, .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(selection.isEmpty)

            Button {
                moveToRequest = MoveToRequest(targets: selection)
            } label: {
                Label("Move", systemImage: "link")
                    .font(.bindery(12, .medium))
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty || state.bindings.isEmpty)

            Button {
                requestRename(selection)
            } label: {
                Label("Rename", systemImage: "textformat")
                    .font(.bindery(12, .medium))
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)

            Button {
                state.verifySnapshots(selection)
            } label: {
                Label("Verify", systemImage: "checkmark.shield")
                    .font(.bindery(12, .medium))
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)

            Button {
                requestDelete(selection)
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.bindery(12, .medium))
                    .foregroundStyle(Color.appRed.opacity(0.86))
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)

            Spacer()

            Button("Cancel") {
                selection.removeAll()
                selecting = false
            }
            .buttonStyle(InventoryTextButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private func requestRename(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let selectedRecords = state.snapshotGroups
            .filter { ids.contains($0.id) }
            .map(\.primary.record)
        let formats = Set(
            selectedRecords
                .map { $0.format.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let idDateMismatch = selectedRecords.contains { record in
            let idDate = String(record.id.prefix(6))
            let backupDate = BackupFilenameFormat.dateText(
                record.capturedAt,
                pattern: "yyMMdd",
                fallback: "yyMMdd"
            )
            return idDate != backupDate
        }
        let format: String
        if idDateMismatch {
            // Content-dated archives keep an ID whose date is not the backup
            // date. End the name with the actual ID so the scanner cannot
            // mistake the suffix for a different snapshot.
            format = "{bindname}[_{projectDate}]_{backupDate}_{id}"
        } else {
            format = formats.count == 1
                ? (formats.first ?? appSettings.defaultFilenameFormat)
                : appSettings.defaultFilenameFormat
        }
        renameRequest = RenameRequest(targets: ids, format: format)
    }

    private func requestDelete(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deleteTargets = ids
        confirmDelete = true
    }

    private func targetIDs(for snapshot: SnapshotGroup) -> Set<String> {
        selection.contains(snapshot.id) ? selection : [snapshot.id]
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.bindery(11.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    private func daySection(_ group: (day: Date, items: [SnapshotGroup])) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(dayLabel(group.day))
                    .font(.bindery(13.5, .semibold))
                    .foregroundStyle(Color.appSecondaryText)
                Text("\(group.items.count)")
                    .font(.bindery(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.appTertiaryText)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            VStack(spacing: 2) {
                ForEach(group.items) { snapshot in
                    SnapshotInventoryRow(
                        group: snapshot,
                        selecting: selecting,
                        selected: selection.contains(snapshot.id)
                    ) {
                        handleTap(snapshot.id)
                    }
                    .contextMenu {
                        snapshotContextMenu(for: snapshot)
                    }
                    .draggable(snapshotDragPayload(for: snapshot)) {
                        SnapshotDragPreview(count: dragIDs(for: snapshot).count)
                    }
                    .background {
                        if selecting {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SnapshotRowFramesKey.self,
                                    value: [snapshot.id: proxy.frame(in: .named("snapshotList"))]
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotContextMenu(for snapshot: SnapshotGroup) -> some View {
                    if let owner = state.bindings.first(where: { $0.id == snapshot.record.bindingID }) {
                        Button {
                            openBinding(owner.id)
                        } label: {
                            Label("Open Binding", systemImage: "folder.badge.gearshape")
                        }
                        Divider()
                    }

                    Button {
                        state.reveal(snapshot.primary.absolutePath)
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                    .disabled(snapshot.availability != .available)

                    Divider()

                    Menu {
                        ForEach(state.stores) { store in
                            Button(store.name) {
                                let ids = contextIDs(for: snapshot)
                                state.moveSnapshots(ids, toStore: store)
                                if ids == selection {
                                    selection.removeAll()
                                    selecting = false
                                }
                            }
                            .disabled(!store.isOnline)
                        }
                    } label: {
                        Label("Move to Store", systemImage: "externaldrive")
                    }
                    .disabled(state.stores.isEmpty)

                    Button {
                        moveToRequest = MoveToRequest(targets: contextIDs(for: snapshot))
                    } label: {
                        Label("Move to Binding…", systemImage: "link")
                    }
                    .disabled(state.bindings.isEmpty)

                    Button {
                        requestRename(contextIDs(for: snapshot))
                    } label: {
                        Label("Rename…", systemImage: "textformat")
                    }

                    Button {
                        state.verifySnapshots(contextIDs(for: snapshot))
                    } label: {
                        Label("Verify", systemImage: "checkmark.shield")
                    }

                    Divider()

                    Button(role: .destructive) {
                        requestDelete(contextIDs(for: snapshot))
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
    }

    private func dragIDs(for snapshot: SnapshotGroup) -> Set<String> {
        selection.contains(snapshot.id) ? selection : [snapshot.id]
    }

    private func snapshotDragPayload(for snapshot: SnapshotGroup) -> String {
        "snapshots:" + dragIDs(for: snapshot).sorted().joined(separator: ",")
    }

    private func contextIDs(for snapshot: SnapshotGroup) -> Set<String> {
        if selection.contains(snapshot.id) { return selection }
        selection = [snapshot.id]
        return [snapshot.id]
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.22))
            Text(query.isEmpty ? (categoryFilter == nil ? "No backups yet" : "No backups in this category") : "No matching backups")
                .font(.bindery(16, .semibold))
                .foregroundStyle(Color.primary.opacity(0.80))
            Text(query.isEmpty
                 ? (categoryFilter == nil ? "Run a binding or drop a file onto a generator card." : "Backups for this category will appear here.")
                 : "Try a different name, category, store, or snapshot ID.")
                .font(.bindery(12.5))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct SnapshotInventoryRow: View {
    let group: SnapshotGroup
    let selecting: Bool
    let selected: Bool
    let tap: () -> Void

    @EnvironmentObject private var state: LibraryState
    @State private var hovering = false

    private var record: SnapshotRecord { group.record }
    private var owner: BackupBinding? {
        guard let bindingID = record.bindingID else { return nil }
        return state.bindings.first { $0.id == bindingID }
    }

    private var statusColor: Color {
        switch group.availability {
        case .available: return Color.appGreen
        case .offline: return Color.appOrange
        case .missing: return Color.appRed
        }
    }

    private var statusText: String {
        switch group.availability {
        case .available: return "Available"
        case .offline: return "Offline"
        case .missing: return "Missing"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.36))
                    .frame(width: 20, height: 20)
            }

            icon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(record.renderedName.isEmpty ? record.fileName : record.renderedName)
                        .font(.bindery(13.5, .semibold))
                        .foregroundStyle(Color.primary.opacity(0.90))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(record.id)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appTertiaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .help("Permanent snapshot ID")
                    if let projectText {
                        Text("Project \(projectText)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.appOrange.opacity(0.95))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.appOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .help("Project/content date from the filename, not the backup date")
                    }
                    if group.copyCount > 1 {
                        Text("\(group.copyCount) copies")
                            .font(.bindery(10, .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let owner {
                        Text(owner.name)
                        separator
                        Text(owner.category)
                    } else {
                        Text("No binding")
                    }
                    separator
                    Text(group.storeNames.joined(separator: " + "))
                    if !record.sourceName.isEmpty, record.sourceName != (owner?.name ?? record.bindingName) {
                        separator
                        Text(record.sourceName)
                    }
                }
                .font(.bindery(12))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(statusText)
                    .font(.bindery(11.5, .medium))
                    .foregroundStyle(statusColor.opacity(0.95))
            }
            .frame(width: 72, alignment: .leading)

            Text(sizeText)
                .font(.bindery(12, .medium))
                .monospacedDigit()
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 70, alignment: .trailing)

            Button {
                state.reveal(group.primary.absolutePath)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(group.availability == .available ? 0.64 : 0.26))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(group.availability != .available)
            .help(group.availability == .available ? group.primary.absolutePath : group.primary.statusText)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            Color.primary.opacity(selected ? 0.075 : (hovering ? 0.05 : 0.018)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: tap)
        .help(group.primary.absolutePath)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            Image(systemName: record.packaging.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.62))
        }
        .frame(width: 32, height: 32)
    }

    private var separator: some View {
        Circle()
            .fill(Color.primary.opacity(0.30))
            .frame(width: 2.5, height: 2.5)
    }

    private var projectText: String? {
        guard let date = record.projectDate else { return nil }
        return record.projectDateText
            ?? BackupFilenameFormat.dateText(date, pattern: "yyMMdd", fallback: "yyMMdd")
    }

    private var sizeText: String {
        guard let bytes = record.byteCount else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

private struct InventoryTextButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.58))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                prominent ? Color.accentColor : Color.primary.opacity(0.055),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}


private struct RenameRequest: Identifiable {
    let id = UUID()
    let targets: Set<String>
    let format: String
}

private struct MoveToRequest: Identifiable {
    let id = UUID()
    let targets: Set<String>
}

struct SnapshotDragPreview: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.system(size: 11, weight: .medium))
            Text(count == 1 ? "1 backup" : "\(count) backups")
                .font(.bindery(11.5, .semibold))
        }
        .foregroundStyle(Color.primary.opacity(0.86))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }
}

struct SnapshotRowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct MarqueeSelectionLayer: View {
    let rowFrames: [String: CGRect]
    @Binding var selection: Set<String>
    let toggle: (String) -> Void

    @State private var anchor: CGPoint?
    @State private var base: Set<String> = []
    @State private var current: CGPoint?

    private var rect: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let rect, rect.width > 2 || rect.height > 2 {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.10))
                    .overlay {
                        Rectangle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("snapshotList"))
                .onChanged { value in
                    if anchor == nil {
                        anchor = value.startLocation
                        base = selection
                    }
                    current = value.location
                    guard let rect, rect.width > 2 || rect.height > 2 else { return }
                    let hit = rowFrames.filter { rect.intersects($0.value) }.map(\.key)
                    let next = base.union(hit)
                    if next != selection { selection = next }
                }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    if moved < 3,
                       let id = rowFrames.first(where: { $0.value.contains(value.startLocation) })?.key {
                        toggle(id)
                    }
                    anchor = nil
                    current = nil
                    base.removeAll()
                }
        )
    }
}
