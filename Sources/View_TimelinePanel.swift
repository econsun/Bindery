import AppKit
import Combine
import SwiftUI

struct TimelinePanel: View {
    var onClose: (() -> Void)? = nil

    @ObservedObject private var activity = ActivityLog.shared
    @AppStorage("timeline.filter") private var filterRaw = TimelineFilter.all.rawValue
    @AppStorage("timeline.types") private var typeFilterRaw = TimelineType.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("timeline.levels") private var levelFilterRaw = ActivityLevel.allCases.map(\.rawValue).joined(separator: ",")

    @State private var expanded: Set<UUID> = []
    @State private var now = Date()

    private var filter: TimelineFilter {
        TimelineFilter(rawValue: filterRaw) ?? .all
    }

    private var selectedTypes: Set<TimelineType> {
        Set(typeFilterRaw.split(separator: ",").compactMap { TimelineType(rawValue: String($0)) })
    }

    private var selectedLevels: Set<ActivityLevel> {
        Set(levelFilterRaw.split(separator: ",").compactMap { ActivityLevel(rawValue: String($0)) })
    }

    private var hasNarrowedTypes: Bool {
        selectedTypes != Set(TimelineType.allCases)
    }

    private var hasNarrowedLevels: Bool {
        selectedLevels != Set(ActivityLevel.allCases)
    }

    private var events: [ActivityEvent] {
        activity.events.filter { event in
            guard filter.matches(event) else { return false }
            guard selectedTypes.contains(event.kind.timelineType) else { return false }
            guard selectedLevels.contains(event.level) else { return false }
            return true
        }
    }

    private var days: [(day: Date, events: [ActivityEvent])] {
        let calendar = Calendar.current
        return Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp) }
            .map { (day: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider().opacity(0.45)
            if days.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.day) { group in
                            daySection(group)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appSidebar.opacity(0.62))
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Timeline")
                .font(.bindery(19, .semibold))
                .foregroundStyle(Color.primary.opacity(0.94))
            Spacer()
            Button {
                copyJSONL()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.50))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Copy visible events as JSONL")

            Button {
                activity.revealLogFile()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.50))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Reveal activity log")

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.50))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Hide Timeline")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(TimelineFilter.allCases) { item in
                Button(item.title) {
                    filterRaw = item.rawValue
                }
                .buttonStyle(TimelinePanelFilterStyle(selected: filter == item))
            }
            Spacer(minLength: 2)
            Menu {
                Section("Event types") {
                    ForEach(TimelineType.allCases) { type in
                        Button {
                            toggleType(type)
                        } label: {
                            if selectedTypes.contains(type) {
                                Label(type.title, systemImage: "checkmark")
                            } else {
                                Text(type.title)
                            }
                        }
                    }
                }
                Section("Levels") {
                    ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                        Button {
                            toggleLevel(level)
                        } label: {
                            if selectedLevels.contains(level) {
                                Label(levelTitle(level), systemImage: "checkmark")
                            } else {
                                Text(levelTitle(level))
                            }
                        }
                    }
                }
                Divider()
                Button("Show all types and levels") {
                    resetAdvancedFilters()
                }
            } label: {
                Image(systemName: hasNarrowedTypes || hasNarrowedLevels ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hasNarrowedTypes || hasNarrowedLevels ? Color.accentColor : Color.primary.opacity(0.42))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filter event types and levels")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 11)
    }

    private func daySection(_ group: (day: Date, events: [ActivityEvent])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dayLabel(group.day))
                .font(.bindery(12, .semibold))
                .foregroundStyle(Color.appSecondaryText)
                .padding(.leading, 3)
                .padding(.top, 11)
                .padding(.bottom, 3)

            ForEach(group.events) { event in
                TimelinePanelRow(
                    event: event,
                    isExpanded: expanded.contains(event.id),
                    now: now,
                    toggle: {
                        if expanded.contains(event.id) {
                            expanded.remove(event.id)
                        } else {
                            expanded.insert(event.id)
                        }
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.22))
            Text(activity.events.isEmpty ? "No activity yet" : "No matching events")
                .font(.bindery(13, .semibold))
                .foregroundStyle(Color.primary.opacity(0.74))
            Text(activity.events.isEmpty
                 ? "Backups and edits will appear here."
                 : "Try another filter or show routine events.")
                .font(.bindery(11.5))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func toggleType(_ type: TimelineType) {
        var set = selectedTypes
        if set.contains(type) { set.remove(type) } else { set.insert(type) }
        typeFilterRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func toggleLevel(_ level: ActivityLevel) {
        var set = selectedLevels
        if set.contains(level) { set.remove(level) } else { set.insert(level) }
        levelFilterRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func resetAdvancedFilters() {
        typeFilterRaw = TimelineType.allCases.map(\.rawValue).joined(separator: ",")
        levelFilterRaw = ActivityLevel.allCases.map(\.rawValue).joined(separator: ",")
    }

    private func levelTitle(_ level: ActivityLevel) -> String {
        switch level {
        case .minor: return "Routine"
        case .normal: return "Normal"
        case .major: return "Major"
        case .error: return "Errors"
        }
    }

    private func copyJSONL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activity.jsonLines(for: events), forType: .string)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private enum TimelineType: String, CaseIterable, Identifiable {
    case backup
    case binding
    case snapshot
    case category
    case store
    case scan
    case system
    case unmanaged

    var id: String { rawValue }
    var title: String {
        switch self {
        case .backup: return "Backups"
        case .binding: return "Bindings"
        case .snapshot: return "Snapshots"
        case .category: return "Categories"
        case .store: return "Stores"
        case .scan: return "Scans"
        case .system: return "System"
        case .unmanaged: return "Unmanaged"
        }
    }
}

private extension ActivityKind {
    var timelineType: TimelineType {
        switch self {
        case .backupStarted, .backupCompleted, .backupFailed:
            return .backup
        case .scan:
            return .scan
        case .storeAdded, .storeRemoved:
            return .store
        case .appLaunch:
            return .system
        case .bindingCreated, .bindingUpdated, .bindingDeleted, .bindingArchived,
             .bindingFavorite, .bindingCategory:
            return .binding
        case .categoryCreated, .categoryRenamed, .categoryMoved, .categoryRemoved:
            return .category
        case .unmanagedImported, .unmanagedIgnored:
            return .unmanaged
        case .snapshotAssigned, .snapshotMovedStore, .snapshotRenamed,
             .snapshotDeleted, .snapshotVerified:
            return .snapshot
        }
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case changes
    case backups
    case scans
    case errors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .changes: return "Changes"
        case .backups: return "Backups"
        case .scans: return "Scans"
        case .errors: return "Errors"
        }
    }

    func matches(_ event: ActivityEvent) -> Bool {
        switch self {
        case .all: return true
        case .changes: return event.kind.group == .change || event.kind.group == .store
        case .backups: return event.kind.group == .backup
        case .scans: return event.kind.group == .scan
        case .errors: return event.level == .error
        }
    }
}

private struct TimelinePanelRow: View {
    let event: ActivityEvent
    let isExpanded: Bool
    let now: Date
    let toggle: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var dotSize: CGFloat {
        switch event.level {
        case .major, .error: return 14
        case .normal: return 12
        case .minor: return 10
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.appTertiaryText)
                if let relativeTime {
                    Text(relativeTime)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .frame(width: 54, alignment: .trailing)
            .padding(.top, 9)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(tint.opacity(event.level == .minor ? 0.55 : 1))
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.appSidebar, lineWidth: event.level == .major || event.level == .error ? 2 : 0)
                    }
                    .padding(.top, 19 - dotSize / 2)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint.opacity(event.level == .minor ? 0.60 : 0.98))
                        .frame(width: 15)
                    Text(event.title)
                        .font(titleFont)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if event.actor != .user {
                        Text(event.actor.rawValue)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.appTertiaryText)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Spacer(minLength: 2)
                    if !event.details.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.34))
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(height: 24)

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.bindery(11.5))
                        .foregroundStyle(event.level == .minor ? Color.appTertiaryText : Color.appSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isExpanded {
                    details
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                isExpanded
                    ? Color.accentColor.opacity(0.055)
                    : (event.level == .major || event.level == .error
                       ? tint.opacity(event.level == .error ? 0.075 : 0.045)
                       : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .padding(.bottom, 2)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(event.details.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: 7) {
                    Text(key)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appTertiaryText)
                        .frame(width: 82, alignment: .leading)
                    Text(event.details[key] ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var relativeTime: String? {
        let interval = now.timeIntervalSince(event.timestamp)
        guard interval >= 0, interval < 86_400 else { return nil }
        if interval < 60 { return "now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3_600))h ago"
    }

    private var titleFont: Font {
        switch event.level {
        case .major, .error: return .bindery(13.5, .semibold)
        case .normal: return .bindery(12.5, .medium)
        case .minor: return .bindery(12)
        }
    }

    private var titleColor: Color {
        switch event.level {
        case .error: return Color.appRed.opacity(0.94)
        case .major: return Color.primary.opacity(0.92)
        case .normal: return Color.primary.opacity(0.80)
        case .minor: return Color.primary.opacity(0.58)
        }
    }

    private var tint: Color {
        switch event.kind.tintName {
        case "red": return Color.appRed
        case "green": return Color.appGreen
        case "orange": return Color.appOrange
        case "purple": return Color(rgb: 0xA855F7)
        case "blue": return Color(rgb: 0x3B82F6)
        case "cyan": return Color(rgb: 0x06B6D4)
        default: return Color.appGray
        }
    }
}

private struct TimelinePanelFilterStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(10.5, .medium))
            .foregroundStyle(selected ? Color.white : Color.appSecondaryText)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
