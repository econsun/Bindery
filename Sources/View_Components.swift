import SwiftUI

func fileSizeText(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}

struct StatusDotText: View {
    let text: String
    let color: Color
    var font: Font = .bindery(13.5, .medium)

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct PathValueView: View {
    let path: String
    var showProvider = true

    private var presentation: PathPresentation { presentPath(path) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: presentation.space.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 16)
            Text(presentation.space == .none ? "Not set" : presentation.short)
                .font(.bindery(12.5))
                .foregroundStyle(Color.primary.opacity(0.70))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .help(presentation.path.isEmpty ? "No path selected" : presentation.path)
    }
}

struct PathEditorRow: View {
    @Binding var path: String
    let choose: () -> Void
    @State private var expanded = false

    private var presentation: PathPresentation { presentPath(path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: presentation.space.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 17)
                Text(presentation.path.isEmpty ? "Not set" : presentation.short)
                    .font(.bindery(12.5))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(expanded ? "Done" : "Edit") { expanded.toggle() }
                    .font(.bindery(11, .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                Button("Choose…", action: choose)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)

            if expanded {
                TextField("", text: $path)
                    .font(.bindery(12.5))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 46)
            .scaleEffect(visible ? 1 : 0.93, anchor: .bottom)
            .onAppear {
                withAnimation(
                    .spring(response: 0.58, dampingFraction: 0.78)
                    .delay(min(Double(index) * 0.045, 0.48))
                ) {
                    visible = true
                }
            }
    }
}

extension View {
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}

struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.42),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
                .padding(18)
            VStack(spacing: 9) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24, weight: .medium))
                Text("Drop to create a binding")
                    .font(.bindery(15, .semibold))
                Text("Folders and files are both supported")
                    .font(.bindery(12))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
