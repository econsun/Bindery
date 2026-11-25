import AppKit
import SwiftUI

final class AppSettings: ObservableObject {
    static let lightDefaults: [String: String] = [
        "Slate": "#AEB6C2", "Red": "#E89A8C", "Orange": "#F0B36F",
        "Yellow": "#E6CF6B", "Green": "#94C9A2", "Cyan": "#85C9C3",
        "Blue": "#8FB4E0", "Purple": "#BCA4DC", "Pink": "#E8A5BD"
    ]
    static let legacyLightDefaults: [String: String] = [
        "Slate": "#DBDFE4", "Red": "#F3C8BF", "Orange": "#F8D3AC",
        "Yellow": "#F7E6A8", "Green": "#C3E8CA", "Cyan": "#B6E8E4",
        "Blue": "#B9D3F1", "Purple": "#DCCCF2", "Pink": "#F5C9D8"
    ]
    static let darkDefaults: [String: String] = [
        "Slate": "#4B5563", "Red": "#DC2626", "Orange": "#EA580C",
        "Yellow": "#CA8A04", "Green": "#16A34A", "Cyan": "#0891B2",
        "Blue": "#2563EB", "Purple": "#9333EA", "Pink": "#DB2777"
    ]

    @Published var lightBases: [String: String] { didSet { save() } }
    @Published var darkBases: [String: String] { didSet { save() } }

    @Published var defaultCompressBackups = false { didSet { save() } }
    @Published var defaultArchiveAfterFirst = false { didSet { save() } }
    @Published var defaultIncludeGit = true { didSet { save() } }
    @Published var defaultRespectsGitignore = false { didSet { save() } }
    @Published var defaultShowPreviewOnCover = true { didSet { save() } }
    @Published var defaultFilenameFormat = BackupFilenameFormat.defaultFormat { didSet { save() } }
    @Published var backupDateFormat = "yyMMdd" { didSet { save() } }
    @Published var projectDateFormat = "yyMMdd" { didSet { save() } }
    @Published var timeFormat = "HHmmss" { didSet { save() } }
    @Published var defaultCreators: Set<BindingCreator> = [.human] { didSet { save() } }
    @Published var defaultViewMode: LibraryViewMode = .grid { didSet { save() } }
    @Published var defaultCategory = "Uncategorized" { didSet { save() } }
    @Published var defaultDestinationPath = "" { didSet { save() } }
    @Published var defaultSort: LibrarySort = .name { didSet { save() } }
    @Published var defaultScope: TimeScope = .all { didSet { save() } }
    @Published var launchAppearance: LaunchAppearance = .system { didSet { save() } }
    @Published var rescanOnLaunch = true { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        let storedLight = d.dictionary(forKey: Keys.lightBases) as? [String: String]
        if let storedLight, storedLight == Self.legacyLightDefaults {
            lightBases = Self.lightDefaults
        } else {
            lightBases = storedLight ?? Self.lightDefaults
        }
        darkBases = (d.dictionary(forKey: Keys.darkBases) as? [String: String]) ?? Self.darkDefaults
        defaultCompressBackups = d.object(forKey: Keys.compress) as? Bool ?? false
        defaultArchiveAfterFirst = d.object(forKey: Keys.archiveFirst) as? Bool ?? false
        defaultIncludeGit = d.object(forKey: Keys.includeGit) as? Bool ?? true
        defaultRespectsGitignore = d.object(forKey: Keys.gitignore) as? Bool ?? false
        defaultShowPreviewOnCover = d.object(forKey: Keys.showPreview) as? Bool ?? true
        defaultFilenameFormat = BackupFilenameFormat.normalize(d.string(forKey: Keys.filenameFormat))
        backupDateFormat = d.string(forKey: Keys.backupDateFormat) ?? "yyMMdd"
        projectDateFormat = d.string(forKey: Keys.projectDateFormat) ?? "yyMMdd"
        timeFormat = d.string(forKey: Keys.timeFormat) ?? "HHmmss"
        if let raw = d.array(forKey: Keys.creators) as? [String] {
            defaultCreators = Set(raw.compactMap(BindingCreator.init(rawValue:)))
        } else {
            defaultCreators = [.human]
        }
        defaultViewMode = d.string(forKey: Keys.viewMode).flatMap(LibraryViewMode.init(rawValue:)) ?? .grid
        defaultCategory = d.string(forKey: Keys.category) ?? "Uncategorized"
        defaultDestinationPath = d.string(forKey: Keys.destination) ?? ""
        defaultSort = d.string(forKey: Keys.sort).flatMap(LibrarySort.init(rawValue:)) ?? .name
        defaultScope = d.string(forKey: Keys.scope).flatMap(TimeScope.init(rawValue:)) ?? .all
        launchAppearance = d.string(forKey: Keys.launchAppearance).flatMap(LaunchAppearance.init(rawValue:)) ?? .system
        rescanOnLaunch = d.object(forKey: Keys.rescan) as? Bool ?? true
    }

    func baseColor(for tone: CardTone, scheme: ColorScheme) -> Color {
        let map = scheme == .light ? lightBases : darkBases
        return Color(hex: map[tone.rawValue] ?? (scheme == .light ? Self.lightDefaults : Self.darkDefaults)[tone.rawValue] ?? "#808080")
    }

    func setBase(_ color: Color, for tone: CardTone, scheme: ColorScheme) {
        let hex = color.hexString
        if scheme == .light {
            lightBases[tone.rawValue] = hex
        } else {
            darkBases[tone.rawValue] = hex
        }
    }

    var launchColorScheme: ColorScheme? {
        switch launchAppearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func palette(for tone: CardTone, scheme: ColorScheme) -> FolderPalette {
        FolderPalette.derived(from: baseColor(for: tone, scheme: scheme), scheme: scheme)
    }

    func resetPalette(_ scheme: ColorScheme) {
        if scheme == .light { lightBases = Self.lightDefaults }
        else { darkBases = Self.darkDefaults }
    }

    var filenameStyle: FilenameStyle {
        FilenameStyle(
            dateFormat: backupDateFormat.isEmpty ? "yyMMdd" : backupDateFormat,
            projectDateFormat: projectDateFormat.isEmpty ? backupDateFormat : projectDateFormat,
            timeFormat: timeFormat.isEmpty ? "HHmmss" : timeFormat
        )
    }

    private func save() {
        defaults.set(lightBases, forKey: Keys.lightBases)
        defaults.set(darkBases, forKey: Keys.darkBases)
        defaults.set(defaultCompressBackups, forKey: Keys.compress)
        defaults.set(defaultArchiveAfterFirst, forKey: Keys.archiveFirst)
        defaults.set(defaultIncludeGit, forKey: Keys.includeGit)
        defaults.set(defaultRespectsGitignore, forKey: Keys.gitignore)
        defaults.set(defaultShowPreviewOnCover, forKey: Keys.showPreview)
        defaults.set(defaultFilenameFormat, forKey: Keys.filenameFormat)
        defaults.set(backupDateFormat, forKey: Keys.backupDateFormat)
        defaults.set(projectDateFormat, forKey: Keys.projectDateFormat)
        defaults.set(timeFormat, forKey: Keys.timeFormat)
        defaults.set(defaultCreators.map(\.rawValue), forKey: Keys.creators)
        defaults.set(defaultViewMode.rawValue, forKey: Keys.viewMode)
        defaults.set(defaultCategory, forKey: Keys.category)
        defaults.set(defaultDestinationPath, forKey: Keys.destination)
        defaults.set(defaultSort.rawValue, forKey: Keys.sort)
        defaults.set(defaultScope.rawValue, forKey: Keys.scope)
        defaults.set(launchAppearance.rawValue, forKey: Keys.launchAppearance)
        defaults.set(rescanOnLaunch, forKey: Keys.rescan)
    }

    private enum Keys {
        static let lightBases = "Bindery.PaletteLight"
        static let darkBases = "Bindery.PaletteDark"
        static let compress = "Bindery.DefaultCompress"
        static let archiveFirst = "Bindery.DefaultArchiveFirst"
        static let includeGit = "Bindery.DefaultIncludeGit"
        static let gitignore = "Bindery.DefaultRespectsGitignore"
        static let showPreview = "Bindery.DefaultShowPreview"
        static let filenameFormat = "Bindery.DefaultFilenameFormat"
        static let backupDateFormat = "Bindery.BackupDateFormat"
        static let projectDateFormat = "Bindery.ProjectDateFormat"
        static let timeFormat = "Bindery.TimeFormat"
        static let creators = "Bindery.DefaultCreators"
        static let viewMode = "Bindery.DefaultViewMode"
        static let category = "Bindery.DefaultCategory"
        static let destination = "Bindery.DefaultDestination"
        static let sort = "Bindery.DefaultSort"
        static let scope = "Bindery.DefaultScope"
        static let launchAppearance = "Bindery.LaunchAppearance"
        static let rescan = "Bindery.RescanOnLaunch"
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}


enum LaunchAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
