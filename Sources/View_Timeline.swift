import AppKit
import Combine
import SwiftUI

struct TimelineView: View {
    @ObservedObject private var activity = ActivityLog.shared
    let search: String

    @State private var filter: TimelineFilter = .all
    @State private var expanded: Set<UUID> = []
    @State private var selectedID: UUID?
    @State private var contentWidth: CGFloat = 0
    @State private var now = Date()

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleEvents: [ActivityEvent] {
        activity.events.filter { event in
            filter.matches(event)
                && (query.isEmpty || event.searchText.localizedCaseInsensitiveContains(query))
        }
    }

    private var days: [(day: Date, events: [ActivityEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleEvents) { calendar.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (day: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
    }

    private var selectedEvent: ActivityEvent? {
        if let selectedID, let event = activity.events.first(where: { $0.id == selectedID }) {
            return event
        }
        return visibleEvents.first
    }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 26) {
                    timelineColumn
                    inspector
                        .frame(width: 360)
                }
                .frame(minWidth: 1240)

                timelineColumn
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if abs(width - contentWidth) > 1 { contentWidth = width }
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var isWide: Bool { contentWidth >= 1240 }

    private var timelineColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            filterBar
            if days.isEmpty {
                emptyState
            } else {
                ForEach(days, id: \.day) { group in
                    daySection(group)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Timeline")
                    .font(.bindery(34, .bold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                Text("\(visibleEvents.count) event\(visibleEvents.count == 1 ? "" : "s") · persistent JSONL activity log")
                    .font(.bindery(15, .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 8) {
                    Button {
                        copyJSONL()
                    } label: {
                        Label("Copy JSONL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(TimelineHeaderButtonStyle())

                    Button {
                        activity.revealLogFile()
                    } label: {
                        Label("Reveal Log", systemImage: "folder")
                    }
                    .buttonStyle(TimelineHeaderButtonStyle())
                }
                Text(presentPath(ActivityLog.logURL.path).short)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.appTertiaryText)
                    .lineLimit(1)
                    .help(ActivityLog.logURL.path)
            }
            .padding(.top, 3)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(TimelineFilter.allCases) { item in
                Button(item.title) {
                    filter = item
                }
                .buttonStyle(TimelineFilterButtonStyle(selected: filter == item))
            }
            Spacer()
            if !expanded.isEmpty {
                Button("Collapse details") {
                    expanded.removeAll()
                }
                .buttonStyle(.plain)
                .font(.bindery(11.5, .medium))
                .foregroundStyle(Color.appSecondaryText)
            }
        }
        .padding(.top, 2)
    }

    private func daySection(_ group: (day: Date, events: [ActivityEvent])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(dayLabel(group.day))
                    .font(.bindery(13, .semibold))
                    .foregroundStyle(Color.primary.opacity(0.54))
                Text("\(group.events.count)")
                    .font(.bindery(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.appTertiaryText)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 5)

            VStack(spacing: 0) {
                ForEach(group.events) { event in
                    TimelineEventRow(
                        event: event,
                        isSelected: selectedEvent?.id == event.id,
                        isExpanded: expanded.contains(event.id),
                        canExpand: !isWide,
                        now: now,
                        select: { selectedID = event.id },
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
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.22))
            Text(activity.events.isEmpty ? "No activity yet" : "No matching events")
                .font(.bindery(16, .semibold))
                .foregroundStyle(Color.primary.opacity(0.80))
            Text(activity.events.isEmpty
                 ? "Backups, edits, moves, deletes, and scans will appear here as a durable timeline."
                 : "Try another search or filter.")
                .font(.bindery(12.5))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private var inspector: some View {
        if let event = selectedEvent {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("EVENT")
                        .font(.bindery(10.5, .semibold))
                        .foregroundStyle(Color.appTertiaryText)
                        .tracking(0.7)
                    Spacer()
                    Text(activityDateLabel(event.timestamp))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.appTertiaryText)
                }

                HStack(spacing: 7) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.level == .error ? Color.appRed : Color.accentColor)
                    Text(event.kind.rawValue)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appSecondaryText)
                    Spacer()
                }

                Text(event.title)
                    .font(.bindery(17, .semibold))
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.bindery(12.5))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    inspectorChip(event.level.rawValue, tint: event.level == .error ? .appRed : .appSecondaryText)
                    inspectorChip(event.actor.rawValue, tint: .appTertiaryText)
                }

                Divider().opacity(0.55)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(event.details.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.appTertiaryText)
                            Text(event.details[key] ?? "")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.appSecondaryText)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 5)
                        if key != event.details.keys.sorted().last {
                            Divider().opacity(0.35)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        copyText(activity.jsonLines(for: [event]))
                    } label: {
                        Label("Copy Event", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(TimelineHeaderButtonStyle())

                    Button {
                        copyText(event.details.keys.sorted().map { "\($0): \(event.details[$0] ?? "")" }.joined(separator: "\n"))
                    } label: {
                        Label("Copy Details", systemImage: "list.bullet")
                    }
                    .buttonStyle(TimelineHeaderButtonStyle())
                }
            }
            .padding(16)
            .background(Color.appPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.22))
                Text("Select an event")
                    .font(.bindery(13, .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private func inspectorChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private func activityDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyJSONL() {
        let text = activity.jsonLines(for: visibleEvents)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

private struct TimelineEventRow: View {
    let event: ActivityEvent
    let isSelected: Bool
    let isExpanded: Bool
    let canExpand: Bool
    let now: Date
    let select: () -> Void
    let toggle: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appTertiaryText)
                if let relativeTime {
                    Text(relativeTime)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .frame(width: 64, alignment: .trailing)
            .padding(.top, 3)

            timelineRail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint.opacity(event.level == .minor ? 0.55 : 0.95))
                        .frame(width: 16)
                    Text(event.title)
                        .font(titleFont)
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                    if event.actor != .user {
                        Text(event.actor.rawValue)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.appTertiaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    if canExpand && !event.details.isEmpty {
                        Button(action: toggle) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(0.45))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.bindery(12))
                        .foregroundStyle(event.level == .minor ? Color.appTertiaryText : Color.appSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isExpanded && canExpand {
                    details
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.055)
                    : (event.level == .major || event.level == .error
                       ? tint.opacity(event.level == .error ? 0.075 : 0.045)
                       : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(alignment: .topLeading) {
                dot
                    .offset(x: -17, y: event.level == .minor ? 13 : 12)
            }
            .padding(.bottom, 2)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            select()
            if canExpand && !event.details.isEmpty { toggle() }
        }
    }

    private var timelineRail: some View {
        Color.clear
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.primary.opacity(0.09))
                    .frame(width: 1)
            }
    }

    private var dot: some View {
        Circle()
            .fill(tint.opacity(event.level == .minor ? 0.50 : 0.95))
            .frame(width: dotSize, height: dotSize)
            .overlay {
                Circle()
                    .strokeBorder(Color.appBackground, lineWidth: event.level == .major || event.level == .error ? 2 : 0)
            }
    }

    private var relativeTime: String? {
        let interval = now.timeIntervalSince(event.timestamp)
        guard interval >= 0, interval < 86_400 else { return nil }
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60)) min ago" }
        return "\(Int(interval / 3_600)) hr ago"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(event.details.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: 8) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appTertiaryText)
                        .frame(width: 108, alignment: .leading)
                    Text(event.details[key] ?? "")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var titleFont: Font {
        switch event.level {
        case .major: return .bindery(14, .semibold)
        case .error: return .bindery(14, .semibold)
        case .normal: return .bindery(13, .medium)
        case .minor: return .bindery(13)
        }
    }

    private var titleColor: Color {
        switch event.level {
        case .error: return Color.appRed.opacity(0.92)
        case .major: return Color.primary.opacity(0.92)
        case .normal: return Color.primary.opacity(0.80)
        case .minor: return Color.primary.opacity(0.58)
        }
    }

    private var dotSize: CGFloat {
        switch event.level {
        case .major, .error: return 8
        case .normal: return 6
        case .minor: return 4
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
        default: return Color.primary.opacity(0.55)
        }
    }
}

private struct TimelineHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .semibold))
            .foregroundStyle(Color.primary.opacity(0.62))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct TimelineFilterButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .medium))
            .foregroundStyle(selected ? Color.white : Color.appSecondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
