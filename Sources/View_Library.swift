import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    @State private var sidebar: SidebarSelection = .active
    @State private var search = ""
    @State private var snapshotBindingFilter: UUID?
    @State private var scope = TimeScope.all
    @State private var viewMode = LibraryViewMode.grid
    @State private var sort: LibrarySort? = .lastBackup
    @State private var sortAscending = false
    @State private var searchFocused = false
    @State private var selectedID: UUID?
    @State private var editingBinding: BackupBinding?
    @State private var pendingDelete: BackupBinding?
    @State private var isDropTargeted = false
    @State private var dropQueue: [URL] = []
    @AppStorage("folderCardWidth") private var cardWidth: Double = 232
    @State private var forcedScheme: ColorScheme?
    @State private var showSettings = false
    @State private var didApplyDefaultViewMode = false
    @AppStorage("timeline.visible") private var timelineVisible = true
    @AppStorage("timeline.width") private var timelineWidth: Double = 360
    @State private var windowWidth: CGFloat = 0
    @State private var showTimelineSheet = false

    private var visibleBindings: [BackupBinding] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = state.bindings.filter { binding in
            matchesSidebar(binding, selection: sidebar)
                && matchesTime(binding, scope: scope)
                && (query.isEmpty || ([binding.name, binding.sourcePath, binding.destinationPath, binding.category] + binding.creators.map(\.rawValue))
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        guard let sort else { return filtered }
        return sortedBindings(filtered, by: sort, ascending: sortAscending)
    }

    private var selectedBinding: BackupBinding? {
        guard let selectedID else { return nil }
        return state.bindings.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            mainContent
            detailOverlay
            statusOverlay
            dropOverlay
        }
        .background(WindowConfigurator(colorScheme: forcedScheme))
        .preferredColorScheme(forcedScheme)
        .onChange(of: viewMode) { _, _ in searchFocused = false }
        .onChange(of: sidebar) { _, newValue in
            searchFocused = false
            search = ""
            if newValue != .backups { snapshotBindingFilter = nil }
            applyDefaultSort(for: newValue)
        }
        .onChange(of: sort) { _, _ in searchFocused = false }
        .onChange(of: cardWidth) { _, _ in searchFocused = false }
        .onAppear(perform: applyLaunchDefaults)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            state.scan()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            state.scan()
        }
        .animation(.easeOut(duration: 0.18), value: state.statusMessage)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(item: $state.finderIntake) { intake in
            FinderIntakeSheet(intake: intake)
                .environmentObject(state)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appSettings)
                .environmentObject(state)
        }
        .sheet(isPresented: $showTimelineSheet) {
            TimelinePanel(onClose: { showTimelineSheet = false })
                .frame(width: 420, height: 720)
        }
        .sheet(item: $editingBinding, onDismiss: openNextDroppedBinding) { binding in
            BindingEditor(
                binding: binding,
                isNew: !state.bindings.contains(where: { $0.id == binding.id })
            ) { saved in
                state.save(saved)
                editingBinding = nil
            } cancel: {
                editingBinding = nil
            } delete: {
                editingBinding = nil
                DispatchQueue.main.async { pendingDelete = binding }
            }
        }
        .alert("Delete Project", isPresented: deleteAlertPresented) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    PreviewImageStore.remove(path: pendingDelete.previewImagePath)
                    state.delete(pendingDelete)
                }
                selectedID = nil
                self.pendingDelete = nil
            }
        } message: {
            Text("Source files, stores and snapshots will not be deleted")
        }
        .alert("Bindery", isPresented: errorAlertPresented) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            LibrarySidebar(
                selection: $sidebar,
                forcedScheme: $forcedScheme,
                dismissSearchFocus: { searchFocused = false },
                resetSnapshotFilter: {
                    snapshotBindingFilter = nil
                    search = ""
                },
                openSettings: { showSettings = true }
            )
            .environmentObject(state)
            .frame(width: 272)
            Rectangle()
                .fill(Color.appBorder)
                .frame(width: 1)
            VStack(spacing: 0) {
                LibraryToolbar(
                    search: $search,
                    viewMode: $viewMode,
                    sort: $sort,
                    sortAscending: $sortAscending,
                    searchFocused: $searchFocused,
                    cardWidth: $cardWidth,
                    searchPlaceholder: searchPlaceholder,
                    add: addBinding,
                    refresh: { state.scan(trigger: .manual) },
                    timelineActive: timelineVisible && windowWidth >= 1400,
                    toggleTimeline: {
                        if windowWidth >= 1400 {
                            timelineVisible.toggle()
                        } else {
                            showTimelineSheet = true
                        }
                    }
                )
                Group {
                    if sidebar == .backups {
                        SnapshotInventoryView(
                            search: search,
                            bindingFilter: snapshotBindingFilter,
                            clearBindingFilter: { snapshotBindingFilter = nil },
                            openBinding: { selectedID = $0 }
                        )
                    } else if sidebar == .unmanaged {
                        UnmanagedView(search: search)
                    } else {
                        LibraryContent(
                            title: sidebarTitle,
                            bindings: visibleBindings,
                            allBindings: state.bindings,
                            scope: $scope,
                            viewMode: viewMode,
                            sort: $sort,
                            sortAscending: $sortAscending,
                            cardWidth: cardWidth,
                            isRunning: { state.runningIDs.contains($0.id) },
                            select: { selectedID = $0.id },
                            edit: { editingBinding = $0 },
                            favorite: state.toggleFavorite,
                            run: { runOrChoose($0) },
                            drop: { binding, urls in
                                guard let first = urls.first else { return }
                                if binding.isGenerator {
                                    state.runBackup(binding, sourceURL: first, style: appSettings.filenameStyle)
                                } else if URL(fileURLWithPath: binding.sourcePath).standardizedFileURL.path
                                            == first.standardizedFileURL.path {
                                    state.runBackup(binding, style: appSettings.filenameStyle)
                                } else {
                                    state.errorMessage = "\(binding.name) has a fixed source. Drop the file onto a generator card, or edit this binding."
                                }
                            },
                            move: state.move,
                            reveal: { state.reveal($0.sourcePath) },
                            delete: { pendingDelete = $0 },
                            assignSnapshots: { ids, binding in
                                state.assignSnapshots(ids, to: binding)
                            },
                            create: addBinding,
                            dismissSearchFocus: { searchFocused = false }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if timelineVisible && windowWidth >= 1400 {
                TimelineResizeHandle(width: $timelineWidth)
                TimelinePanel(onClose: { timelineVisible = false })
                    .frame(width: timelineWidth)
            }
        }
        .background(Color.appBackground)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if abs(width - windowWidth) > 1 { windowWidth = width }
        }
    }

    private var searchPlaceholder: String {
        if snapshotBindingFilter != nil { return "Search this binding" }
        if sidebar == .backups { return "Search Backups" }
        return "Search Projects"
    }

    private func showBackups(for binding: BackupBinding) {
        selectedID = nil
        search = ""
        searchFocused = false
        snapshotBindingFilter = binding.id
        sidebar = .backups
    }

    @ViewBuilder
    private var detailOverlay: some View {
        if let binding = selectedBinding {
            BindingDetail(
                binding: binding,
                isRunning: state.runningIDs.contains(binding.id),
                close: { selectedID = nil },
                edit: { editingBinding = binding },
                favorite: { state.toggleFavorite(binding) },
                run: { runOrChoose(binding) },
                openSource: { state.open(binding.sourcePath) },
                openDestination: { state.open(binding.destinationPath) },
                openBackups: { showBackups(for: binding) },
                revealSnapshot: { state.reveal($0) }
            )
            .transition(.opacity)
            .zIndex(4)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if !state.statusMessage.isEmpty {
            StatusToast(text: state.statusMessage)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            DropTargetOverlay()
                .zIndex(20)
        }
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )
    }

    private func applyDefaultSort(for selection: SidebarSelection) {
        let defaultSort: LibrarySort
        if selection.usesCategorySortDefault {
            defaultSort = appSettings.defaultCategorySort
        } else if selection.usesSmartSortDefault {
            defaultSort = appSettings.defaultSmartSort
        } else {
            return
        }
        sort = defaultSort
        sortAscending = defaultSort.defaultAscending
    }

    private func applyLaunchDefaults() {
        guard !didApplyDefaultViewMode else { return }
        viewMode = appSettings.defaultViewMode
        scope = appSettings.defaultScope
        let initialSort = sidebar.usesCategorySortDefault ? appSettings.defaultCategorySort : appSettings.defaultSmartSort
        sort = initialSort
        sortAscending = initialSort.defaultAscending
        if let scheme = appSettings.launchColorScheme {
            forcedScheme = scheme
        }
        if appSettings.rescanOnLaunch {
            state.scan()
        }
        didApplyDefaultViewMode = true
    }

    private func runOrChoose(_ binding: BackupBinding) {
        if binding.isGenerator {
            chooseSource(for: binding)
        } else {
            state.runBackup(binding, style: appSettings.filenameStyle)
        }
    }

    private func chooseSource(for binding: BackupBinding) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Back Up"
        panel.message = "Choose the file or folder to back up with \(binding.name)."
        if panel.runModal() == .OK, let url = panel.url {
            state.runBackup(binding, sourceURL: url, style: appSettings.filenameStyle)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let text = item as? String {
                    url = URL(string: text)
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            dropQueue.append(contentsOf: urls)
            openNextDroppedBinding()
        }
    }

    private func openNextDroppedBinding() {
        guard editingBinding == nil, !dropQueue.isEmpty else { return }
        let url = dropQueue.removeFirst()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            openNextDroppedBinding()
            return
        }
        let kind: BindingKind = isDirectory.boolValue ? .folder : .file
        let name = kind == .folder
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        let tones: [CardTone] = [.orange, .cyan, .green, .blue, .purple, .pink]
        var binding = BackupBinding(
            name: name.isEmpty ? "Untitled" : name,
            sourcePath: url.path,
            kind: kind,
            tone: tones.randomElement() ?? .slate,
            filenameFormat: appSettings.defaultFilenameFormat
        )
        if let store = state.stores.first {
            binding.storeID = store.id
            binding.destinationPath = store.path
        }
        editingBinding = binding
    }

    private var sidebarTitle: String {
        switch sidebar {
        case .all: return "All Bindings"
        case .backups: return "All Backups"
        case .unmanaged: return "Unmanaged"
        case .active: return "Active"
        case .neverBackedUp: return "Unbacked"
        case .favorites: return "Favorites"
        case .needsInput: return "Needs Input"
        case .offline: return "Offline"
        case .archived: return "Archived"
        case .category(let value): return value
        case .creator(let value): return value.rawValue
        case .kind(let value): return value.rawValue
        case .tone(let value): return value.rawValue
        }
    }

    private func addBinding() {
        let tone = [CardTone.orange, .cyan, .green, .blue, .purple].randomElement() ?? .slate
        var binding = BackupBinding(
            destinationPath: appSettings.defaultDestinationPath,
            category: appSettings.defaultCategory.isEmpty ? "Uncategorized" : appSettings.defaultCategory,
            creators: appSettings.defaultCreators,
            tone: tone,
            showPreviewOnCover: appSettings.defaultShowPreviewOnCover,
            compressBackups: appSettings.defaultCompressBackups,
            archiveAfterFirstBackup: appSettings.defaultArchiveAfterFirst,
            includeGitMetadata: appSettings.defaultIncludeGit,
            respectsGitignore: appSettings.defaultRespectsGitignore,
            filenameFormat: appSettings.defaultFilenameFormat
        )
        if let store = state.stores.first {
            binding.storeID = store.id
            binding.destinationPath = store.path
        }
        editingBinding = binding
    }
}

// MARK: - Sidebar

private struct LibrarySidebar: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: SidebarSelection
    @Binding var forcedScheme: ColorScheme?
    let dismissSearchFocus: () -> Void
    let resetSnapshotFilter: () -> Void
    let openSettings: () -> Void
    @AppStorage("sidebar.smartFolders") private var showSmartFolders = true
    @AppStorage("sidebar.categories") private var showCategories = true
    @AppStorage("sidebar.types") private var showTypes = true
    @AppStorage("sidebar.creators") private var showCreators = true
    @State private var collapsedCategories: Set<String> = []
    @State private var editingCategory: String?
    @State private var categoryDraft = ""
    @State private var creatingCategory = false
    @State private var hoveringSettings = false
    @FocusState private var categoryFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarRow("All Bindings", icon: "square.grid.2x2", selection: .all)
                    sidebarRow(
                        "All Backups",
                        icon: "archivebox",
                        selection: .backups,
                        reselect: resetSnapshotFilter
                    )
                    sidebarRow("Unmanaged", icon: "tray", selection: .unmanaged)

                    sectionHeader("Smart Folders", expanded: $showSmartFolders)
                    if showSmartFolders {
                        sidebarRow(
                            "Active",
                            icon: "checkmark.circle",
                            selection: .active,
                            dropHandler: { id in state.assignArchived(id, false) }
                        )
                        sidebarRow(
                            "Favorites",
                            icon: "star",
                            selection: .favorites,
                            dropHandler: { id in state.assignArchived(id, false) }
                        )
                        sidebarRow(
                            "Unbacked",
                            icon: "clock.arrow.circlepath",
                            selection: .neverBackedUp,
                            dropHandler: { id in state.assignArchived(id, false) }
                        )
                        sidebarRow(
                            "Offline",
                            icon: "wifi.slash",
                            selection: .offline,
                            dropHandler: { id in state.assignArchived(id, false) }
                        )
                        sidebarRow(
                            "Archived",
                            icon: "archivebox",
                            selection: .archived,
                            dropHandler: { id in state.assignArchived(id, true) }
                        )
                    }

                    sectionHeader("Categories", expanded: $showCategories, count: state.categories.count, add: {
                        let path = state.addNewCategory()
                        beginCategoryEdit(path, isNew: true)
                    })
                    .modifier(CategoryRootDropModifier { path in
                        state.moveCategory(path, under: nil)
                    })
                    if showCategories {
                        ForEach(state.categoryTree) { node in
                            categoryNodeRow(node)
                        }
                    }

                    sectionHeader("Creators", expanded: $showCreators)
                    if showCreators {
                        ForEach(BindingCreator.allCases) { creator in
                            creatorRow(creator)
                        }
                    }

                    sectionHeader("Types", expanded: $showTypes)
                    if showTypes {
                        ForEach(BindingKind.allCases) { kind in
                            sidebarRow(
                                kind.rawValue,
                                icon: kind.icon,
                                selection: .kind(kind),
                                dropHandler: { id in state.assignArchived(id, false) }
                            )
                        }
                    }

                }
                .padding(.horizontal, 11)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 9) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        forcedScheme = colorScheme == .dark ? .light : .dark
                    }
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .frame(width: 27, height: 25)
                }
                .buttonStyle(.plain)
                .help(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")

                StatusDotText(text: "Ready", color: Color.appGreen, font: .bindery(12.5, .medium))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Image(systemName: "house")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.45))
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(hoveringSettings ? 0.90 : 0.45))
                        .frame(width: 25, height: 23)
                        .background(
                            hoveringSettings ? Color.primary.opacity(0.065) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringSettings = $0 }
                .help("Settings")
            }
            .padding(.horizontal, 19)
            .padding(.bottom, 16)
            .padding(.top, 10)
        }
        .background(Color.appSidebar)
        .simultaneousGesture(TapGesture().onEnded { dismissSearchFocus() })
    }

    private func sectionHeader(
        _ title: String,
        expanded: Binding<Bool>,
        count: Int? = nil,
        add: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    Text(title)
                        .font(.bindery(13, .semibold))
                    if let count {
                        Text("\(count)")
                            .font(.bindery(11.5, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.appTertiaryText)
                    }
                    Spacer()
                }
                .foregroundStyle(Color.primary.opacity(0.34))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.50))
                        .frame(width: 30, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Category")
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 28)
        .padding(.bottom, 4)
    }

    private func categoryNodeRow(_ node: CategoryNode) -> AnyView {
        let selected = selection == .category(node.path)
        let tone = state.categoryColor(node.path)
        let expanded = !collapsedCategories.contains(node.path)

        return AnyView(VStack(spacing: 0) {
            HStack(spacing: 6) {
                if node.children.isEmpty {
                    Color.clear.frame(width: 12)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if expanded { collapsedCategories.insert(node.path) }
                            else { collapsedCategories.remove(node.path) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                }

                CategoryFolderIcon(tone: tone)

                if editingCategory == node.path {
                    TextField("Category name", text: $categoryDraft)
                        .font(.bindery(15, .medium))
                        .textFieldStyle(.plain)
                        .focused($categoryFieldFocused)
                        .onSubmit { commitCategoryEdit() }
                        .onExitCommand { cancelCategoryEdit() }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                        }
                } else {
                    Text(node.name)
                        .font(.bindery(15, selected ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(selected ? 0.94 : 0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(node.totalBindingCount)")
                    .font(.bindery(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.appTertiaryText)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.leading, CGFloat(node.depth) * 14 + 11)
            .padding(.trailing, 11)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onTapGesture {
                if editingCategory != node.path {
                    selection = .category(node.path)
                }
            }
            .draggable("category:" + node.path) {
                CategoryDragPreview(name: node.name, tone: tone)
            }
            .modifier(CategoryDropModifier(
                assign: { id in state.assignCategory(id, node.path) },
                move: { dragged in state.moveCategory(dragged, under: node.path) }
            ))
            .contextMenu {
                Button("Rename") {
                    beginCategoryEdit(node.path, isNew: false)
                }
                Menu("Move") {
                    Button("Root") {
                        state.moveCategory(node.path, under: nil)
                    }
                    Divider()
                    ForEach(state.categories.filter {
                        $0 != node.path && !$0.hasPrefix(node.path + "/")
                    }, id: \.self) { target in
                        Button(target) {
                            state.moveCategory(node.path, under: target)
                        }
                    }
                }
                Menu("Folder Color") {
                    ForEach(CardTone.allCases) { color in
                        Button {
                            state.setCategoryColor(node.path, color)
                        } label: {
                            HStack {
                                Circle().fill(appSettings.baseColor(for: color, scheme: colorScheme)).frame(width: 10, height: 10)
                                Text(color.rawValue)
                            }
                        }
                    }
                }
            }

            if expanded {
                ForEach(node.children) { child in
                    categoryNodeRow(child)
                }
            }
        })
    }

    private func beginCategoryEdit(_ path: String, isNew: Bool) {
        editingCategory = path
        creatingCategory = isNew
        categoryDraft = isNew ? "" : (path.split(separator: "/").last.map(String.init) ?? path)
        DispatchQueue.main.async {
            categoryFieldFocused = true
        }
    }

    private func commitCategoryEdit() {
        guard let old = editingCategory else { return }
        let name = categoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            if creatingCategory { state.removeCategoryIfEmpty(old) }
        } else {
            state.renameCategory(old, to: name)
        }
        editingCategory = nil
        creatingCategory = false
        categoryFieldFocused = false
    }

    private func cancelCategoryEdit() {
        if creatingCategory, let old = editingCategory {
            state.removeCategoryIfEmpty(old)
        }
        editingCategory = nil
        creatingCategory = false
        categoryFieldFocused = false
    }

    private func creatorRow(_ creator: BindingCreator) -> some View {
        let item = SidebarSelection.creator(creator)
        let selected = selection == item
        return Button { selection = item } label: {
            HStack(spacing: 11) {
                CreatorIconView(creator: creator, size: 14, tint: .adaptive)
                    .opacity(selected ? 0.90 : 0.68)
                    .frame(width: 18)
                Text(creator.rawValue)
                    .font(.bindery(15, selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(selected ? 0.94 : 0.68))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(state.count(item))")
                    .font(.bindery(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .modifier(SidebarDropModifier(handler: { id in
            state.setCreator(id, creator)
        }))
    }

    private func sidebarRow(
        _ title: String,
        icon: String,
        selection item: SidebarSelection,
        compactIcon: Bool = false,
        iconColor: Color? = nil,
        iconOpacity: Double = 0.78,
        dropHandler: ((UUID) -> Void)? = nil,
        reselect: (() -> Void)? = nil
    ) -> some View {
        let selected = selection == item
        return Button {
            if selected, let reselect {
                reselect()
            } else {
                selection = item
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: compactIcon ? 8 : 13, weight: .medium))
                    .foregroundStyle(iconColor ?? Color.primary.opacity(iconOpacity))
                    .frame(width: 18)
                Text(title)
                    .font(.bindery(15, selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(selected ? 0.94 : 0.68))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(state.count(item))")
                    .font(.bindery(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.30))
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .modifier(SidebarDropModifier(handler: dropHandler))
    }
}

// MARK: - Toolbar

private struct LibraryToolbar: View {
    @Binding var search: String
    @Binding var viewMode: LibraryViewMode
    @Binding var sort: LibrarySort?
    @Binding var sortAscending: Bool
    @Binding var searchFocused: Bool
    @Binding var cardWidth: Double
    let searchPlaceholder: String
    let add: () -> Void
    let refresh: () -> Void
    let timelineActive: Bool
    let toggleTimeline: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.55))
                SearchField(
                    text: $search,
                    isFocused: $searchFocused,
                    placeholder: searchPlaceholder,
                    onEscape: { searchFocused = false }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .accessibilityLabel(searchPlaceholder)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(width: 270, height: 38)
            .background(Color.primary.opacity(0.052), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }

            Button(action: add) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ToolbarSquareButtonStyle())
            .help("New Project")

            HStack(spacing: 1) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Button { viewMode = mode } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 15.5, weight: .medium))
                            .frame(width: 37, height: 34)
                    }
                    .buttonStyle(ToolbarSegmentButtonStyle(selected: viewMode == mode))
                    .help(mode.rawValue.capitalized)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Menu {
                Button {
                    sort = nil
                } label: {
                    if sort == nil {
                        Label("Unsorted", systemImage: "checkmark")
                    } else {
                        Text("Unsorted")
                    }
                }
                Divider()
                ForEach(LibrarySort.allCases) { option in
                    Button {
                        sort = option
                        sortAscending = option.defaultAscending
                    } label: {
                        if sort == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(sort?.rawValue ?? "Unsorted")
                        .font(.bindery(10.5, .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.primary.opacity(0.66))
                .padding(.horizontal, 8)
                .frame(width: 112, height: 38)
                .background(Color.primary.opacity(0.052), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort: \(sort?.rawValue ?? "Unsorted")")

            if viewMode == .grid {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.30))
                    Button {
                        cardWidth = max(180, cardWidth - 12)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary.opacity(0.48))
                    Slider(value: $cardWidth, in: 180...300) { editing in
                        if editing {
                            searchFocused = false
                        }
                    }
                    .controlSize(.mini)
                    .frame(width: 68)
                    .tint(Color.primary.opacity(0.42))
                    Button {
                        cardWidth = min(300, cardWidth + 12)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary.opacity(0.48))
                }
                .padding(.horizontal, 8)
                .frame(height: 38)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help("Folder size")
            }

            Spacer()

            Button(action: toggleTimeline) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .medium))
                    Text("Timeline")
                        .font(.bindery(12.5, .medium))
                }
                .foregroundStyle(timelineActive ? Color.accentColor : Color.primary.opacity(0.62))
                .padding(.horizontal, 9)
                .frame(height: 36)
                .background(
                    timelineActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.052),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help(timelineActive ? "Hide Timeline" : "Show Timeline")

            Button(action: refresh) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                    Text("Rescan")
                        .font(.bindery(14.5, .medium))
                }
                .foregroundStyle(Color.primary.opacity(0.58))
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
        .frame(height: 62)
        .background(Color.appBackground)
    }
}

// MARK: - Content

private struct LibraryContent: View {
    let title: String
    let bindings: [BackupBinding]
    let allBindings: [BackupBinding]
    @Binding var scope: TimeScope
    let viewMode: LibraryViewMode
    @Binding var sort: LibrarySort?
    @Binding var sortAscending: Bool
    let cardWidth: Double
    let isRunning: (BackupBinding) -> Bool
    let select: (BackupBinding) -> Void
    let edit: (BackupBinding) -> Void
    let favorite: (BackupBinding) -> Void
    let run: (BackupBinding) -> Void
    let drop: (BackupBinding, [URL]) -> Void
    let move: (BackupBinding, String) -> Void
    let reveal: (BackupBinding) -> Void
    let delete: (BackupBinding) -> Void
    let assignSnapshots: (Set<String>, BackupBinding) -> Void
    let create: () -> Void
    let dismissSearchFocus: () -> Void
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.bindery(34, .bold))
                            .foregroundStyle(Color.primary.opacity(0.96))
                        Text("\(bindings.count) projects")
                            .font(.bindery(15, .medium))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(TimeScope.allCases) { item in
                            Button(item.rawValue) { scope = item }
                                .buttonStyle(ScopeButtonStyle(selected: scope == item))
                        }
                    }
                    .padding(.top, 3)
                }
                ActivityStrip(bindings: allBindings)
                    .padding(.top, 2)
                if bindings.isEmpty {
                    LibraryEmptyState(create: create)
                } else {
                    switch viewMode {
                    case .grid:
                        cardGrid
                    case .list:
                        list
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .simultaneousGesture(TapGesture().onEnded { dismissSearchFocus() })
    }

    private var cardGrid: some View {
        let minWidth = CGFloat(cardWidth)
        let horizontalSpacing = max(14, minWidth * 0.10)
        let columnCount = gridWidth > 0
            ? max(1, Int((gridWidth + horizontalSpacing) / (minWidth + horizontalSpacing)))
            : 4
        let width = gridWidth > 0
            ? (gridWidth - CGFloat(columnCount - 1) * horizontalSpacing) / CGFloat(columnCount)
            : minWidth
        let scale = width / BindingFolderCard.designWidth
        let verticalSpacing = max(24, width * 0.18)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: horizontalSpacing, alignment: .top), count: columnCount),
            alignment: .center,
            spacing: verticalSpacing
        ) {
            ForEach(Array(bindings.enumerated()), id: \.element.id) { index, binding in
                BindingFolderCard(binding: binding, isRunning: isRunning(binding))
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: width, height: BindingFolderCard.designHeight * scale, alignment: .top)
                    .overlay { contextSurface(for: binding) }
                    .modifier(SnapshotBindingDropModifier { ids in assignSnapshots(ids, binding) })
                    .staggeredAppearance(index: index)
                    .draggable(binding.id.uuidString) {
                        DragPreview(binding: binding)
                    }
                    .onTapGesture { select(binding) }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if abs(width - gridWidth) > 1 { gridWidth = width }
        }
        .id(title + "|" + viewMode.rawValue)
    }

    private var list: some View {
        VStack(spacing: 2) {
            listHeader
            ForEach(bindings) { binding in
                BindingListRow(binding: binding, isRunning: isRunning(binding))
                    .overlay { contextSurface(for: binding) }
                    .modifier(SnapshotBindingDropModifier { ids in assignSnapshots(ids, binding) })
                    .draggable(binding.id.uuidString) {
                        DragPreview(binding: binding)
                    }
                    .onTapGesture { select(binding) }
            }
        }
        .padding(.top, 4)
    }

    private var listHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 30, height: 1)
            listHeaderButton("Name", option: .name, minWidth: 150)
            listHeaderButton("Category", option: .category, minWidth: 95)
            Text("Store")
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            listHeaderButton("Status", option: .status, minWidth: 100)
            listHeaderButton("Last Backup", option: .lastBackup, minWidth: 95)
            Text("Backup Size")
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            listHeaderButton("Type", option: .kind, minWidth: 55)
            Color.clear.frame(width: 42, height: 1)
        }
        .font(.bindery(12.5, .semibold))
        .foregroundStyle(Color.appSecondaryText)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func listHeaderButton(_ title: String, option: LibrarySort, minWidth: CGFloat) -> some View {
        Button {
            if sort == option {
                if sortAscending {
                    sortAscending = false
                } else {
                    sort = nil
                }
            } else {
                sort = option
                sortAscending = option.defaultAscending
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sort == option {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func contextSurface(for binding: BackupBinding) -> some View {
        BindingContextMenuSurface(
            binding: binding,
            categories: Array(Set(allBindings.map(\.category))).sorted(),
            open: { select(binding) },
            run: { run(binding) },
            editNote: { edit(binding) },
            favorite: { favorite(binding) },
            move: { move(binding, $0) },
            reveal: { reveal(binding) },
            delete: { delete(binding) }
        )
    }
}

// MARK: - Activity

private struct ActivityStrip: View {
    let bindings: [BackupBinding]

    private var points: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let result: [(String, Int)] = (0..<12).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let count = bindings.reduce(0) { result, binding in
                result + binding.backupDates.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }.count
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = offset == 11 ? "MMM yyyy" : "MMM"
            return (formatter.string(from: date), count)
        }
        return result
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(Color.primary.opacity(point.count == 0 ? 0.14 : 0.58))
                        .frame(width: 11, height: min(38, max(3, CGFloat(point.count) * 8)))
                        .frame(height: 38, alignment: .bottom)
                    Text(point.label)
                        .font(.bindery(12.5, .medium))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 62, alignment: .bottom)
        .padding(.horizontal, 16)
    }
}

// MARK: - List row

private struct BindingListRow: View {
    let binding: BackupBinding
    let isRunning: Bool
    @EnvironmentObject private var state: LibraryState
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var statusText: String { backupCardStatusText(for: binding, isRunning: isRunning) }

    private var backupSizeText: String {
        guard let bytes = binding.totalBackupBytes else { return "—" }
        return fileSizeText(bytes)
    }

    private static let lastBackupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var lastBackupText: String {
        guard let date = binding.lastBackupAt else { return "—" }
        return Self.lastBackupFormatter.string(from: date)
    }

    private var statusDot: Color {
        if isRunning { return Color.appGreen }
        if binding.isArchived { return Color.appRed }
        if binding.storeID == nil || binding.destinationPath.isEmpty { return Color.appOrange }
        if !binding.destinationExists { return Color.appRed }
        if !binding.isGenerator && (binding.sourcePath.isEmpty || !binding.sourceExists) { return Color.appRed }
        if binding.lastBackupAt == nil { return Color.appGray }
        return Color.appGreen
    }

    var body: some View {
        HStack(spacing: 12) {
            miniFolder
            Text(binding.name.isEmpty ? "Untitled" : binding.name)
                .font(.bindery(13.5, .semibold))
                .foregroundStyle(Color.primary.opacity(0.92))
                .lineLimit(1)
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            CategoryTagView(category: binding.category)
                .frame(minWidth: 95, maxWidth: .infinity, alignment: .leading)
            Text(state.store(for: binding)?.name ?? "—")
                .font(.bindery(12.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            StatusDotText(
                text: statusText,
                color: statusDot,
                font: .bindery(12.5, .medium)
            )
            .foregroundStyle(Color.appSecondaryText)
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            Text(lastBackupText)
                .font(.bindery(12.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 95, maxWidth: .infinity, alignment: .leading)
            Text(backupSizeText)
                .font(.bindery(12.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .monospacedDigit()
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Image(systemName: binding.kind.icon)
                    .font(.system(size: 11))
                Text(binding.kind.rawValue)
            }
            .font(.bindery(12, .medium))
            .foregroundStyle(Color.appSecondaryText)
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)
            if isRunning {
                ProgressView().controlSize(.mini).frame(width: 16)
            }
            Image(systemName: binding.isFavorite ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundStyle(binding.isFavorite ? Color(rgb: 0xE9B75F) : Color.primary.opacity(0.35))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(
            Color.primary.opacity(hovering ? 0.055 : 0.022),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var miniFolder: some View {
        let palette = binding.tone.palette(for: colorScheme)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.paperBottom)
                .frame(width: 24, height: 26)
            if let svg = binding.coverIconSVG {
                LucideIconView(svg: svg, size: 11, tint: .adaptive)
                    .frame(width: 24, height: 20, alignment: .center)
            }
            FolderFrontShape()
                .fill(LinearGradient(colors: [palette.frontTop, palette.frontBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 18)
                .offset(y: 12)
                .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Empty state

private struct LibraryEmptyState: View {
    let create: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(rgb: 0xC9CDD3))
                    .frame(width: 96, height: 94)
                    .offset(y: 0)
                FolderFrontShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(rgb: 0x5E646D), Color(rgb: 0x42464D)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 126, height: 74)
                    .offset(y: 48)
                    .shadow(color: .black.opacity(0.30), radius: 8, y: 5)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .offset(y: 15)
            }
            .frame(height: 128)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)

            Text("No projects here yet")
                .font(.bindery(16, .semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .padding(.top, 26)
            Text("Bind a folder or file and Bindery will keep timestamped snapshots.")
                .font(.bindery(11.5))
                .foregroundStyle(Color.primary.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            Button("New Project", action: create)
                .buttonStyle(DetailPrimaryButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }
}

// MARK: - Detail overlay

private struct BindingDetail: View {
    let binding: BackupBinding
    @Environment(\.colorScheme) private var colorScheme
    let isRunning: Bool
    let close: () -> Void
    let edit: () -> Void
    let favorite: () -> Void
    let run: () -> Void
    let openSource: () -> Void
    let openDestination: () -> Void
    let openBackups: () -> Void
    let revealSnapshot: (String) -> Void

    var body: some View {
        ZStack {
            ZStack {
                Rectangle().fill(Color.appDetailDim)
                RadialGradient(
                    colors: [binding.tone.palette(for: colorScheme).frontTop.opacity(0.22), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 620
                )
                RadialGradient(
                    colors: [.orange.opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 30,
                    endRadius: 520
                )
            }
            .background(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture(perform: close)

            HStack(alignment: .center, spacing: 34) {
                leftColumn
                rightColumn
            }
            .frame(maxWidth: 1020)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .onTapGesture {}
        }
        .onExitCommand(perform: close)
    }

    private var leftColumn: some View {
        VStack(spacing: 24) {
            BindingFolderCard(binding: binding, isRunning: isRunning, forceOpen: true)
                .scaleEffect(1.16)
                .frame(width: 300, height: 300)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button(action: run) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.black.opacity(0.70))
                        } else {
                            Label(
                                binding.isGenerator ? "Add Backup" : "Backup",
                                systemImage: binding.isGenerator ? "plus" : "arrow.triangle.2.circlepath"
                            )
                            .lineLimit(1)
                        }
                    }
                    .buttonStyle(DetailWideButtonStyle(running: isRunning))
                    .disabled(isRunning || binding.needsInput)
                    .help(isRunning ? "Backing Up…" : (binding.isGenerator ? "Add Backup" : "Backup"))

                    Button(action: edit) {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .lineLimit(1)
                    }
                    .buttonStyle(DetailWideButtonStyle())
                    .help("Edit Binding")
                }

                HStack(spacing: 8) {
                    Button(action: openSource) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(DetailIconButtonStyle(glass: true))
                    .disabled(!binding.sourceExists)
                    .opacity(binding.sourceExists ? 1 : 0.36)
                    .help("Open Source Folder")

                    Button(action: openDestination) {
                        Image(systemName: "folder.fill")
                    }
                    .buttonStyle(DetailIconButtonStyle(glass: true))
                    .disabled(!binding.destinationExists)
                    .opacity(binding.destinationExists ? 1 : 0.36)
                    .help("Open Target Folder")

                    Button(action: openBackups) {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(DetailIconButtonStyle(glass: true))
                    .help("Show This Binding's Backups")

                    Button(action: favorite) {
                        Image(systemName: binding.isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(DetailIconButtonStyle(glass: true))
                    .help(binding.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
            }
        }
        .frame(width: 410)
    }

    private var rightColumn: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasVisualPreview {
                        visualPreview
                    } else {
                        BackupHeatmapPanel(binding: binding)
                    }

                    BackupHistoryPanel(
                        binding: binding,
                        openBackups: openBackups,
                        revealSnapshot: revealSnapshot
                    )

                    if hasVisualPreview {
                        BackupHeatmapPanel(binding: binding)
                    }

                    BindingDetailsPanel(binding: binding)
                    noteButton
                }
                .frame(width: 570)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 570)
    }

    private var hasVisualPreview: Bool {
        effectivePreviewFile(for: binding) != nil
    }

    @ViewBuilder
    private var visualPreview: some View {
        if let file = effectivePreviewFile(for: binding) {
            if isHTMLPreview(file) {
                HTMLPreviewFrame(url: file)
            } else if let image = previewImage(for: binding) {
                ImagePreviewFileFrame(image: image, path: file.path)
            } else {
                FilePreviewFrame(path: file.path)
            }
        }
    }

    private var noteButton: some View {
        Button(action: edit) {
            HStack {
                Text(binding.note?.isEmpty == false ? binding.note! : "Add a note")
                    .font(.bindery(13, .medium))
                    .foregroundStyle(Color.primary.opacity(0.64))
                    .lineLimit(2)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.30))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Color.appPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MediaPreviewPanel: View {
    let binding: BackupBinding

    var body: some View {
        VStack(spacing: 12) {
            if let html = htmlIndexURL(for: binding) {
                HTMLPreviewFrame(url: html)
            } else if let path = binding.previewImagePath, PreviewImageStore.image(at: path) != nil {
                ImagePreviewFrame(path: path)
            }
            BackupHeatmapPanel(binding: binding)
        }
    }
}

private struct ImagePreviewFileFrame: View {
    let image: NSImage
    let path: String

    private var previewSize: CGSize {
        let original = image.size
        guard original.width > 0, original.height > 0 else { return CGSize(width: 1, height: 1) }
        let maxWidth: CGFloat = 570
        let maxHeight: CGFloat = 340
        let scale = min(maxWidth / original.width, maxHeight / original.height)
        return CGSize(width: original.width * scale, height: original.height * scale)
    }

    var body: some View {
        let size = previewSize
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                PreviewOpenFileButton(path: path)
            }
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ImagePreviewFrame: View {
    let path: String

    var body: some View {
        Group {
            if let image = PreviewImageStore.image(at: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.05)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct HTMLPreviewFrame: View {
    let url: URL
    @StateObject private var controller = WebPreviewController()
    @State private var hovering = false
    @State private var zoomLevel: CGFloat = 0.75

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                WebPreview(url: url, zoomLevel: zoomLevel, controller: controller)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .id(url.path)

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Open in browser")
                .padding(10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 300)
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                HStack(spacing: 7) {
                    Button { zoomLevel = max(0.65, zoomLevel - 0.12) } label: {
                        Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    Text("\(Int(zoomLevel * 100))%")
                        .font(.bindery(10, .semibold))
                        .monospacedDigit()
                    Button { zoomLevel = min(1.8, zoomLevel + 0.12) } label: {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Color.primary.opacity(0.78))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .help("Scroll the page · Use the buttons to zoom")
    }
}

private struct BackupHeatmapPanel: View {
    let binding: BackupBinding

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<(52 * 7)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    var body: some View {
        let maxCount = max(1, days.map { day in
            binding.backupDates.filter { Calendar.current.isDate($0, inSameDayAs: day) }.count
        }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Backup Activity")
                    .font(.bindery(15, .semibold))
                Spacer()
                Text("Past year")
                    .font(.bindery(11.5, .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(8), spacing: 2), count: 7),
                spacing: 2
            ) {
                ForEach(days, id: \.self) { day in
                    let count = binding.backupDates.filter { Calendar.current.isDate($0, inSameDayAs: day) }.count
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            count == 0
                                ? Color.primary.opacity(0.075)
                                : Color.appGreen.opacity(min(0.92, 0.34 + Double(count) / Double(maxCount) * 0.58))
                        )
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BackupHistoryPanel: View {
    let binding: BackupBinding
    let openBackups: () -> Void
    let revealSnapshot: (String) -> Void

    private var records: [BackupRecord] { binding.backupHistory }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Backup Records")
                    .font(.bindery(16, .semibold))
                Text("\(records.count)")
                    .font(.bindery(11.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.appSecondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer()
                Text(backupStatusText(for: binding, isRunning: false))
                    .font(.bindery(11.5, .medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                Button(action: openBackups) {
                    HStack(spacing: 4) {
                        Text("All Backups")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(DetailUtilityButtonStyle())
                .fixedSize()
                .help("Show these records in All Backups")
            }

            if records.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.25))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No backups yet")
                            .font(.bindery(12.5, .semibold))
                            .foregroundStyle(Color.primary.opacity(0.62))
                        Text("Click Backup to create the first snapshot.")
                            .font(.bindery(12))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    Spacer()
                }
                .frame(height: 60)
            } else if records.count <= 8 {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            recordRow(record)
                        }
                    }
                }
                .defaultScrollAnchor(.top)
                .scrollIndicators(.visible)
                .frame(height: 288)
            }
        }
        .padding(18)
        .background(Color.appPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func recordRow(_ record: BackupRecord) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(record.id == records.first?.id ? Color.appGreen : Color.primary.opacity(0.22))
                .frame(width: 6, height: 6)

            Text(Self.dateFormatter.string(from: record.date))
                .font(.bindery(13, .semibold))
                .foregroundStyle(Color.primary.opacity(0.84))
                .fixedSize()

            Text(snapshotName(record))
                .font(.bindery(12.5))
                .foregroundStyle(record.snapshotPath.isEmpty ? Color.appTertiaryText : Color.appSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(0)

            if let projectDate = record.projectDate {
                Text("Project \(BackupFilenameFormat.dateText(projectDate, pattern: "yyMMdd", fallback: "yyMMdd"))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appOrange.opacity(0.95))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.appOrange.opacity(0.10), in: Capsule())
                    .fixedSize()
                    .help("Project/content date from the filename, not the backup date")
            }

            if record.id == records.first?.id {
                Text("Latest")
                    .font(.bindery(9, .semibold))
                    .foregroundStyle(Color.appGreen)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.appGreen.opacity(0.12), in: Capsule())
                    .fixedSize()
            }

            if record.copyCount > 1 {
                Text("\(record.copyCount) copies")
                    .font(.bindery(9, .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                    .fixedSize()
            }

            if let availability = record.availability, availability != .available {
                Text(availability == .missing ? "Missing" : "Offline")
                    .font(.bindery(9, .semibold))
                    .foregroundStyle(availability == .missing ? Color.appRed : Color.appOrange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        (availability == .missing ? Color.appRed : Color.appOrange).opacity(0.11),
                        in: Capsule()
                    )
                    .fixedSize()
            }

            Spacer(minLength: 6)

            if !record.snapshotPath.isEmpty {
                Button {
                    revealSnapshot(record.snapshotPath)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Show")
                            .font(.bindery(10.5, .semibold))
                    }
                }
                .buttonStyle(DetailUtilityButtonStyle())
                .fixedSize()
                .disabled(record.availability != nil && record.availability != .available)
                .opacity(record.availability == nil || record.availability == .available ? 1 : 0.36)
            }
        }
        .padding(.vertical, 7)
        .help(record.snapshotPath.isEmpty ? "Snapshot path was not recorded for this backup" : record.snapshotPath)
    }

    private func snapshotName(_ record: BackupRecord) -> String {
        if record.snapshotPath.isEmpty { return "Snapshot path not recorded" }
        return URL(fileURLWithPath: record.snapshotPath).lastPathComponent
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter
    }()
}

private struct BindingDetailsPanel: View {
    let binding: BackupBinding
    @State private var sourceSizeText = "Calculating…"

    private var attributes: [FileAttributeKey: Any] {
        (try? FileManager.default.attributesOfItem(atPath: binding.sourcePath)) ?? [:]
    }

    private var modifiedText: String {
        guard let date = attributes[.modificationDate] as? Date else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var backupCount: Int { binding.backupRecords.count }

    private var totalCopies: Int {
        binding.backupRecords.reduce(0) { $0 + max(1, $1.copyCount) }
    }

    private var snapshotCountText: String {
        "\(backupCount) snapshot\(backupCount == 1 ? "" : "s")"
    }

    private var backupSizeText: String {
        guard let bytes = binding.totalBackupBytes else { return "—" }
        var text = fileSizeText(bytes)
        if totalCopies > backupCount {
            text += " · \(totalCopies) copies"
        }
        return text
    }

    private var latestText: String {
        guard let latest = binding.lastBackupAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter.string(from: latest)
    }

    private var creatorsText: String {
        let names = BindingCreator.allCases
            .filter { binding.creators.contains($0) }
            .map(\.rawValue)
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.bindery(16, .semibold))

            sectionLabel("Backups")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                detailRow("Snapshots", snapshotCountText)
                detailRow("Backup size", backupSizeText)
                detailRow("Latest", latestText)
            }

            Divider().opacity(0.5)

            sectionLabel("Source")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                detailRow("Type", binding.kind.rawValue)
                detailCategoryRow(binding.category)
                detailRow("Creators", creatorsText)
                detailRow("Source size", sourceSizeText)
                detailRow("Modified", modifiedText)
            }

            VStack(alignment: .leading, spacing: 7) {
                pathRow("Source", path: binding.sourcePath)
                pathRow("Target", path: binding.destinationPath)
            }
        }
        .padding(18)
        .background(Color.appPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: binding.sourcePath) {
            guard !binding.sourcePath.isEmpty else { sourceSizeText = "Not set"; return }
            guard FileManager.default.fileExists(atPath: binding.sourcePath) else { sourceSizeText = "Unavailable"; return }
            sourceSizeText = await FolderSizeCache.shared.sizeText(for: binding.sourcePath) ?? "Unavailable"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.bindery(11.5, .semibold))
            .foregroundStyle(Color.appTertiaryText)
            .textCase(.uppercase)
            .padding(.top, 1)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.bindery(13.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.bindery(14))
                .foregroundStyle(Color.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }

    private func detailCategoryRow(_ category: String) -> some View {
        GridRow {
            Text("Category")
                .font(.bindery(13.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 104, alignment: .leading)
            HStack {
                CategoryTagView(category: category)
                Spacer()
            }
        }
    }

    private func pathRow(_ label: String, path: String) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Text(label)
                .font(.bindery(13.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 104, alignment: .leading)
            PathValueView(path: path)
                .lineLimit(1)
        }
    }
}

private struct DetailWideButtonStyle: ButtonStyle {
    var running = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(13, .bold))
            .foregroundStyle(Color.black.opacity(0.86))
            .lineLimit(1)
            .frame(width: 116, height: 36)
            .background {
                if running {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                } else {
                    Capsule()
                        .fill(Color.white)
                }
            }
            .overlay {
                if !running {
                    Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct DetailPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(13, .bold))
            .lineLimit(1)
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(Color.white, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct DetailUtilityButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let light = colorScheme == .light
        return configuration.label
            .font(.bindery(11, .semibold))
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(light ? Color.white.opacity(0.92) : Color.primary.opacity(0.07), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(light ? 0.10 : 0.0), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private struct DetailIconButtonStyle: ButtonStyle {
    var glass = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let light = colorScheme == .light
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(glass && light ? Color.black.opacity(0.70) : Color.primary.opacity(glass ? 0.86 : 0.72))
            .frame(width: 36, height: 36)
            .background(
                glass
                    ? (light ? Color.white.opacity(0.72) : Color.white.opacity(0.10))
                    : Color.primary.opacity(light ? 0.05 : 0.075),
                in: Circle()
            )
            .overlay {
                if glass {
                    Circle().strokeBorder(Color.white.opacity(light ? 0.75 : 0.12), lineWidth: 1)
                }
            }
            .shadow(color: glass && light ? .black.opacity(0.08) : .clear, radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

// MARK: - Editor

private struct BindingEditor: View {
    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    @State private var binding: BackupBinding
    @State private var showingIconPicker = false
    @State private var showingFormatHelp = false
    private let isNew: Bool
    let save: (BackupBinding) -> Void
    let cancel: () -> Void
    let delete: (() -> Void)?

    init(
        binding: BackupBinding,
        isNew: Bool = false,
        save: @escaping (BackupBinding) -> Void,
        cancel: @escaping () -> Void,
        delete: (() -> Void)? = nil
    ) {
        _binding = State(initialValue: binding)
        self.isNew = isNew
        self.save = save
        self.cancel = cancel
        self.delete = delete
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorSection("Basics")
                    editorRow("Mode") {
                        HStack(spacing: 7) {
                            editorChip("Fixed source", selected: !binding.isGenerator, help: "Bind one folder or file.") {
                                if binding.isGenerator {
                                    binding.kind = .folder
                                }
                            }
                            editorChip("Generator", selected: binding.isGenerator, help: "Accept any file or folder dropped on this card.") {
                                binding.kind = .generator
                                binding.sourcePath = ""
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    editorRow("Category") {
                        TextField("A/B", text: $binding.category)
                            .font(.bindery(14))
                            .textFieldStyle(.roundedBorder)
                    }
                    editorRow("Name") {
                        TextField("", text: $binding.name)
                            .font(.bindery(14))
                            .textFieldStyle(.roundedBorder)
                    }

                    editorSection("Source & Store")
                    if binding.isGenerator {
                        editorRow("Source") {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.draw")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.34))
                                Text("Drop any file or folder onto this card to create a snapshot.")
                                    .font(.bindery(12))
                                    .foregroundStyle(Color.primary.opacity(0.46))
                                Spacer()
                            }
                            .frame(height: 30)
                        }
                    } else {
                        editorRow("Source") {
                            PathEditorRow(path: $binding.sourcePath, choose: chooseSource)
                        }
                    }
                    editorRow("Store") {
                        editorStorePicker
                    }

                    editorSection("Snapshots")
                    backupOptions

                    editorSection("Appearance")
                    editorRow("Creator") {
                        HStack(spacing: 7) {
                            ForEach(BindingCreator.allCases) { creator in
                                let selected = binding.creators.contains(creator)
                                editorChip(creator.rawValue, selected: selected, help: "Toggle \(creator.rawValue)", icon: AnyView(
                                    CreatorIconView(creator: creator, size: 13, tint: selected ? .white : .adaptive)
                                )) {
                                    if selected {
                                        binding.creators.remove(creator)
                                    } else {
                                        binding.creators.insert(creator)
                                    }
                                }
                            }
                        }
                    }
                    editorRow("Cover") {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                                if let svg = binding.coverIconSVG {
                                    LucideIconView(svg: svg, size: 20)
                                } else {
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.22))
                                }
                            }
                            .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(binding.iconName ?? "No cover icon")
                                    .font(.bindery(12, .medium))
                                    .foregroundStyle(Color.primary.opacity(0.66))
                                    .lineLimit(1)
                                Text("Lucide icon shown on the folder paper")
                                    .font(.bindery(10.5))
                                    .foregroundStyle(Color.primary.opacity(0.30))
                            }
                            Spacer()
                            Button("Choose Lucide Icon…") { showingIconPicker = true }
                            if binding.iconName != nil || binding.iconSVG != nil {
                                Button("Remove") {
                                    binding.iconName = nil
                                    binding.iconSVG = nil
                                }
                            }
                        }
                    }
                    editorRow("Preview") {
                        HStack(spacing: 10) {
                            previewThumbnail
                            VStack(alignment: .leading, spacing: 1) {
                                Text(previewLabel)
                                    .font(.bindery(12, .medium))
                                    .foregroundStyle(Color.primary.opacity(0.66))
                                    .lineLimit(1)
                                Text("File preview; can be shown on the folder cover")
                                    .font(.bindery(10.5))
                                    .foregroundStyle(Color.primary.opacity(0.30))
                            }
                            Spacer()
                            Toggle("Show on cover", isOn: $binding.showPreviewOnCover)
                                .toggleStyle(.checkbox)
                                .font(.bindery(11.5, .medium))
                                .foregroundStyle(Color.primary.opacity(0.58))
                                .disabled(effectivePreviewFile(for: binding) == nil)
                                .help("Show the selected or default preview on the folder cover")
                            Button("Choose File…", action: choosePreview)
                            if hasCustomPreview {
                                Button("Remove") {
                                    if let legacy = binding.previewImagePath {
                                        PreviewImageStore.remove(path: legacy)
                                    }
                                    binding.previewImagePath = nil
                                    binding.previewFilePath = nil
                                }
                            }
                        }
                    }

                    editorSection("Note")
                    editorRow("Note") {
                        TextEditor(text: Binding(get: { binding.note ?? "" }, set: { binding.note = $0 }))
                            .font(.system(size: 14))
                            .frame(height: 62)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.visible)
            Divider().opacity(0.45)
            footer
        }
        .frame(width: 820, height: 820)
        .background(Color.appPanel)
        .sheet(isPresented: $showingIconPicker) {
            LucideIconPicker(
                selectedName: binding.iconName,
                onSelect: { name, svg in
                    binding.iconName = name
                    binding.iconSVG = svg
                    showingIconPicker = false
                },
                onRemove: {
                    binding.iconName = nil
                    binding.iconSVG = nil
                    showingIconPicker = false
                }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(isNew ? (binding.isGenerator ? "New Generator" : "New Project") : "Edit \(binding.isGenerator ? "Generator" : "Project")")
                    .font(.bindery(22, .bold))
                Text(binding.isGenerator
                     ? "Create a reusable generator. Drop any file or folder on its card to make a snapshot."
                     : "Bind a source to a backup store.")
                    .font(.bindery(12))
                    .foregroundStyle(Color.primary.opacity(0.38))
            }
            Spacer()
            FolderChip(binding: binding)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !isNew, let delete {
                Button("Delete…", role: .destructive, action: delete)
                    .font(.bindery(12, .medium))
                    .foregroundStyle(Color.appRed.opacity(0.90))
            }
            Spacer()
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button("Save") {
                if !binding.isGenerator { detectSourceKind() }
                if binding.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    binding.category = "Uncategorized"
                }
                if binding.filenameFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    binding.filenameFormat = BackupFilenameFormat.defaultFormat
                }
                if binding.storeID == nil { binding.storeID = state.stores.first?.id }
                if let store = state.store(for: binding) {
                    binding.storeID = store.id
                    binding.destinationPath = store.path
                }
                if binding.isGenerator {
                    binding.sourcePath = ""
                    binding.kind = .generator
                }
                if binding.kind == .file {
                    binding.compressBackups = false
                    binding.includeGitMetadata = false
                    binding.respectsGitignore = false
                }
                save(binding)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(binding.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || state.store(for: binding) == nil
                || (!binding.isGenerator && binding.sourcePath.isEmpty))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func editorSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.bindery(11.5, .semibold))
                .foregroundStyle(Color.appTertiaryText)
                .textCase(.uppercase)
            Divider().opacity(0.5)
        }
    }

    private var hasCustomPreview: Bool {
        if let path = binding.previewFilePath, !path.isEmpty { return true }
        if let path = binding.previewImagePath, !path.isEmpty { return true }
        return false
    }

    private var previewLabel: String {
        guard let file = effectivePreviewFile(for: binding) else { return "No preview file" }
        return hasCustomPreview ? file.lastPathComponent : "\(file.lastPathComponent) (default)"
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        let file = effectivePreviewFile(for: binding)
        let image = previewImage(for: binding)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let file {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.22))
            }
        }
        .frame(width: 58, height: 38)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var backupOptions: some View {
        VStack(alignment: .leading, spacing: 13) {
            editorRow("Options") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        if binding.kind == .file {
                            Text("Single files are copied as-is; ZIP compression applies to folders only.")
                                .font(.bindery(11))
                                .foregroundStyle(Color.primary.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            backupTag("Compress folders", isOn: $binding.compressBackups,
                                      help: "Store folder snapshots as a single .zip archive. Single files are always copied as-is.")
                            backupTag("Git history", isOn: $binding.includeGitMetadata,
                                      help: "Include the .git folder in folder snapshots.")
                            backupTag("Respect .gitignore", isOn: $binding.respectsGitignore,
                                      help: "Leave out files matched by .gitignore in folder snapshots.")
                        }
                        backupTag("Archive after first backup", isOn: $binding.archiveAfterFirstBackup,
                                  help: "Archive this binding after its first successful snapshot.")
                        Spacer(minLength: 0)
                    }
                }
            }

            editorRow("File name") {
                filenameRow
            }
        }
    }

    private func backupTag(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        editorChip(title, selected: isOn.wrappedValue, help: help) {
            isOn.wrappedValue.toggle()
        }
    }

    private func editorChip(_ title: String, selected: Bool, help: String, icon: AnyView? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    icon
                } else if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                }
                Text(title)
                    .font(.bindery(11.5, .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.60))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.055),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var filenameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("", text: $binding.filenameFormat)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button {
                    showingFormatHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.34))
                }
                .buttonStyle(.plain)
                .help(BackupFilenameFormat.helpText)
                .popover(isPresented: $showingFormatHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filename variables")
                            .font(.bindery(13, .semibold))
                            .foregroundStyle(Color.primary.opacity(0.86))
                            .padding(.bottom, 2)
                        ForEach(BackupFilenameFormat.variables, id: \.token) { variable in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(variable.token)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 86, alignment: .leading)
                                Text(variable.description)
                                    .font(.bindery(11))
                                    .foregroundStyle(Color.primary.opacity(0.52))
                            }
                        }
                        Divider().padding(.vertical, 2)
                        Text("Optional groups: [_{projectDate}] disappears when the source has no project date.")
                            .font(.bindery(10.5))
                            .foregroundStyle(Color.primary.opacity(0.40))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Example · \(BackupFilenameFormat.example(for: binding, style: appSettings.filenameStyle))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.34))
                    }
                    .padding(14)
                    .frame(width: 330)
                }
                Button("Reset") {
                    binding.filenameFormat = BackupFilenameFormat.defaultFormat
                }
                .buttonStyle(.plain)
                .font(.bindery(10.5, .medium))
                .foregroundStyle(Color.primary.opacity(0.36))
            }
            Text("Example · \(BackupFilenameFormat.example(for: binding, style: appSettings.filenameStyle))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.30))
                .lineLimit(1)
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.bindery(13.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
                .frame(width: 86, alignment: .leading)
            content()
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !binding.sourcePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: binding.sourcePath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            binding.sourcePath = url.path
            detectSourceKind()
            if binding.name.isEmpty { binding.name = url.deletingPathExtension().lastPathComponent }
        }
    }

    private func choosePreview() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        var isDirectory: ObjCBool = false
        if !binding.sourcePath.isEmpty,
           FileManager.default.fileExists(atPath: binding.sourcePath, isDirectory: &isDirectory) {
            let source = URL(fileURLWithPath: binding.sourcePath)
            panel.directoryURL = isDirectory.boolValue ? source : source.deletingLastPathComponent()
        } else if let current = effectivePreviewFile(for: binding) {
            panel.directoryURL = current.deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            binding.previewFilePath = url.path
            binding.previewImagePath = nil
        }
    }

    private func detectSourceKind() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: binding.sourcePath, isDirectory: &isDirectory) else { return }
        binding.kind = isDirectory.boolValue ? .folder : .file
        if !isDirectory.boolValue {
            binding.compressBackups = false
            binding.includeGitMetadata = false
            binding.respectsGitignore = false
        }
    }

    private var editorStorePicker: some View {
        HStack(spacing: 8) {
            if state.stores.isEmpty {
                Text("No store configured")
                    .font(.bindery(12))
                    .foregroundStyle(Color.primary.opacity(0.40))
                Button("Add Store…", action: addStoreFromEditor)
                    .font(.bindery(11.5, .medium))
            } else {
                Menu {
                    ForEach(state.stores) { store in
                        Button {
                            binding.storeID = store.id
                            binding.destinationPath = store.path
                        } label: {
                            HStack {
                                Text(store.name)
                                Text(store.isOnline ? "Online" : "Offline")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(selectedStore?.isOnline == true ? Color.appGreen : Color.appOrange)
                            .frame(width: 6, height: 6)
                        Text(selectedStore?.name ?? "Choose a store")
                            .font(.bindery(13, .medium))
                            .foregroundStyle(Color.primary.opacity(0.78))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.24))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Text(selectedStore == nil ? "" : presentPath(selectedStore?.path ?? "").short)
                    .font(.bindery(10.5))
                    .foregroundStyle(Color.primary.opacity(0.30))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var selectedStore: StoreRef? {
        guard let id = binding.storeID else { return nil }
        return state.stores.first { $0.id == id }
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func addStoreFromEditor() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Store"
        panel.message = "Choose a folder for Bindery snapshots."
        if panel.runModal() == .OK, let url = panel.url {
            state.addStore(at: url)
            if let store = state.stores.last {
                binding.storeID = store.id
                binding.destinationPath = store.path
            }
        }
    }
}

private struct FolderChip: View {
    let binding: BackupBinding
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        let palette = appSettings.palette(for: binding.tone, scheme: colorScheme)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.paperBottom)
                .frame(width: 54, height: 48)
            FolderFrontShape()
                .fill(LinearGradient(colors: [palette.frontTop, palette.frontBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 66, height: 34)
                .offset(y: 26)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .frame(width: 68, height: 58)
        .padding(.top, 4)
    }
}

// MARK: - Chrome

private struct StatusToast: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.bindery(12, .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 18)
        }
    }
}

private struct ScopeButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(14.5, .medium))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(Color.primary.opacity(selected ? 0.90 : 0.44))
            .background(Color.primary.opacity(selected ? 0.105 : 0.040), in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct TimelineResizeHandle: View {
    @Binding var width: Double
    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(hovering ? Color.accentColor.opacity(0.65) : Color.appBorder)
                .frame(width: hovering ? 2 : 1)
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = width }
                    let next = (dragStart ?? width) - value.translation.width
                    width = min(560, max(320, next))
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .onTapGesture(count: 2) {
            width = 360
        }
        .help("Drag to resize Timeline · double-click to reset")
    }
}

private struct ToolbarSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(0.62))
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : 0.052),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }
}

private struct ToolbarSegmentButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(selected ? 0.90 : 0.40))
            .background(
                selected ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct DragPreview: View {
    let binding: BackupBinding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: binding.kind.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.55))
            VStack(alignment: .leading, spacing: 1) {
                Text(binding.name.isEmpty ? "Untitled" : binding.name)
                    .font(.bindery(12, .semibold))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)
                Text(leafCategoryName(binding.category))
                    .font(.bindery(10))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 180, height: 44, alignment: .leading)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

private struct CategoryDropModifier: ViewModifier {
    let assign: (UUID) -> Void
    let move: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data, let string = String(data: data, encoding: .utf8) else { return }
                    if string.hasPrefix("category:") {
                        let dragged = String(string.dropFirst("category:".count))
                        DispatchQueue.main.async { move(dragged) }
                    } else if let id = UUID(uuidString: string) {
                        DispatchQueue.main.async { assign(id) }
                    }
                }
                return true
            }
    }
}

private struct CategoryRootDropModifier: ViewModifier {
    let move: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data, let string = String(data: data, encoding: .utf8),
                          string.hasPrefix("category:") else { return }
                    let path = String(string.dropFirst("category:".count))
                    DispatchQueue.main.async { move(path) }
                }
                return true
            }
    }
}

private struct CategoryDragPreview: View {
    let name: String
    let tone: CardTone

    var body: some View {
        HStack(spacing: 6) {
            CategoryFolderIcon(tone: tone, size: 12)
            Text(name)
                .font(.bindery(11, .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(width: 128, height: 26, alignment: .leading)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }
}

private struct CategoryFolderIcon: View {
    let tone: CardTone
    var size: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        let color = appSettings.baseColor(for: tone, scheme: colorScheme)
        ZStack {
            Image(systemName: "folder.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color.opacity(0.16))
            Image(systemName: "folder")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: 16)
    }
}

private struct SnapshotBindingDropModifier: ViewModifier {
    let assign: (Set<String>) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.60), lineWidth: 1.5)
                        }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data,
                          let string = String(data: data, encoding: .utf8),
                          string.hasPrefix("snapshots:") else { return }
                    let ids = string.dropFirst("snapshots:".count)
                        .split(separator: ",")
                        .map(String.init)
                    DispatchQueue.main.async { assign(Set(ids)) }
                }
                return true
            }
    }
}

private struct SidebarDropModifier: ViewModifier {
    let handler: ((UUID) -> Void)?
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if let handler {
            content
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                            }
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(
                    of: [UTType.plainText],
                    isTargeted: $isTargeted
                ) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        guard let data,
                              let string = String(data: data, encoding: .utf8),
                              let id = UUID(uuidString: string) else { return }
                        DispatchQueue.main.async {
                            handler(id)
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let colorScheme: ColorScheme?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        coordinator.install(on: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = NSColor.appWindowBackground
        window.hasShadow = true
        window.appearance = colorScheme == .light
            ? NSAppearance(named: .aqua)
            : colorScheme == .dark ? NSAppearance(named: .darkAqua) : nil
        DispatchQueue.main.async {
            insetTrafficLights(window)
        }
    }

    final class Coordinator {
        private var monitor: Any?

        func install(on window: NSWindow) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard event.window === window, event.clickCount == 2 else { return event }
                let point = event.locationInWindow
                let titlebarHeight = max(28, window.frame.height - window.contentLayoutRect.maxY)
                guard point.y >= window.frame.height - titlebarHeight - 4,
                      point.x > 86 else { return event }
                window.zoom(nil)
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    private func insetTrafficLights(_ window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        guard !buttons.isEmpty else { return }
        for button in buttons {
            var frame = button.frame
            frame.origin.x += 7
            frame.origin.y -= 4
            button.frame = frame
        }
    }
}
