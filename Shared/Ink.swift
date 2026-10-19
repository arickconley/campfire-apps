import SwiftUI
#if canImport(UIKit)
import UIKit
typealias InkPlatformColor = UIColor
typealias InkPlatformFont = UIFont
typealias InkFontDescriptor = UIFontDescriptor
#elseif canImport(AppKit)
import AppKit
typealias InkPlatformColor = NSColor
typealias InkPlatformFont = NSFont
typealias InkFontDescriptor = NSFontDescriptor
#endif

enum Ink {
    static var paper: Color { Color(light: AppAppearance.shared.theme.colors[0].0, dark: AppAppearance.shared.theme.colors[0].1) }
    static var ink: Color { Color(light: AppAppearance.shared.theme.colors[1].0, dark: AppAppearance.shared.theme.colors[1].1) }
    static var moss: Color { Color(light: AppAppearance.shared.theme.colors[2].0, dark: AppAppearance.shared.theme.colors[2].1) }
    static var ember: Color { Color(light: AppAppearance.shared.accent.colors.0, dark: AppAppearance.shared.accent.colors.1) }
    static var rule: Color { Color(light: AppAppearance.shared.theme.colors[3].0, dark: AppAppearance.shared.theme.colors[3].1) }

    static var uiPaper: InkPlatformColor { palette(0) }
    static var uiInk: InkPlatformColor { palette(1) }
    static var uiMoss: InkPlatformColor { palette(2) }
    static var uiRule: InkPlatformColor { palette(3) }
    static var uiEmber: InkPlatformColor {
        let colors = AppAppearance.shared.accent.colors
        return dynamic(light: colors.0, dark: colors.1)
    }

    private static func palette(_ index: Int) -> InkPlatformColor {
        let colors = AppAppearance.shared.theme.colors[index]
        return dynamic(light: colors.0, dark: colors.1)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> InkPlatformColor {
        #if canImport(UIKit)
        UIColor { trait in
            hex(trait.userInterfaceStyle == .dark ? dark : light)
        }
        #else
        NSColor(name: nil, dynamicProvider: { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return hex(darkMode ? dark : light)
        })
        #endif
    }

    private static func hex(_ hex: UInt32) -> InkPlatformColor {
        InkPlatformColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum InkFont {
    static func serif(_ size: CGFloat, bold: Bool, italic: Bool) -> InkPlatformFont {
        let weight: InkPlatformFont.Weight = bold ? .semibold : .regular
        let base = InkPlatformFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(AppAppearance.shared.typeface.platformDesign) ?? base.fontDescriptor
        #if canImport(UIKit)
        var traits = UIFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let styled = descriptor.withSymbolicTraits(traits) {
            descriptor = styled
        }
        let font = UIFont(descriptor: descriptor, size: size)
        if italic && !isItalic(font), let fallback = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: fallback, size: size)
        }
        return font
        #else
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        // Rounded has no italic face; keep emphasis with the system italic font.
        if italic && !isItalic(font) {
            return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? font
        }
        return font
        #endif
    }

    static func editorSize(_ size: CGFloat) -> CGFloat {
        size * AppAppearance.shared.fontSize / 20
    }

    static func mono(_ size: CGFloat = 17) -> InkPlatformFont {
        .monospacedSystemFont(ofSize: editorSize(size), weight: .regular)
    }

    static func isBold(_ font: InkPlatformFont) -> Bool {
        #if canImport(UIKit)
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #else
        font.fontDescriptor.symbolicTraits.contains(.bold)
        #endif
    }

    static func isItalic(_ font: InkPlatformFont) -> Bool {
        #if canImport(UIKit)
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #else
        font.fontDescriptor.symbolicTraits.contains(.italic)
        #endif
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: Ink.dynamicColor(light: light, dark: dark))
        #else
        self.init(nsColor: Ink.dynamicColor(light: light, dark: dark))
        #endif
    }
}

extension Ink {
    fileprivate static func dynamicColor(light: UInt32, dark: UInt32) -> InkPlatformColor {
        dynamic(light: light, dark: dark)
    }
}

extension Font {
    static func campTitle() -> Font { .system(.largeTitle, design: .serif) }
    static func campPost() -> Font { .system(.title3, design: .serif) }
    static func campEditor() -> Font { .system(.title2, design: .serif) }
}
