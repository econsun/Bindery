import SwiftUI

struct SnapshotRenameSheet: View {
    @EnvironmentObject private var state: LibraryState
    let targets: Set<String>
    let style: FilenameStyle
    let apply: (String) -> Void
    let cancel: () -> Void

    @State private var format: String

    init(
        targets: Set<String>,
        initialFormat: String,
        style: FilenameStyle,
        apply: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.targets = targets
        self.style = style
        self.apply = apply
        self.cancel = cancel
        let trimmed = initialFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        _format = State(initialValue: trimmed.isEmpty ? BackupFilenameFormat.defaultFormat : trimmed)
    }

    private var previews: [SnapshotRenamePreview] {
        state.renamePreviews(targets, format: format, style: style)
    }

    private var changedCount: Int {
        previews.filter { $0.status == .changed }.count
    }

    private var conflictCount: Int {
        previews.filter { $0.status == .conflict }.count
    }

    private var unchangedCount: Int {
        previews.filter { $0.status == .unchanged }.count
    }

    private var unavailableCount: Int {
        previews.filter { $0.status == .unavailable }.count
    }

    private var canApply: Bool {
        changedCount > 0 && conflictCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rename \(targets.count) snapshot\(targets.count == 1 ? "" : "s")")
                        .font(.bindery(20, .bold))
                        .foregroundStyle(Color.primary.opacity(0.94))
                    Text("One format is applied to the whole selection. The permanent ID never changes.")
                        .font(.bindery(12.5))
                        .foregroundStyle(Color.primary.opacity(0.42))
                }
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Name format")
                    .font(.bindery(12, .semibold))
                    .foregroundStyle(Color.primary.opacity(0.48))
                TextField("", text: $format, prompt: Text(BackupFilenameFormat.defaultFormat).foregroundColor(Color.primary.opacity(0.26)))
                    .font(.system(size: 12.5, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                Text("{bindname}  {projectDate}  {backupDate}  {backupTime}  {id}  {XX}  {name}  {ext}")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.34))
                    .textSelection(.enabled)
                Text("[_{projectDate}] disappears when a snapshot has no project date. The ID is kept even if the format omits {id}.")
                    .font(.bindery(10.5))
                    .foregroundStyle(Color.primary.opacity(0.34))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.bindery(12, .semibold))
                        .foregroundStyle(Color.primary.opacity(0.48))
                    Spacer()
                    summary
                }
                previewList
            }

            HStack(spacing: 9) {
                if conflictCount > 0 {
                    Label(
                        "\(conflictCount) target name\(conflictCount == 1 ? "" : "s") already exist",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.bindery(11.5, .medium))
                    .foregroundStyle(Color.appRed.opacity(0.86))
                } else if changedCount == 0 {
                    Label("No names will change with this format", systemImage: "equal.circle")
                        .font(.bindery(11.5, .medium))
                        .foregroundStyle(Color.primary.opacity(0.42))
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(RenameSheetSecondaryButtonStyle())
                Button("Rename") {
                    apply(format)
                }
                .buttonStyle(RenameSheetPrimaryButtonStyle())
                .disabled(!canApply)
                .opacity(canApply ? 1 : 0.38)
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(Color.appPanel)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            if changedCount > 0 {
                Text("\(changedCount) ready")
                    .foregroundStyle(Color.appGreen.opacity(0.88))
            }
            if unchangedCount > 0 {
                Text("\(unchangedCount) unchanged")
                    .foregroundStyle(Color.primary.opacity(0.38))
            }
            if unavailableCount > 0 {
                Text("\(unavailableCount) offline")
                    .foregroundStyle(Color.appOrange.opacity(0.88))
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .monospacedDigit()
    }

    private var previewList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(previews) { preview in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(statusColor(preview.status))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.oldName)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.primary.opacity(0.42))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(preview.newName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.86))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(statusLabel(preview.status))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(statusColor(preview.status).opacity(0.86))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(statusColor(preview.status).opacity(0.10), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .padding(4)
        }
        .frame(height: min(264, CGFloat(max(1, previews.count)) * 46 + 8))
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func statusColor(_ status: SnapshotRenamePreview.Status) -> Color {
        switch status {
        case .changed: return Color.appGreen
        case .unchanged: return Color.primary.opacity(0.30)
        case .conflict: return Color.appRed
        case .unavailable: return Color.appOrange
        }
    }

    private func statusLabel(_ status: SnapshotRenamePreview.Status) -> String {
        switch status {
        case .changed: return "Rename"
        case .unchanged: return "No change"
        case .conflict: return "Exists"
        case .unavailable: return "Offline"
        }
    }
}

private struct RenameSheetPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(12, .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Color.accentColor, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct RenameSheetSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(12, .semibold))
            .foregroundStyle(Color.primary.opacity(0.62))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
