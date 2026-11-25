import AppKit
import SwiftUI

struct LucideIconPicker: View {
    let selectedName: String?
    let onSelect: (String, String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var link = ""
    @State private var isFetching = false
    @State private var errorText: String?
    @State private var hoveredName: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 6)

    private var filteredNames: [String] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return LucideCatalog.names }
        return LucideCatalog.names.filter {
            $0.replacingOccurrences(of: "-", with: " ").contains(term) || $0.contains(term)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Folder Icon")
                        .font(.bindery(21, .bold))
                    Text("Choose a Lucide icon, or paste any Lucide link.")
                        .font(.bindery(12))
                        .foregroundStyle(Color.primary.opacity(0.40))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.primary.opacity(0.30))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.34))
                TextField("Paste a lucide.dev link or icon name", text: $link)
                    .font(.bindery(12.5))
                    .textFieldStyle(.plain)
                    .onSubmit(useLink)
                Button(action: useLink) {
                    if isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Use Link")
                            .font(.bindery(11.5, .semibold))
                    }
                }
                .buttonStyle(IconPickerActionStyle())
                .disabled(isFetching || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Browse lucide.dev") {
                    if let url = URL(string: "https://lucide.dev/icons") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain)
                .font(.bindery(11))
                .foregroundStyle(Color.primary.opacity(0.38))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }

            if let errorText {
                Text(errorText)
                    .font(.bindery(11.5, .medium))
                    .foregroundStyle(Color(rgb: 0xE58A7D))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary.opacity(0.34))
                TextField("Search \(LucideCatalog.icons.count) built-in icons", text: $query)
                    .font(.bindery(12.5))
                    .textFieldStyle(.plain)
                Text("\(filteredNames.count)")
                    .font(.bindery(10.5, .medium))
                    .foregroundStyle(Color.primary.opacity(0.30))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(filteredNames, id: \.self) { name in
                        iconCell(name)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                if let selectedName, let svg = LucideCatalog.icons[selectedName] {
                    LucideIconView(svg: svg, size: 18)
                    Text(selectedName)
                        .font(.bindery(11.5, .medium))
                        .foregroundStyle(Color.primary.opacity(0.46))
                } else {
                    Text("No icon selected")
                        .font(.bindery(11.5, .medium))
                        .foregroundStyle(Color.primary.opacity(0.34))
                }
                Spacer()
                Button("Remove Icon") {
                    onRemove()
                    dismiss()
                }
                .buttonStyle(IconPickerActionStyle())
                Button("Done") { dismiss() }
                    .buttonStyle(IconPickerDoneStyle())
            }
        }
        .padding(22)
        .frame(width: 780, height: 640)
        .background(Color.appPanel)
    }

    private func iconCell(_ name: String) -> some View {
        let selected = name == selectedName
        return Button {
            if let svg = LucideCatalog.icons[name] {
                onSelect(name, svg)
                dismiss()
            }
        } label: {
            VStack(spacing: 6) {
                LucideIconView(svg: LucideCatalog.icons[name], size: 24)
                    .opacity(selected ? 1 : 0.88)
                Text(name.replacingOccurrences(of: "-", with: " "))
                    .font(.bindery(9, .medium))
                    .foregroundStyle(Color.primary.opacity(selected ? 0.90 : 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                selected ? Color.primary.opacity(0.13) : (hoveredName == name ? Color.primary.opacity(0.07) : Color.primary.opacity(0.035)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.26) : Color.primary.opacity(0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredName = name } else if hoveredName == name { hoveredName = nil }
        }
    }

    private func useLink() {
        let input = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isFetching else { return }
        isFetching = true
        errorText = nil
        Task {
            let result = await LucideFetcher.resolve(input)
            await MainActor.run {
                isFetching = false
                if let result {
                    onSelect(result.name, result.svg)
                    dismiss()
                } else {
                    errorText = "Could not find that icon. Use a lucide.dev icon link, an icon name, or check your connection."
                }
            }
        }
    }
}

private struct IconPickerActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .semibold))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.075), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct IconPickerDoneStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bindery(11.5, .bold))
            .foregroundStyle(Color.appPrimaryText)
            .padding(.horizontal, 15)
            .frame(height: 29)
            .background(Color.appPrimaryFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
