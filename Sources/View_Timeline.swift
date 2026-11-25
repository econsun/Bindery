import AppKit
import SwiftUI

struct TimelineView: View {
    @ObservedObject private var activity = ActivityLog.shared
    let search: String

    @State private var filter: TimelineFilter = .all
    @State private var expanded: Set<UUID> = []

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

    var body: some View {
        ScrollView {
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
            .padding(.horizontal, 30)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Timeline")
                    .font(.bindery(34, .bold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                Text("\(visibleEvents.count) event\(visibleEvents.count == 1 ? "" : "s") · persistent JSONL activity log")
                    .font(.bindery(15, .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
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
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.26))
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
                .font(.bindery(11, .medium))
                .foregroundStyle(Color.primary.opacity(0.36))
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
                    .font(.bindery(10.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.26))
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 5)

            VStack(spacing: 0) {
                ForEach(group.events) { event in
                    TimelineEventRow(
                        event: event,
                        isExpanded: expanded.contains(event.id),
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
                .font(.bindery(12))
                .foregroundStyle(Color.primary.opacity(0.38))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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
    let isExpanded: Bool
    let toggle: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.28))
                .frame(width: 54, alignment: .trailing)
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
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.26))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    if !event.details.isEmpty {
                        Button(action: toggle) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(0.26))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.bindery(11.5))
                        .foregroundStyle(Color.primary.opacity(event.level == .minor ? 0.30 : 0.46))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isExpanded {
                    details
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                event.level == .major || event.level == .error
                    ? tint.opacity(event.level == .error ? 0.075 : 0.045)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .padding(.bottom, 2)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if !event.details.isEmpty { toggle() }
        }
    }

    private var timelineRail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Circle()
                .fill(tint.opacity(event.level == .minor ? 0.45 : 0.95))
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    Circle()
                        .strokeBorder(Color.appBackground, lineWidth: event.level == .major || event.level == .error ? 2 : 0)
                }
                .padding(.top, 5)
        }
        .frame(width: 14)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(event.details.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: 8) {
                    Text(key)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.30))
                        .frame(width: 104, alignment: .leading)
                    Text(event.details[key] ?? "")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.54))
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
        case .minor: return .bindery(12.5)
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
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.54))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
