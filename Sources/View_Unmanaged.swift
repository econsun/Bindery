import AppKit
import SwiftUI

struct UnmanagedView: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    let search: String

    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var lastTappedID: String?
    @State private var keyMonitor: Any?
    @State private var pickerRequest: UnmanagedMoveRequest?
    @State private var renameRequest: UnmanagedRenameRequest?
    @State private var confirmDelete = false
    @State private var deleteTargets: Set<String> = []

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var items: [UnmanagedItem] {
        guard !query.isEmpty else { return state.unmanagedItems }
        return state.unmanagedItems.filter {
            [$0.name, $0.relativePath, $0.storeName, $0.categoryPath]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var unboundGroups: [SnapshotGroup] {
        let groups = state.unboundSnapshotGroups
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            let record = group.record
            let fields = [
                record.renderedName,
                record.fileName,
                record.bindingName,
                record.id,
                record.sourceName,
                group.storeNames.joined(separator: " "),
                group.copies.map(\.absolutePath).joined(separator: " ")
            ]
            return fields.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var totalCount: Int { items.count + unboundGroups.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if totalCount == 0 {
                        emptyState
                    } else {
                        if !unboundGroups.isEmpty {
                            sectionHeader("Backups Without a Binding", count: unboundGroups.count)
                            ViewThatFits(in: .horizontal) {
                                SnapshotColumnHeader()
                                EmptyView()
                            }
                            unboundList
                        }

                        if !items.isEmpty {
                            sectionHeader("Files in Stores", count: items.count)
                            ViewThatFits(in: .horizontal) {
                                UnmanagedFileColumnHeader()
                                EmptyView()
                            }
                            VStack(spacing: 2) {
                                ForEach(items) { item in
                                    UnmanagedRow(item: item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, selecting ? 90 : 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            if selecting {
                actionBar
                    .padding(.horizontal, 30)
                    .padding(.bottom, 22)
            }
        }
        .alert("Delete backups?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { deleteTargets.removeAll() }
            Button("Delete", role: .destructive) {
                let targets = deleteTargets
                state.deleteSnapshots(targets)
                selection.subtract(targets)
                deleteTargets.removeAll()
                if selection.isEmpty { selecting = false }
            }
        } message: {
            Text("\(deleteTargets.count) backup\(deleteTargets.count == 1 ? "" : "s") will be moved to the macOS Trash. Missing records are removed; offline copies are skipped.")
        }
        .sheet(item: $pickerRequest) { request in
            BindingPickerSheet(
                title: "Move to Binding",
                subtitle: "Choose the binding that should own \(request.targets.count == 1 ? "this backup" : "these backups")",
                bindings: state.bindings,
                apply: { binding in
                    state.assignSnapshots(request.targets, to: binding)
                    selection.subtract(request.targets)
                    if selection.isEmpty { selecting = false }
                    pickerRequest = nil
                },
                cancel: { pickerRequest = nil }
            )
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
        .onChange(of: search) { _, _ in
            selection.removeAll()
            selecting = false
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    private var unboundList: some View {
        VStack(spacing: 2) {
            ForEach(unboundGroups) { group in
                SnapshotInventoryRow(
                    group: group,
                    selecting: selecting,
                    selected: selection.contains(group.id),
                    tap: { handleTap(group.id) }
                )
                .contextMenu {
                    Button {
                        pickerRequest = UnmanagedMoveRequest(targets: contextIDs(for: group))
                    } label: {
                        Label("Move to Binding", systemImage: "link")
                    }
                    .disabled(state.bindings.isEmpty)
                    Button {
                        requestRename(contextIDs(for: group))
                    } label: {
                        Label("Rename", systemImage: "textformat")
                    }
                    Button {
                        state.verifySnapshots(contextIDs(for: group))
                    } label: {
                        Label("Verify", systemImage: "checkmark.shield")
                    }
                    Divider()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: group.primary.absolutePath)])
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                    .disabled(group.availability != .available)
                    Button {
                        copyToPasteboard(group.record.id)
                    } label: {
                        Label("Copy Snapshot ID", systemImage: "number")
                    }
                    Button {
                        copyToPasteboard(group.primary.absolutePath)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    .disabled(group.availability != .available)
                    Divider()
                    Button(role: .destructive) {
                        requestDelete(contextIDs(for: group))
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .draggable(dragPayload(for: group)) {
                    SnapshotDragPreview(count: dragIDs(for: group).count)
                }
                .background {
                    if selecting {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SnapshotRowFramesKey.self,
                                value: [group.id: proxy.frame(in: .named("snapshotList"))]
                            )
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "snapshotList")
        .onPreferenceChange(SnapshotRowFramesKey.self) { frames in
            if frames != rowFrames { rowFrames = frames }
        }
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

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected")
                .font(.bindery(12.5, .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .monospacedDigit()

            Divider().frame(height: 18)

            Button {
                pickerRequest = UnmanagedMoveRequest(targets: selection)
            } label: {
                Label("Move", systemImage: "link")
                    .font(.bindery(12, .medium))
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)

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
            .buttonStyle(UnmanagedBarButtonStyle())
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unmanaged")
                    .font(.bindery(34, .bold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                Text(subtitle)
                    .font(.bindery(15, .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer()
            if unboundGroups.isEmpty == false {
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    if !selecting { selection.removeAll() }
                }
                .buttonStyle(UnmanagedBarButtonStyle())
                .padding(.top, 3)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !unboundGroups.isEmpty {
            parts.append("\(unboundGroups.count) backup\(unboundGroups.count == 1 ? "" : "s") without a binding")
        }
        if !items.isEmpty {
            parts.append("\(items.count) file\(items.count == 1 ? "" : "s") in stores")
        }
        return parts.isEmpty ? "Nothing waiting for you" : parts.joined(separator: " · ")
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.bindery(13.5, .semibold))
                .foregroundStyle(Color.appSecondaryText)
            Text("\(count)")
                .font(.bindery(11, .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.appTertiaryText)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.22))
            Text(query.isEmpty ? "Nothing unmanaged" : "No matching items")
                .font(.bindery(16, .semibold))
                .foregroundStyle(Color.primary.opacity(0.80))
            Text(query.isEmpty
                 ? "Every backup belongs to a binding, and every file in the stores is either a snapshot or explicitly ignored."
                 : "Try a different name, store, or snapshot ID.")
                .font(.bindery(12.5))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var orderedIDs: [String] {
        unboundGroups.map(\.id)
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

    private func contextIDs(for group: SnapshotGroup) -> Set<String> {
        if selection.contains(group.id) { return selection }
        selection = [group.id]
        selecting = true
        return [group.id]
    }

    private func dragIDs(for group: SnapshotGroup) -> Set<String> {
        selection.contains(group.id) ? selection : [group.id]
    }

    private func dragPayload(for group: SnapshotGroup) -> String {
        "snapshots:" + dragIDs(for: group).sorted().joined(separator: ",")
    }

    private func requestRename(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let formats = Set(
            state.snapshotGroups
                .filter { ids.contains($0.id) }
                .map { $0.primary.record.format.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let format = formats.count == 1
            ? (formats.first ?? appSettings.defaultFilenameFormat)
            : appSettings.defaultFilenameFormat
        renameRequest = UnmanagedRenameRequest(targets: ids, format: format)
    }

    private func requestDelete(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deleteTargets = ids
        confirmDelete = true
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
                selection = Set(unboundGroups.map(\.id))
            }
            return nil
        }
    }
}

private struct UnmanagedMoveRequest: Identifiable {
    let id = UUID()
    let targets: Set<String>
}

private struct UnmanagedRenameRequest: Identifiable {
    let id = UUID()
    let targets: Set<String>
    let format: String
}

private struct UnmanagedBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .semibold))
            .foregroundStyle(Color.primary.opacity(0.58))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct UnmanagedRow: View {
    let item: UnmanagedItem
    @EnvironmentObject private var state: LibraryState
    @State private var hovering = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideRow
                .frame(minWidth: 1080)
            compactRow
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(
            Color.primary.opacity(hovering ? 0.05 : 0.018),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.absolutePath)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.absolutePath)])
            } label: {
                Label("Show in Finder", systemImage: "magnifyingglass")
            }
            Button {
                copyToPasteboard(item.absolutePath)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Button {
                copyToPasteboard(item.name)
            } label: {
                Label("Copy Name", systemImage: "textformat")
            }
            Divider()
            Button {
                state.importUnmanaged(item)
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
            Button(role: .destructive) {
                state.ignoreUnmanaged(item)
            } label: {
                Label("Ignore", systemImage: "eye.slash")
            }
        }
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            icon
            nameBlock
            Spacer(minLength: 8)
            sizeView.frame(width: 70, alignment: .trailing)
            actions
        }
    }

    private var wideRow: some View {
        HStack(spacing: 14) {
            icon
            nameBlock
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            Text(item.storeName)
                .font(.bindery(12.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            CategoryTagView(category: item.categoryPath)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text(item.relativePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appTertiaryText)
                .lineLimit(1)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            sizeView.frame(width: 70, alignment: .trailing)
            actions
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.62))
        }
        .frame(width: 32, height: 32)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.bindery(14, .semibold))
                .foregroundStyle(Color.primary.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.relativePath)
                .font(.bindery(12))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var sizeView: some View {
        Text(sizeText)
            .font(.bindery(12, .medium))
            .monospacedDigit()
            .foregroundStyle(Color.appSecondaryText)
    }

    private var actions: some View {
        HStack(spacing: 7) {
            Button("Import") {
                state.importUnmanaged(item)
            }
            .buttonStyle(UnmanagedActionStyle(prominent: true))

            Button("Ignore") {
                state.ignoreUnmanaged(item)
            }
            .buttonStyle(UnmanagedActionStyle(prominent: false))
        }
    }

    private var sizeText: String {
        guard let bytes = item.byteCount else { return "—" }
        return fileSizeText(bytes)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct UnmanagedFileColumnHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 44, height: 1)
            Text("Name")
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            Text("Store")
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text("Category")
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text("Path")
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 70, alignment: .trailing)
            Color.clear.frame(width: 130, height: 1)
        }
        .font(.bindery(11.5, .semibold))
        .foregroundStyle(Color.appSecondaryText)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .frame(minWidth: 1080)
    }
}

private struct UnmanagedActionStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11, .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.62))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                prominent ? Color.accentColor : Color.primary.opacity(0.055),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
