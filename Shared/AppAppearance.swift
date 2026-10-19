import SwiftUI

@Observable
final class AppAppearance {
    static let shared = AppAppearance()

    enum Mode: String, CaseIterable {
        case system = "System", light = "Light", dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        #if canImport(AppKit)
        var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        #endif
    }

    enum Theme: String, CaseIterable {
        case campfire = "Campfire", paper = "Paper", forest = "Forest", dusk = "Dusk"

        // Paper, text, secondary text, and separators, in light and dark appearances.
        var colors: [(UInt32, UInt32)] {
            switch self {
            case .campfire: [(0xF4EFE6, 0x1A1612), (0x1C1915, 0xF4EFE6), (0x5C6B52, 0xA8B59A), (0xE4D9C8, 0x2E2822)]
            case .paper: [(0xFAF9F6, 0x1C1D1F), (0x252629, 0xF0F0ED), (0x62666B, 0xACB1B7), (0xE4E4DF, 0x333639)]
            case .forest: [(0xEDF1E8, 0x151D18), (0x223229, 0xE7EEE5), (0x51654F, 0xA5B9A0), (0xD5DECE, 0x2D3C30)]
            case .dusk: [(0xF1ECF3, 0x211B28), (0x352B3D, 0xF0E9F4), (0x706079, 0xBDAAC9), (0xDED3E4, 0x3A2E45)]
            }
        }
    }

    enum Accent: String, CaseIterable {
        case ember = "Ember", moss = "Moss", ocean = "Ocean", plum = "Plum"
        var colors: (UInt32, UInt32) {
            switch self {
            case .ember: (0xAE4D1F, 0xEF9A65)
            case .moss: (0x4B6C40, 0xA6C58F)
            case .ocean: (0x276A86, 0x81BDD7)
            case .plum: (0x83518B, 0xCDA2D4)
            }
        }
    }

    enum Typeface: String, CaseIterable {
        case serif = "Serif", system = "System", rounded = "Rounded", mono = "Monospaced"
        var design: Font.Design {
            switch self {
            case .serif: .serif
            case .system: .default
            case .rounded: .rounded
            case .mono: .monospaced
            }
        }
        var platformDesign: InkFontDescriptor.SystemDesign {
            switch self {
            case .serif: .serif
            case .system: .default
            case .rounded: .rounded
            case .mono: .monospaced
            }
        }
    }

    private let defaults: UserDefaults
    var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "campfire.appearanceMode") } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "campfire.theme") } }
    var accent: Accent { didSet { defaults.set(accent.rawValue, forKey: "campfire.accent") } }
    var typeface: Typeface { didSet { defaults.set(typeface.rawValue, forKey: "campfire.typeface") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "campfire.fontSize") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = Mode(rawValue: defaults.string(forKey: "campfire.appearanceMode") ?? "") ?? .system
        theme = Theme(rawValue: defaults.string(forKey: "campfire.theme") ?? "") ?? .campfire
        accent = Accent(rawValue: defaults.string(forKey: "campfire.accent") ?? "") ?? .ember
        typeface = Typeface(rawValue: defaults.string(forKey: "campfire.typeface") ?? "") ?? .serif
        let savedSize = defaults.double(forKey: "campfire.fontSize")
        fontSize = savedSize.isFinite && (16...28).contains(savedSize) ? savedSize : 20
    }

    var revision: String { "\(mode)/\(theme)/\(accent)/\(typeface)/\(fontSize)" }

    func reset() {
        mode = .system
        theme = .campfire
        accent = .ember
        typeface = .serif
        fontSize = 20
    }
}


struct AppearanceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Ink.ember)
            .preferredColorScheme(AppAppearance.shared.mode.colorScheme)
            #if canImport(AppKit)
            .onChange(of: AppAppearance.shared.mode, initial: true) { _, mode in
                NSApplication.shared.appearance = mode.appKitAppearance
            }
            #endif
    }
}
