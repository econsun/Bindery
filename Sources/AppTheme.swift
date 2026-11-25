import AppKit
import SwiftUI

private extension NSAppearance {
    var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

private func adaptive(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.isDarkMode ? dark : light
    }
}

private func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

extension Color {
    static let appBackground = Color(nsColor: adaptive(light: srgb(0xF5F5F7), dark: srgb(0x08090B)))
    static let appSidebar = Color(nsColor: adaptive(light: srgb(0xEDEDF0), dark: srgb(0x0B0C10)))
    static let appPanel = Color(nsColor: adaptive(light: srgb(0xFFFFFF), dark: srgb(0x131418)))
    static let appElevated = Color(nsColor: adaptive(light: srgb(0xFFFFFF), dark: srgb(0x1A1B20)))
    static let appDetailDim = Color(nsColor: adaptive(light: srgb(0x000000, alpha: 0.34), dark: srgb(0x000000, alpha: 0.34)))
    static let appPanelWash = Color(nsColor: adaptive(light: srgb(0x000000, alpha: 0.035), dark: srgb(0xFFFFFF, alpha: 0.05)))
    static let appBorder = Color(nsColor: adaptive(light: srgb(0x000000, alpha: 0.08), dark: srgb(0xFFFFFF, alpha: 0.06)))
    static let appPrimaryFill = Color.primary
    static let appPrimaryText = Color(nsColor: adaptive(light: srgb(0xFFFFFF), dark: srgb(0x0A0A0B)))
    static let appGreen = Color(nsColor: adaptive(light: srgb(0x3F8B58), dark: srgb(0x8ECF9B)))
    static let appOrange = Color(nsColor: adaptive(light: srgb(0xB26A24), dark: srgb(0xE6A261)))
    static let appRed = Color(nsColor: adaptive(light: srgb(0xB4544A), dark: srgb(0xD97B6D)))
    static let appGray = Color(nsColor: adaptive(light: srgb(0x6E7580), dark: srgb(0x8B9098)))
}

extension NSColor {
    static var appWindowBackground: NSColor {
        adaptive(light: srgb(0xF5F5F7), dark: srgb(0x08090B))
    }
}
