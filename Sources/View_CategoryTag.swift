import SwiftUI

struct CategoryTagView: View {
    let category: String

    @EnvironmentObject private var state: LibraryState
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        appSettings.baseColor(for: state.categoryColor(category), scheme: colorScheme)
    }

    var body: some View {
        Text(leafCategoryName(category))
            .font(.bindery(10.5, .medium))
            .foregroundStyle(Color.primary.opacity(0.82))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            }
            .help(category)
    }
}
