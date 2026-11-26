import AppKit
import FinderSync
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var state: LibraryState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var section: SettingsSection = .appearance
    @State private var paletteScheme: ColorScheme = .light
    @State private var previewTone: CardTone = .orange
    @State private var showingFormatHelp = false
    @State private var finderEnabled = false
    @State private var finderMessage = ""

    @AppStorage("sidebar.smartFolders") private var showSmartFolders = true
    @AppStorage("sidebar.categories") private var showCategories = true
    @AppStorage("sidebar.creators") private var showCreators = true
    @AppStorage("sidebar.types") private var showTypes = true
    @AppStorage("folderCardWidth") private var cardWidth: Double = 232

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case defaults = "New Binding"
        case storage = "Storage"
        case general = "General"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .appearance: return "paintpalette"
            case .defaults: return "slider.horizontal.3"
            case .storage: return "externaldrive"
            case .general: return "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.appBorder).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .padding(.horizontal, 28)
                        .padding(.top, 26)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.primary.opacity(0.045)).frame(height: 1)
                }
            }
        }
        .frame(width: 920, height: 700)
        .background(Color.appPanel)
        .onAppear {
            paletteScheme = colorScheme
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.bindery(24, .bold))
                .foregroundStyle(Color.primary.opacity(0.94))
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 18)

            ForEach(SettingsSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 18)
                        Text(item.rawValue)
                            .font(.bindery(13.5, section == item ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(Color.primary.opacity(section == item ? 0.92 : 0.58))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(
                        section == item ? Color.primary.opacity(0.075) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.bottom, 2)
            }

            Spacer()
            Text("Bindery · 2.0")
                .font(.bindery(10.5, .medium))
                .foregroundStyle(Color.primary.opacity(0.24))
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(width: 190)
        .background(Color.primary.opacity(0.022))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .appearance: appearanceContent
        case .defaults: defaultsContent
        case .storage: storageContent
        case .general: generalContent
        }
    }

    // MARK: Appearance

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Appearance")

            HStack(spacing: 8) {
                schemeButton(.light, icon: "sun.max", title: "Light")
                schemeButton(.dark, icon: "moon", title: "Dark")
                Spacer()
                Button("Reset Palette") {
                    settings.resetPalette(paletteScheme)
                }
                .buttonStyle(.plain)
                .font(.bindery(11, .medium))
                .foregroundStyle(Color.primary.opacity(0.38))
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Palette")
                        .font(.bindery(11.5, .semibold))
                        .foregroundStyle(Color.primary.opacity(0.32))
                        .padding(.leading, 2)

                    VStack(spacing: 0) {
                        ForEach(CardTone.allCases) { tone in
                            HStack(spacing: 12) {
                                ColorPicker("", selection: Binding(
                                    get: { settings.baseColor(for: tone, scheme: paletteScheme) },
                                    set: { settings.setBase($0, for: tone, scheme: paletteScheme) }
                                ), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 38)

                                Text(tone.rawValue)
                                    .font(.bindery(13, .medium))
                                    .foregroundStyle(Color.primary.opacity(previewTone == tone ? 0.94 : 0.72))
                                    .frame(width: 62, alignment: .leading)

                                Text(settings.baseColor(for: tone, scheme: paletteScheme).hexString)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.28))
                                Spacer()
                                if previewTone == tone {
                                    Image(systemName: "eye")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.30))
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 43)
                            .contentShape(Rectangle())
                            .onTapGesture { previewTone = tone }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.045))
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(CardTone.allCases) { tone in
                            Button {
                                previewTone = tone
                            } label: {
                                Circle()
                                    .fill(settings.baseColor(for: tone, scheme: paletteScheme))
                                    .frame(width: 19, height: 19)
                                    .overlay {
                                        Circle().strokeBorder(
                                            previewTone == tone ? Color.primary.opacity(0.88) : Color.primary.opacity(0.08),
                                            lineWidth: previewTone == tone ? 1.5 : 1
                                        )
                                    }
                                    .scaleEffect(previewTone == tone ? 1.12 : 1)
                            }
                            .buttonStyle(.plain)
                            .help(tone.rawValue)
                        }
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.028))
                        BindingFolderCard(binding: previewBinding, isRunning: false, forceOpen: false)
                            .scaleEffect(1.06)
                    }
                    .frame(width: 232, height: 266)
                    .environment(\.colorScheme, paletteScheme)
                    .environmentObject(settings)
                }
                .frame(width: 232)
            }
        }
    }

    private func schemeButton(_ scheme: ColorScheme, icon: String, title: String) -> some View {
        Button {
            paletteScheme = scheme
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.bindery(12, .medium))
            }
            .foregroundStyle(paletteScheme == scheme ? Color.primary.opacity(0.92) : Color.primary.opacity(0.46))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                paletteScheme == scheme ? Color.primary.opacity(0.085) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var previewBinding: BackupBinding {
        BackupBinding(
            name: "Preview",
            sourcePath: "/tmp/260312 Preview.pdf",
            destinationPath: "/tmp",
            storeID: UUID(),
            category: "Library/Design",
            creators: [.human],
            tone: previewTone,
            backupDates: [Date()],
            filenameFormat: settings.defaultFilenameFormat,
            projectDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 12))
        )
    }

    // MARK: New binding

    private var defaultsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("New Binding Defaults")

            settingsGroup("Backup") {
                HStack(spacing: 7) {
                    settingsTag("Compress folders", isOn: $settings.defaultCompressBackups)
                    settingsTag("Archive after first backup", isOn: $settings.defaultArchiveAfterFirst)
                    settingsTag("Git history", isOn: $settings.defaultIncludeGit)
                    settingsTag("Respect .gitignore", isOn: $settings.defaultRespectsGitignore)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            settingsGroup("File name") {
                fileNamerow
            }

            settingsGroup("Date & time formats") {
                settingsRow("Backup date", icon: "calendar") {
                    formatField($settings.backupDateFormat, width: 150)
                }
                settingsRow("Project date", icon: "calendar.badge.clock") {
                    formatField($settings.projectDateFormat, width: 150)
                }
                settingsRow("Time", icon: "clock") {
                    formatField($settings.timeFormat, width: 150)
                }
                settingsRow("Preview", icon: "textformat") {
                    Text(BackupFilenameFormat.example(for: previewBinding, style: settings.filenameStyle))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.46))
                        .lineLimit(1)
                }
            }

            settingsGroup("Defaults") {
                settingsRow("Category", icon: "folder") {
                    TextField("", text: $settings.defaultCategory)
                        .font(.bindery(12.5))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                settingsRow("Store", icon: "externaldrive") {
                    Text(state.stores.first?.name ?? "Choose in Storage")
                        .font(.bindery(12, .medium))
                        .foregroundStyle(Color.primary.opacity(0.56))
                }
                settingsRow("Creators", icon: "person.2") {
                    HStack(spacing: 6) {
                        ForEach(BindingCreator.allCases) { creator in
                            let selected = settings.defaultCreators.contains(creator)
                            settingsChip(creator.rawValue, selected: selected, icon: AnyView(
                                CreatorIconView(creator: creator, size: 12, tint: selected ? .white : .adaptive)
                            )) {
                                if selected { settings.defaultCreators.remove(creator) }
                                else { settings.defaultCreators.insert(creator) }
                            }
                        }
                    }
                }
                settingsRow("Cover preview", icon: "eye") {
                    Toggle("", isOn: $settings.defaultShowPreviewOnCover)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
    }

    private var fileNamerow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: $settings.defaultFilenameFormat)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button {
                    showingFormatHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.34))
                }
                .buttonStyle(.plain)
                .help(BackupFilenameFormat.helpText)
                .popover(isPresented: $showingFormatHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Filename variables")
                            .font(.bindery(13, .semibold))
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Optional groups")
                                .font(.bindery(11, .semibold))
                                .foregroundStyle(Color.primary.opacity(0.60))
                            Text("[_{projectDate}] disappears when the source has no project date, so no doubled underscore is left behind.")
                                .font(.bindery(10.5))
                                .foregroundStyle(Color.primary.opacity(0.40))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                Button("Reset") {
                    settings.defaultFilenameFormat = BackupFilenameFormat.defaultFormat
                }
                .buttonStyle(.plain)
                .font(.bindery(10.5, .medium))
                .foregroundStyle(Color.primary.opacity(0.36))
            }
            Text("Example · \(BackupFilenameFormat.example(for: previewBinding, style: settings.filenameStyle))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.30))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Storage

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Storage")

            settingsGroup("Stores") {
                if state.stores.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No stores yet")
                                .font(.bindery(13, .semibold))
                                .foregroundStyle(Color.primary.opacity(0.72))
                            Text("Choose a folder. Bindery keeps its catalog in a hidden .bindery directory and never hides the snapshots themselves.")
                                .font(.bindery(11))
                                .foregroundStyle(Color.primary.opacity(0.36))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button("Add Store…", action: chooseStore)
                    }
                    .padding(14)
                } else {
                    ForEach(state.stores) { store in
                        storeRow(store)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: chooseStore) {
                        Label("Add Store…", systemImage: "plus")
                            .font(.bindery(12, .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary.opacity(0.62))

                    Spacer()

                    Button {
                        state.scan(trigger: .manual)
                    } label: {
                        HStack(spacing: 6) {
                            if state.isScanning {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(state.isScanning ? "Scanning…" : "Scan Now")
                                .font(.bindery(12, .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .disabled(state.isScanning)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if !state.externalCollections.isEmpty {
                settingsGroup("External systems") {
                    ForEach(state.externalCollections) { external in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.055))
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.48))
                            }
                            .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(external.label)
                                    .font(.bindery(13, .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.80))
                                Text("\(external.kind) · \(external.relativePath)")
                                    .font(.bindery(11))
                                    .foregroundStyle(Color.primary.opacity(0.34))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            Text("Skipped")
                                .font(.bindery(10, .semibold))
                                .foregroundStyle(Color.primary.opacity(0.30))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.045))
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                    }
                }
            }

            settingsGroup("Scanning") {
                settingsRow("Scan at launch", icon: "power") {
                    Toggle("", isOn: $settings.rescanOnLaunch)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                settingsRow("Last scan", icon: "clock") {
                    Text(lastScanText)
                        .font(.bindery(12, .medium))
                        .foregroundStyle(Color.primary.opacity(0.56))
                        .monospacedDigit()
                }
                if let report = state.scanReport {
                    settingsRow("Last result", icon: "checklist") {
                        Text(report.summary)
                            .font(.bindery(12, .medium))
                            .foregroundStyle(Color.primary.opacity(0.56))
                            .lineLimit(1)
                    }
                }
            }

            Text("A store owns its own catalog. If the drive is not connected, Bindery still shows the last known records and marks them offline.")
                .font(.bindery(11))
                .foregroundStyle(Color.primary.opacity(0.32))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var lastScanText: String {
        guard let date = state.stores.compactMap(\.lastScanAt).max() else { return "Not scanned yet" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }

    private func storeRow(_ store: StoreRef) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(store.isOnline ? Color.appGreen : Color.appOrange)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(store.name)
                        .font(.bindery(13, .semibold))
                        .foregroundStyle(Color.primary.opacity(0.84))
                    Text(store.isOnline ? "Online" : "Offline")
                        .font(.bindery(10, .semibold))
                        .foregroundStyle(store.isOnline ? Color.appGreen : Color.appOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((store.isOnline ? Color.appGreen : Color.appOrange).opacity(0.10), in: Capsule())
                }
                Text(shortened(store.path))
                    .font(.bindery(11))
                    .foregroundStyle(Color.primary.opacity(0.34))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text("\(state.snapshotCount(for: store.id))")
                .font(.bindery(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.48))

            Button {
                state.removeStore(store)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.28))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Remove this store reference. Files are never deleted.")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.045))
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }

    private func chooseStore() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Store"
        panel.message = "Choose a folder for Bindery snapshots. The folder can be on an external drive."
        if panel.runModal() == .OK, let url = panel.url {
            state.addStore(at: url)
        }
    }

    // MARK: General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("General")

            settingsGroup("Library") {
                settingsRow("Default view", icon: "square.grid.2x2") {
                    GlassSegmented(
                        options: [(LibraryViewMode.grid, "Grid", "square.grid.2x2"), (LibraryViewMode.list, "List", "list.bullet")],
                        selection: $settings.defaultViewMode
                    )
                }
                settingsRow("Smart folder sort", icon: "clock.arrow.circlepath") {
                    GlassMenu(options: LibrarySort.allCases.map { ($0, $0.rawValue) }, selection: $settings.defaultSmartSort)
                }
                settingsRow("Category sort", icon: "folder") {
                    GlassMenu(options: LibrarySort.allCases.map { ($0, $0.rawValue) }, selection: $settings.defaultCategorySort)
                }
                settingsRow("Time range", icon: "clock") {
                    GlassMenu(options: TimeScope.allCases.map { ($0, $0.rawValue) }, selection: $settings.defaultScope)
                }
            }

            settingsGroup("Finder") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(finderEnabled ? Color.appGreen : Color.appOrange)
                            .frame(width: 7, height: 7)
                        Text(finderEnabled ? "Finder extension enabled" : "Finder extension needs permission")
                            .font(.bindery(12.5, .medium))
                            .foregroundStyle(Color.primary.opacity(0.86))
                        Spacer()
                    }
                    Text("Adds **Use Bindery** to the Finder right-click menu for files and folders: send them to Unmanaged or back them up into a binding.")
                        .font(.bindery(11.5))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(finderEnabled ? "Open Finder Settings" : "Enable Finder Extension") {
                            if finderEnabled {
                                openFinderExtensionSettings()
                            } else {
                                enableFinderExtension()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        if !finderEnabled {
                            Button("Open Finder Settings") { openFinderExtensionSettings() }
                                .buttonStyle(.plain)
                                .font(.bindery(11.5, .medium))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if !finderMessage.isEmpty {
                            Text(finderMessage)
                                .font(.bindery(10.5))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                }
                .padding(14)
            }

            settingsGroup("Appearance") {
                settingsRow("Launch appearance", icon: "circle.lefthalf.filled") {
                    GlassSegmented(
                        options: [(LaunchAppearance.system, "System", "circle.lefthalf.filled"), (LaunchAppearance.light, "Light", "sun.max"), (LaunchAppearance.dark, "Dark", "moon")],
                        selection: $settings.launchAppearance
                    )
                }
            }

            settingsGroup("Sidebar") {
                settingsRow("Visible sections", icon: "sidebar.left") {
                    HStack(spacing: 6) {
                        sidebarChip("Smart Folders", isOn: $showSmartFolders)
                        sidebarChip("Categories", isOn: $showCategories)
                        sidebarChip("Creators", isOn: $showCreators)
                        sidebarChip("Types", isOn: $showTypes)
                    }
                }
            }

            settingsGroup("Cards") {
                settingsRow("Card size", icon: "rectangle.portrait") {
                    HStack(spacing: 10) {
                        Slider(value: $cardWidth, in: 180...300)
                            .frame(width: 200)
                        Text("\(Int(cardWidth)) pt")
                            .font(.bindery(11, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(0.36))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

        }
    }

    private func refreshFinderStatus() {
        finderEnabled = FIFinderSyncController.isExtensionEnabled
    }

    private func enableFinderExtension() {
        let appex = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/BinderyFinder.appex")
        _ = runPluginkit(["-a", appex.path])
        _ = runPluginkit(["-e", "use", "-i", "com.econsun.bindery.finder"])
        refreshFinderStatus()
        if finderEnabled {
            finderMessage = "Enabled"
        } else {
            finderMessage = "Open Finder Settings to allow it"
        }
    }

    private func runPluginkit(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func openFinderExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func sidebarChip(_ title: String, isOn: Binding<Bool>) -> some View {
        settingsChip(title, selected: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
    }

    private func formatField(_ value: Binding<String>, width: CGFloat) -> some View {
        TextField("yyMMdd", text: value)
            .font(.system(size: 11.5, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
    }

    // MARK: Components

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.bindery(22, .bold))
            .foregroundStyle(Color.primary.opacity(0.94))
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.bindery(11.5, .semibold))
                .foregroundStyle(Color.primary.opacity(0.32))
                .padding(.leading, 2)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func settingsRow<Content: View>(_ label: String, icon: String? = nil, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 11) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.50))
                }
                .frame(width: 28, height: 28)
            }
            Text(label)
                .font(.bindery(13, .medium))
                .foregroundStyle(Color.primary.opacity(0.82))
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.045))
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }

    private func settingsTag(_ title: String, isOn: Binding<Bool>) -> some View {
        settingsChip(title, selected: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
    }

    private func settingsChip(_ title: String, selected: Bool, icon: AnyView? = nil, action: @escaping () -> Void) -> some View {
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
            .frame(height: 27)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.055),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(selected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func shortened(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}


private struct GlassSegmented<Option: Hashable>: View {
    let options: [(Option, String, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                Button {
                    selection = item.0
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.2)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.1)
                            .font(.bindery(11.5, .medium))
                    }
                    .foregroundStyle(selection == item.0 ? Color.primary.opacity(0.90) : Color.primary.opacity(0.42))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        selection == item.0 ? Color.appElevated : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        if selection == item.0 {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        }
    }
}

private struct GlassMenu<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    private var currentLabel: String {
        options.first { $0.0 == selection }?.1 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                Button {
                    selection = item.0
                } label: {
                    if selection == item.0 {
                        Label(item.1, systemImage: "checkmark")
                    } else {
                        Text(item.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.bindery(12, .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color.primary.opacity(0.68))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
