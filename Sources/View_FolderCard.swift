import AppKit
import SwiftUI

// MARK: - Typography

extension Font {
    static func bindery(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Palette

struct FolderPalette {
    let frontTop: Color
    let frontBottom: Color
    let paperTop: Color
    let paperBottom: Color
    let backTop: Color
    let backBottom: Color
    let accent: Color
    let ink: Color
    let artInk: Color
}

extension FolderPalette {
    static func derived(from base: Color, scheme: ColorScheme) -> FolderPalette {
        if scheme == .light {
            return FolderPalette(
                frontTop: base,
                frontBottom: base.mixed(with: .black, amount: 0.10),
                paperTop: base.mixed(with: .white, amount: 0.95),
                paperBottom: base.mixed(with: .white, amount: 0.88),
                backTop: base.mixed(with: .white, amount: 0.72),
                backBottom: base.mixed(with: .white, amount: 0.62),
                accent: base.mixed(with: .black, amount: 0.15),
                ink: base.mixed(with: .black, amount: 0.78),
                artInk: base.mixed(with: .black, amount: 0.68)
            )
        }
        return FolderPalette(
            frontTop: base,
            frontBottom: base.mixed(with: .black, amount: 0.16),
            paperTop: base.mixed(with: .white, amount: 0.90),
            paperBottom: base.mixed(with: .white, amount: 0.82),
            backTop: base.mixed(with: .black, amount: 0.55),
            backBottom: base.mixed(with: .black, amount: 0.68),
            accent: base.mixed(with: .white, amount: 0.25),
            ink: .white,
            artInk: .white
        )
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Color {
    func mixed(with other: Color, amount: CGFloat) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let t = max(0, min(1, amount))
        return Color(nsColor: NSColor(
            srgbRed: a.redComponent * (1 - t) + b.redComponent * t,
            green: a.greenComponent * (1 - t) + b.greenComponent * t,
            blue: a.blueComponent * (1 - t) + b.blueComponent * t,
            alpha: 1
        ))
    }
}

extension CardTone {
    var palette: FolderPalette { palette(for: .dark) }

    func palette(for scheme: ColorScheme) -> FolderPalette {
        let base = scheme == .light ? lightPalette : darkPalette
        if scheme == .light {
            return FolderPalette(
                frontTop: base.frontTop.mixed(with: darkPalette.frontTop, amount: 0.30),
                frontBottom: base.frontBottom.mixed(with: darkPalette.frontBottom, amount: 0.30),
                paperTop: base.paperTop, paperBottom: base.paperBottom,
                backTop: base.backTop, backBottom: base.backBottom,
                accent: base.accent, ink: base.ink, artInk: base.artInk
            )
        } else {
            let neutral = Color(rgb: 0xAEB6C2)
            return FolderPalette(
                frontTop: base.frontTop.mixed(with: neutral, amount: 0.16),
                frontBottom: base.frontBottom.mixed(with: neutral, amount: 0.16),
                paperTop: base.paperTop, paperBottom: base.paperBottom,
                backTop: base.backTop, backBottom: base.backBottom,
                accent: base.accent, ink: base.ink, artInk: base.artInk
            )
        }
    }

    private var darkPalette: FolderPalette {
        switch self {
        case .slate:
            return FolderPalette(
                frontTop: Color(rgb: 0x4B5563), frontBottom: Color(rgb: 0x374151),
                paperTop: Color(rgb: 0xE5E7EB), paperBottom: Color(rgb: 0xD1D5DB),
                backTop: Color(rgb: 0x374151), backBottom: Color(rgb: 0x1F2937),
                accent: Color(rgb: 0x9CA3AF), ink: .white, artInk: .white
            )
        case .red:
            return FolderPalette(
                frontTop: Color(rgb: 0xDC2626), frontBottom: Color(rgb: 0xB91C1C),
                paperTop: Color(rgb: 0xFEE2E2), paperBottom: Color(rgb: 0xFECACA),
                backTop: Color(rgb: 0x7F1D1D), backBottom: Color(rgb: 0x5F1515),
                accent: Color(rgb: 0xF87171), ink: .white, artInk: .white
            )
        case .orange:
            return FolderPalette(
                frontTop: Color(rgb: 0xEA580C), frontBottom: Color(rgb: 0xC2410C),
                paperTop: Color(rgb: 0xFFEDD5), paperBottom: Color(rgb: 0xFED7AA),
                backTop: Color(rgb: 0x7C2D12), backBottom: Color(rgb: 0x5C210C),
                accent: Color(rgb: 0xFB923C), ink: .white, artInk: .white
            )
        case .yellow:
            return FolderPalette(
                frontTop: Color(rgb: 0xCA8A04), frontBottom: Color(rgb: 0xA16207),
                paperTop: Color(rgb: 0xFEF9C3), paperBottom: Color(rgb: 0xFEF08A),
                backTop: Color(rgb: 0x713F12), backBottom: Color(rgb: 0x4D2D0A),
                accent: Color(rgb: 0xFACC15), ink: .white, artInk: .white
            )
        case .green:
            return FolderPalette(
                frontTop: Color(rgb: 0x16A34A), frontBottom: Color(rgb: 0x15803D),
                paperTop: Color(rgb: 0xDCFCE7), paperBottom: Color(rgb: 0xBBF7D0),
                backTop: Color(rgb: 0x14532D), backBottom: Color(rgb: 0x0B3B1E),
                accent: Color(rgb: 0x4ADE80), ink: .white, artInk: .white
            )
        case .cyan:
            return FolderPalette(
                frontTop: Color(rgb: 0x0891B2), frontBottom: Color(rgb: 0x0E7490),
                paperTop: Color(rgb: 0xCFFAFE), paperBottom: Color(rgb: 0xA5F3FC),
                backTop: Color(rgb: 0x164E63), backBottom: Color(rgb: 0x0E3A4A),
                accent: Color(rgb: 0x22D3EE), ink: .white, artInk: .white
            )
        case .blue:
            return FolderPalette(
                frontTop: Color(rgb: 0x2563EB), frontBottom: Color(rgb: 0x1D4ED8),
                paperTop: Color(rgb: 0xDBEAFE), paperBottom: Color(rgb: 0xBFDBFE),
                backTop: Color(rgb: 0x1E3A8A), backBottom: Color(rgb: 0x172554),
                accent: Color(rgb: 0x60A5FA), ink: .white, artInk: .white
            )
        case .purple:
            return FolderPalette(
                frontTop: Color(rgb: 0x9333EA), frontBottom: Color(rgb: 0x7E22CE),
                paperTop: Color(rgb: 0xF3E8FF), paperBottom: Color(rgb: 0xE9D5FF),
                backTop: Color(rgb: 0x4C1D95), backBottom: Color(rgb: 0x3B1574),
                accent: Color(rgb: 0xC084FC), ink: .white, artInk: .white
            )
        case .pink:
            return FolderPalette(
                frontTop: Color(rgb: 0xDB2777), frontBottom: Color(rgb: 0xBE185D),
                paperTop: Color(rgb: 0xFCE7F3), paperBottom: Color(rgb: 0xFBCFE8),
                backTop: Color(rgb: 0x831843), backBottom: Color(rgb: 0x5C122F),
                accent: Color(rgb: 0xF472B6), ink: .white, artInk: .white
            )
        }
    }

    private var lightPalette: FolderPalette {
        switch self {
        case .slate:
            return FolderPalette(
                frontTop: Color(rgb: 0xDBDFE4), frontBottom: Color(rgb: 0xC4C9D1),
                paperTop: Color(rgb: 0xFAFBFC), paperBottom: Color(rgb: 0xE9EBEF),
                backTop: Color(rgb: 0xE0E4E8), backBottom: Color(rgb: 0xCDD2D8),
                accent: Color(rgb: 0x8A9099), ink: Color(rgb: 0x22262C), artInk: Color(rgb: 0x363C44)
            )
        case .red:
            return FolderPalette(
                frontTop: Color(rgb: 0xF3C8BF), frontBottom: Color(rgb: 0xE4ABA0),
                paperTop: Color(rgb: 0xFFF7F4), paperBottom: Color(rgb: 0xF4DFD9),
                backTop: Color(rgb: 0xEAD3CD), backBottom: Color(rgb: 0xDBC0B9),
                accent: Color(rgb: 0xCB796B), ink: Color(rgb: 0x3B211C), artInk: Color(rgb: 0x5B342C)
            )
        case .orange:
            return FolderPalette(
                frontTop: Color(rgb: 0xF8D3AC), frontBottom: Color(rgb: 0xEDBB8E),
                paperTop: Color(rgb: 0xFFF9F2), paperBottom: Color(rgb: 0xF4E4D0),
                backTop: Color(rgb: 0xECD7C0), backBottom: Color(rgb: 0xDCC3A8),
                accent: Color(rgb: 0xCE9152), ink: Color(rgb: 0x3A2A1B), artInk: Color(rgb: 0x5A4029)
            )
        case .yellow:
            return FolderPalette(
                frontTop: Color(rgb: 0xF7E6A8), frontBottom: Color(rgb: 0xEAD47A),
                paperTop: Color(rgb: 0xFFFDF2), paperBottom: Color(rgb: 0xF7EFCF),
                backTop: Color(rgb: 0xE9E0C2), backBottom: Color(rgb: 0xD8CBA8),
                accent: Color(rgb: 0xC6A23A), ink: Color(rgb: 0x3A300F), artInk: Color(rgb: 0x5A4A14)
            )
        case .green:
            return FolderPalette(
                frontTop: Color(rgb: 0xC3E8CA), frontBottom: Color(rgb: 0x9FD0AA),
                paperTop: Color(rgb: 0xF5FCF6), paperBottom: Color(rgb: 0xDCF0E1),
                backTop: Color(rgb: 0xD7EADB), backBottom: Color(rgb: 0xBFDCC5),
                accent: Color(rgb: 0x5D9C6B), ink: Color(rgb: 0x1D3322), artInk: Color(rgb: 0x2B4D33)
            )
        case .cyan:
            return FolderPalette(
                frontTop: Color(rgb: 0xB6E8E4), frontBottom: Color(rgb: 0x93CFCA),
                paperTop: Color(rgb: 0xF2FCFB), paperBottom: Color(rgb: 0xD8EFED),
                backTop: Color(rgb: 0xCEE8E5), backBottom: Color(rgb: 0xB4D4D1),
                accent: Color(rgb: 0x4B9D98), ink: Color(rgb: 0x173331), artInk: Color(rgb: 0x24514E)
            )
        case .blue:
            return FolderPalette(
                frontTop: Color(rgb: 0xB9D3F1), frontBottom: Color(rgb: 0x94B5DE),
                paperTop: Color(rgb: 0xF3F9FF), paperBottom: Color(rgb: 0xDCEAFB),
                backTop: Color(rgb: 0xD4E2F2), backBottom: Color(rgb: 0xB9CCE2),
                accent: Color(rgb: 0x6791C4), ink: Color(rgb: 0x1E2C3B), artInk: Color(rgb: 0x2E4258)
            )
        case .purple:
            return FolderPalette(
                frontTop: Color(rgb: 0xDCCCF2), frontBottom: Color(rgb: 0xC4B0DF),
                paperTop: Color(rgb: 0xFAF7FF), paperBottom: Color(rgb: 0xEADEF9),
                backTop: Color(rgb: 0xE1D5EE), backBottom: Color(rgb: 0xCFC0E1),
                accent: Color(rgb: 0x9878C2), ink: Color(rgb: 0x2C213C), artInk: Color(rgb: 0x41305A)
            )
        case .pink:
            return FolderPalette(
                frontTop: Color(rgb: 0xF5C9D8), frontBottom: Color(rgb: 0xE6ACBF),
                paperTop: Color(rgb: 0xFFF6FA), paperBottom: Color(rgb: 0xF4DDE6),
                backTop: Color(rgb: 0xEDD5DE), backBottom: Color(rgb: 0xDDC0CB),
                accent: Color(rgb: 0xD083A0), ink: Color(rgb: 0x3B2230), artInk: Color(rgb: 0x5E3548)
            )
        }
    }

    var color: Color { palette.frontBottom }

    var swatch: Color {
        switch self {
        case .slate: return Color(rgb: 0x9CA3AF)
        case .red: return Color(rgb: 0xEF4444)
        case .orange: return Color(rgb: 0xF59E0B)
        case .yellow: return Color(rgb: 0xEAB308)
        case .green: return Color(rgb: 0x22C55E)
        case .cyan: return Color(rgb: 0x06B6D4)
        case .blue: return Color(rgb: 0x3B82F6)
        case .purple: return Color(rgb: 0xA855F7)
        case .pink: return Color(rgb: 0xEC4899)
        }
    }

    var nsColor: NSColor { NSColor(swatch) }
}

// MARK: - Size cache

actor FolderSizeCache {
    static let shared = FolderSizeCache()

    private var cache: [String: String] = [:]

    func sizeText(for path: String) async -> String? {
        guard !path.isEmpty else { return nil }
        if let cached = cache[path] { return cached }
        let text = await Task.detached(priority: .utility) {
            FolderSizeCache.compute(path)
        }.value
        cache[path] = text
        return text
    }

    private nonisolated static func compute(_ path: String) -> String? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            guard let attributes = try? manager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return nil }
            return format(size.int64Value)
        }

        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return format(total)
    }

    private nonisolated static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Glyphs

struct FolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let topLeftRadius = width * 0.082
        let topRightRadius = width * 0.070
        let bottomRadius = width * 0.095
        let highEnd = width * 0.470
        let lowStart = width * 0.620
        let lowY = height * 0.130

        var path = Path()
        path.move(to: CGPoint(x: topLeftRadius, y: 0))
        path.addLine(to: CGPoint(x: highEnd, y: 0))
        path.addCurve(
            to: CGPoint(x: lowStart, y: lowY),
            control1: CGPoint(x: highEnd + width * 0.060, y: 0),
            control2: CGPoint(x: lowStart - width * 0.030, y: lowY)
        )
        path.addLine(to: CGPoint(x: width - topRightRadius, y: lowY))
        path.addQuadCurve(
            to: CGPoint(x: width, y: lowY + topRightRadius),
            control: CGPoint(x: width, y: lowY)
        )
        path.addLine(to: CGPoint(x: width, y: height - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: width - bottomRadius, y: height),
            control: CGPoint(x: width, y: height)
        )
        path.addLine(to: CGPoint(x: bottomRadius, y: height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: height - bottomRadius),
            control: CGPoint(x: 0, y: height)
        )
        path.addLine(to: CGPoint(x: 0, y: topLeftRadius))
        path.addQuadCurve(
            to: CGPoint(x: topLeftRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Cover art

struct CoverPreviewImage: View {
    let path: String?
    var cornerRadius: CGFloat = 13

    var body: some View {
        if let image = PreviewImageStore.image(at: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        }
    }
}

// MARK: - Folder card

struct BindingFolderCard: View {
    static let designWidth: CGFloat = 220
    static let designHeight: CGFloat = 242

    let binding: BackupBinding
    let isRunning: Bool
    var forceOpen = false

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    @State private var hovering = false

    private enum Metrics {
        static let width = BindingFolderCard.designWidth
        static let height = BindingFolderCard.designHeight
        static let frontTop: CGFloat = 100
        static let frontHeight: CGFloat = 142
        static let openShift: CGFloat = 13
        static let paperWidth: CGFloat = 200
        static let paperHeight: CGFloat = 216
        static let paperTop: CGFloat = 0
        static let paperRadius: CGFloat = 22
        static let backWidth: CGFloat = 200
        static let backHeight: CGFloat = 216
        static let backTop: CGFloat = 26
        static let backRadius: CGFloat = 18
    }

    private var isOpen: Bool { hovering || forceOpen }
    private var palette: FolderPalette { appSettings.palette(for: binding.tone, scheme: colorScheme) }

    private var statusText: String {
        backupCardStatusText(for: binding, isRunning: isRunning)
    }

    private var backupSummaryText: String? {
        let count = binding.backupRecords.count
        guard count > 0 else { return nil }
        var text = "\(count) backup\(count == 1 ? "" : "s")"
        if let bytes = binding.totalBackupBytes {
            text += " · \(fileSizeText(bytes))"
        }
        return text
    }

    private var statusDot: Color {
        if isRunning { return Color.appGreen }
        if binding.isArchived { return Color.appRed }
        if binding.storeID == nil || binding.destinationPath.isEmpty { return Color.appOrange }
        if !binding.destinationExists { return Color.appRed }
        if !binding.isGenerator && (binding.sourcePath.isEmpty || !binding.sourceExists) { return Color.appRed }
        if binding.lastBackupAt == nil { return Color.appGray }
        return Color.appGreen
    }


    var body: some View {
        ZStack(alignment: .top) {
            ambientGlow
            paperPanel
            frontPanel
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .animation(.spring(response: 0.46, dampingFraction: 0.80), value: isOpen)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(binding.name), \(statusText), \(binding.category)")
    }

    private var ambientGlow: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [palette.frontBottom.opacity(isOpen ? 0.26 : 0.10), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 150
                )
            )
            .frame(width: Metrics.width - 16, height: Metrics.height - 44)
            .offset(y: 34)
    }

    private var backPanel: some View {
        RoundedRectangle(cornerRadius: Metrics.backRadius, style: .continuous)
            .fill(
                LinearGradient(colors: [palette.backTop, palette.backBottom], startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.backRadius, style: .continuous)
                    .strokeBorder(palette.ink.opacity(0.06), lineWidth: 1)
            }
            .frame(width: Metrics.backWidth, height: Metrics.backHeight)
            .offset(y: Metrics.backTop)
            .shadow(color: .black.opacity(0.30), radius: 9, y: 6)
    }

    private var paperPanel: some View {
        ZStack(alignment: .top) {
            paperSurface

            if !showsCoverPreview {
                coverArt
                    .padding(.top, 5)
                    .offset(y: isOpen ? Metrics.openShift : 0)
            }
        }
        .frame(
            width: Metrics.paperWidth,
            height: Metrics.paperHeight + (isOpen ? Metrics.openShift : 0)
        )
        .offset(y: Metrics.paperTop)
        .shadow(color: .black.opacity(isOpen ? 0.30 : 0.20), radius: isOpen ? 12 : 8, y: isOpen ? 5 : 3)
    }

    private var showsCoverPreview: Bool {
        binding.showPreviewOnCover && effectivePreviewFile(for: binding) != nil
    }

    @ViewBuilder
    private var paperSurface: some View {
        ZStack(alignment: .top) {
            if !showsCoverPreview {
                paperBackground
            }
            if showsCoverPreview, let file = effectivePreviewFile(for: binding) {
                FileCoverThumbnail(url: file, direct: previewImage(for: binding))
                    .frame(
                        width: Metrics.paperWidth,
                        height: Metrics.paperHeight + (isOpen ? Metrics.openShift : 0)
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    private var paperBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous)
            .fill(LinearGradient(colors: [palette.paperTop, palette.paperBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.22), .clear],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 150
                        )
                    )
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.black.opacity(0.10)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.paperRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var coverArt: some View {
        if let svg = binding.coverIconSVG {
            LucideIconView(svg: svg, size: 44, tint: .adaptive)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                .frame(width: Metrics.paperWidth - 20, height: 74, alignment: .center)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private var frontTopOpacity: Double {
        if isOpen { return colorScheme == .light ? 0.54 : 0.47 }
        return 1.0
    }

    private var frontBottomOpacity: Double {
        if isOpen { return colorScheme == .light ? 0.64 : 0.58 }
        return 1.0
    }

    private var frontPanel: some View {
        let top = Metrics.frontTop
        let height = Metrics.frontHeight
        return ZStack(alignment: .top) {
            ZStack {
                if isOpen {
                    FolderFrontShape()
                        .fill(.thinMaterial)
                }

                FolderFrontShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.frontTop.opacity(frontTopOpacity),
                                palette.frontBottom.opacity(frontBottomOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    .clipShape(FolderFrontShape())

                FolderFrontShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), .clear, Color.black.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                FolderFrontShape()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.12), .clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 260
                        )
                    )

                FolderFrontShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                FolderFrontShape()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.12), .clear],
                            center: UnitPoint(x: 0.56, y: 0.60),
                            startRadius: 12,
                            endRadius: 190
                        )
                    )

                FolderFrontShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
                .shadow(color: palette.frontBottom.opacity(0.28), radius: 18, y: 10)
                .shadow(color: .black.opacity(0.26), radius: 8, y: 5)

            frontContent
                .padding(.horizontal, 21)
                .padding(.top, 36)
                .padding(.bottom, 10)
                .frame(width: Metrics.width, height: height, alignment: .top)
        }
        .frame(width: Metrics.width, height: height)
        .offset(y: top)
    }

    private var frontContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(binding.name.isEmpty ? "Untitled" : binding.name)
                .font(.bindery(17, .bold))
                .foregroundStyle(palette.ink.opacity(0.97))
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatusDotText(
                text: statusText,
                color: statusDot,
                font: .bindery(13.5, .medium)
            )
            .foregroundStyle(palette.ink.opacity(0.90))

            if let backupSummaryText {
                HStack(spacing: 4.5) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10, weight: .medium))
                    Text(backupSummaryText)
                        .font(.bindery(12, .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(palette.ink.opacity(0.70))
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 4) {
                Spacer(minLength: 4)

                Text(leafCategoryName(binding.category))
                    .font(.bindery(11, .semibold))
                    .foregroundStyle(palette.ink.opacity(0.98))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.ink.opacity(0.11), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .help(binding.category)
            }
        }
    }
}
