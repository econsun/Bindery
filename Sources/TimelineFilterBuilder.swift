import SwiftUI

enum TimelineMatchMode: String, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }
    var title: String { self == .all ? "All" : "Any" }
}

enum TimelineFilterField: String, Codable, CaseIterable, Identifiable {
    case type
    case level
    case actor
    case kind
    case title
    case summary
    case details
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Type"
        case .level: return "Level"
        case .actor: return "Actor"
        case .kind: return "Kind"
        case .title: return "Title"
        case .summary: return "Summary"
        case .details: return "Details"
        case .time: return "Time"
        }
    }

    var operators: [TimelineFilterOperator] {
        switch self {
        case .type, .level, .actor, .kind:
            return [.isExactly, .isNot]
        case .title, .summary, .details:
            return [.isExactly, .isNot, .contains, .doesNotContain, .startsWith, .endsWith, .isEmpty, .isNotEmpty]
        case .time:
            return [.before, .after, .between]
        }
    }

    var defaultOperator: TimelineFilterOperator {
        switch self {
        case .title, .summary, .details: return .contains
        case .time: return .between
        default: return .isExactly
        }
    }
}

enum TimelineFilterOperator: String, Codable, CaseIterable, Identifiable {
    case isExactly
    case isNot
    case contains
    case doesNotContain
    case startsWith
    case endsWith
    case isEmpty
    case isNotEmpty
    case before
    case after
    case between

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isExactly: return "is"
        case .isNot: return "is not"
        case .contains: return "contains"
        case .doesNotContain: return "does not contain"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .before: return "before"
        case .after: return "after"
        case .between: return "between"
        }
    }

    var requiresValue: Bool {
        self != .isEmpty && self != .isNotEmpty
    }
}

enum TimelineType: String, Codable, CaseIterable, Identifiable {
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

extension TimelineType {
    static var filterOptions: [TimelineType] {
        allCases.filter { $0 != .scan }
    }

    var tint: Color {
        switch self {
        case .backup: return Color.appGreen
        case .binding: return Color(rgb: 0xA855F7)
        case .snapshot: return Color(rgb: 0x3B82F6)
        case .category: return Color.appOrange
        case .store: return Color(rgb: 0x06B6D4)
        case .scan: return Color(rgb: 0x14B8A6)
        case .system: return Color.appGray
        case .unmanaged: return Color(rgb: 0xD97706)
        }
    }
}

extension ActivityKind {
    static var filterOptions: [ActivityKind] {
        allCases.filter { $0 != .scan && $0 != .backupStarted }
    }

    var displayTitle: String {
        switch self {
        case .appLaunch: return "App launched"
        case .scan: return "Stores scanned"
        case .backupStarted: return "Backup started"
        case .backupCompleted: return "Backup completed"
        case .backupFailed: return "Backup failed"
        case .bindingCreated: return "Binding created"
        case .bindingUpdated: return "Binding updated"
        case .bindingDeleted: return "Binding deleted"
        case .bindingArchived: return "Binding archived"
        case .bindingFavorite: return "Binding favorited"
        case .bindingCategory: return "Binding category changed"
        case .categoryCreated: return "Category created"
        case .categoryRenamed: return "Category renamed"
        case .categoryMoved: return "Category moved"
        case .categoryRemoved: return "Category removed"
        case .storeAdded: return "Store added"
        case .storeRemoved: return "Store removed"
        case .snapshotAssigned: return "Snapshot assigned"
        case .snapshotMovedStore: return "Snapshot moved store"
        case .snapshotRenamed: return "Snapshot renamed"
        case .snapshotDeleted: return "Snapshot deleted"
        case .snapshotVerified: return "Snapshot verified"
        case .unmanagedImported: return "File imported"
        case .unmanagedIgnored: return "File ignored"
        }
    }

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

struct TimelineFilterCondition: Codable, Identifiable, Equatable {
    var id = UUID()
    var field: TimelineFilterField = .type
    var operation: TimelineFilterOperator = .isExactly
    var text = ""
    var type: TimelineType = .backup
    var level: ActivityLevel = .normal
    var actor: ActivityActor = .user
    var kind: ActivityKind = .backupCompleted
    var start: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    var end: Date = Date()

    static func make(for field: TimelineFilterField) -> TimelineFilterCondition {
        var condition = TimelineFilterCondition()
        condition.field = field
        condition.operation = field.defaultOperator
        return condition
    }

    func matches(_ event: ActivityEvent) -> Bool {
        switch field {
        case .type:
            return compare(event.kind.timelineType == type)
        case .level:
            return compare(event.level == level)
        case .actor:
            return compare(event.actor == actor)
        case .kind:
            return compare(event.kind == kind)
        case .title:
            return textMatch(event.title)
        case .summary:
            return textMatch(event.summary)
        case .details:
            let text = event.details.keys.sorted()
                .map { "\($0): \(event.details[$0] ?? "")" }
                .joined(separator: "\n")
            return textMatch(text)
        case .time:
            switch operation {
            case .before: return event.timestamp < start
            case .after: return event.timestamp > start
            case .between: return event.timestamp >= start && event.timestamp <= end
            default: return true
            }
        }
    }

    private func compare(_ equal: Bool) -> Bool {
        operation == .isNot ? !equal : equal
    }

    private func textMatch(_ value: String) -> Bool {
        if operation == .isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if operation == .isNotEmpty {
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        switch operation {
        case .isExactly:
            return value.caseInsensitiveCompare(needle) == .orderedSame
        case .isNot:
            return value.caseInsensitiveCompare(needle) != .orderedSame
        case .contains:
            return value.localizedCaseInsensitiveContains(needle)
        case .doesNotContain:
            return !value.localizedCaseInsensitiveContains(needle)
        case .startsWith:
            return value.range(of: needle, options: [.caseInsensitive, .anchored]) != nil
        case .endsWith:
            return value.range(of: needle, options: [.caseInsensitive, .backwards, .anchored]) != nil
        case .isEmpty:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .isNotEmpty:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }
}

struct TimelineFilterBuilder: View {
    @Binding var conditions: [TimelineFilterCondition]
    @Binding var matchMode: TimelineMatchMode
    let done: () -> Void

    private var panelHeight: CGFloat {
        let dateExtra = conditions.reduce(CGFloat.zero) { partial, condition in
            partial + ((condition.field == .time && condition.operation == .between) ? 34 : 0)
        }
        return min(720, max(260, 194 + CGFloat(conditions.count) * 54 + dateExtra))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filters")
                        .font(.bindery(16, .semibold))
                    Text("Show events where the conditions below match.")
                        .font(.bindery(11))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            HStack(spacing: 10) {
                Text("Match")
                    .font(.bindery(12, .medium))
                    .foregroundStyle(Color.appSecondaryText)
                Picker("", selection: $matchMode) {
                    ForEach(TimelineMatchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                Text(matchMode == .all ? "All conditions must match" : "Any condition can match")
                    .font(.bindery(11))
                    .foregroundStyle(Color.appTertiaryText)
                Spacer()
            }

            if conditions.isEmpty {
                Text("No filter conditions. Every event is shown.")
                    .font(.bindery(12))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 7) {
                    Text("Field").frame(width: 92, alignment: .leading)
                    Text("Logic").frame(width: 118, alignment: .leading)
                    Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 14, height: 1)
                }
                .font(.bindery(9.5, .semibold))
                .foregroundStyle(Color.appTertiaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach($conditions) { $condition in
                                TimelineFilterConditionRow(
                                    condition: $condition,
                                    remove: {
                                        conditions.removeAll { $0.id == condition.id }
                                    }
                                )
                                .overlay(alignment: .bottom) {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: conditions.count) { _, _ in
                        guard let last = conditions.last else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 8) {
                Menu {
                    ForEach(TimelineFilterField.allCases) { field in
                        Button(field.title) {
                            conditions.append(.make(for: field))
                        }
                    }
                } label: {
                    Label("Add condition", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Button("Last 24 hours") { addRange(hours: 24) }
                    Button("Last 7 days") { addRange(days: 7) }
                    Button("Last 30 days") { addRange(days: 30) }
                } label: {
                    Label("Time range", systemImage: "calendar")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                if !conditions.isEmpty {
                    Button("Clear all") {
                        conditions.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.bindery(11, .medium))
                    .foregroundStyle(Color.appSecondaryText)
                }
            }
            .font(.bindery(11.5, .medium))

            Text("is = exact match · contains = text includes the value · empty operators need no value.")
                .font(.bindery(10))
                .foregroundStyle(Color.appTertiaryText)
        }
        .padding(16)
        .frame(width: 640, height: panelHeight)
        .background(Color.appBackground)
        .animation(.easeOut(duration: 0.18), value: conditions.count)
    }

    private func addRange(hours: Int) {
        var condition = TimelineFilterCondition.make(for: .time)
        condition.operation = .between
        condition.start = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
        condition.end = Date()
        conditions.append(condition)
    }

    private func addRange(days: Int) {
        var condition = TimelineFilterCondition.make(for: .time)
        condition.operation = .between
        condition.start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        condition.end = Date()
        conditions.append(condition)
    }
}

private struct TimelineFilterConditionRow: View {
    @Binding var condition: TimelineFilterCondition
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Picker("", selection: $condition.field) {
                    ForEach(TimelineFilterField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
                .help("Field to compare")

                Picker("", selection: $condition.operation) {
                    ForEach(condition.field.operators) { op in
                        Text(op.title).tag(op)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 118)
                .help("Comparison logic")

                if condition.operation.requiresValue {
                    valueControl
                } else {
                    Text("No value")
                        .font(.bindery(11))
                        .foregroundStyle(Color.appTertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.42))
                }
                .buttonStyle(.plain)
                .help("Remove condition")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .onChange(of: condition.field) { _, newField in
            if !newField.operators.contains(condition.operation) {
                condition.operation = newField.defaultOperator
            }
        }
    }

    @ViewBuilder
    private var valueControl: some View {
        switch condition.field {
        case .type:
            Picker("", selection: $condition.type) {
                ForEach(TimelineType.filterOptions) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        case .level:
            Picker("", selection: $condition.level) {
                ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                    Text(levelTitle(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        case .actor:
            Picker("", selection: $condition.actor) {
                Text("User").tag(ActivityActor.user)
                Text("System").tag(ActivityActor.system)
                Text("Scan").tag(ActivityActor.scan)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        case .kind:
            Picker("", selection: $condition.kind) {
                ForEach(ActivityKind.filterOptions, id: \.rawValue) { kind in
                    Text(kind.displayTitle).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        case .title, .summary, .details:
            TextField("Value", text: $condition.text)
                .textFieldStyle(.roundedBorder)
                .font(.bindery(11.5))
                .frame(maxWidth: .infinity)
        case .time:
            if condition.operation == .between {
                HStack(spacing: 5) {
                    datePicker($condition.start)
                    Text("to")
                        .font(.bindery(10.5))
                        .foregroundStyle(Color.appTertiaryText)
                    datePicker($condition.end)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                datePicker($condition.start)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(.bindery(10.5))
    }

    private func levelTitle(_ level: ActivityLevel) -> String {
        switch level {
        case .minor: return "Routine"
        case .normal: return "Normal"
        case .major: return "Major"
        case .error: return "Errors"
        }
    }
}
