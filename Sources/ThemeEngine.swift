import SwiftUI

// MARK: - Theme Definition

/// JSON-serializable theme definition
struct ThemeDefinition: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var colors: ThemeColors
    var fonts: ThemeFonts

    struct ThemeColors: Codable, Equatable {
        var bg: String           // hex color
        var bgCard: String
        var bgHover: String
        var cream: String
        var creamBold: String
        var creamDim: String
        var accent: String
        var accentLime: String
        var accentBlue: String
        var accentMagenta: String
        var muted: String
        var teal: String
        var green: String
        var red: String
        var yellow: String
        var blue: String
    }

    struct ThemeFonts: Codable, Equatable {
        var family: String       // "system" or font name
        var sizeMultiplier: Double
        var minimumSize: Int
    }

    // Built-in Synthaer Dark (matches current Theme enum)
    static let synthaerDark = ThemeDefinition(
        name: "synthaer-dark",
        colors: ThemeColors(
            bg: "#1a1525", bgCard: "#231e30", bgHover: "#2c2540",
            cream: "#f5e6d3", creamBold: "#fff1e0", creamDim: "#a89585",
            accent: "#ff6b9d", accentLime: "#b8e986", accentBlue: "#7ec8e3",
            accentMagenta: "#e17bed",
            muted: "#6b6080", teal: "#4ec9b0", green: "#6abf69",
            red: "#f44747", yellow: "#dcdcaa", blue: "#569cd6"
        ),
        fonts: ThemeFonts(family: "system", sizeMultiplier: 1.0, minimumSize: 12)
    )

    // Built-in Synthaer Light
    static let synthaerLight = ThemeDefinition(
        name: "synthaer-light",
        colors: ThemeColors(
            bg: "#faf5ef", bgCard: "#f0ebe4", bgHover: "#e6e0d8",
            cream: "#2d2438", creamBold: "#1a1525", creamDim: "#6b6080",
            accent: "#d44a7a", accentLime: "#5a8c3e", accentBlue: "#3a7ca5",
            accentMagenta: "#9b4da6",
            muted: "#a89585", teal: "#2d8f7f", green: "#4a8f49",
            red: "#c03030", yellow: "#8b7b20", blue: "#3a6aad"
        ),
        fonts: ThemeFonts(family: "system", sizeMultiplier: 1.0, minimumSize: 12)
    )

    static let builtins: [ThemeDefinition] = [synthaerDark, synthaerLight]
}

// MARK: - Theme Engine

/// Manages theme loading, selection, and color resolution
@MainActor
class ThemeEngine: ObservableObject {
    static let shared = ThemeEngine()

    @Published var activeTheme: ThemeDefinition = .synthaerDark
    @Published var availableThemes: [ThemeDefinition] = ThemeDefinition.builtins

    private let themesDir = NSHomeDirectory() + "/.config/mlx-launcher/themes"

    init() {
        loadCustomThemes()
    }

    // MARK: - Theme Loading

    func loadCustomThemes() {
        var themes = ThemeDefinition.builtins
        let files = (try? FileManager.default.contentsOfDirectory(atPath: themesDir)) ?? []
        for file in files where file.hasSuffix(".json") {
            let path = "\(themesDir)/\(file)"
            guard let data = FileManager.default.contents(atPath: path),
                  let theme = try? JSONDecoder().decode(ThemeDefinition.self, from: data) else { continue }
            // Skip if a builtin with the same name already exists
            if !themes.contains(where: { $0.name == theme.name }) {
                themes.append(theme)
            }
        }
        availableThemes = themes
    }

    // MARK: - Theme Selection

    func selectTheme(_ name: String) {
        if let theme = availableThemes.first(where: { $0.name == name }) {
            activeTheme = theme
        }
    }

    func selectTheme(_ theme: ThemeDefinition) {
        activeTheme = theme
    }

    // MARK: - Custom Theme Management

    func saveCustomTheme(_ theme: ThemeDefinition) {
        try? FileManager.default.createDirectory(atPath: themesDir, withIntermediateDirectories: true)
        let path = "\(themesDir)/\(theme.name).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(theme) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        loadCustomThemes()
        // Auto-select after saving
        activeTheme = theme
    }

    func deleteCustomTheme(_ name: String) {
        let path = "\(themesDir)/\(name).json"
        try? FileManager.default.removeItem(atPath: path)
        loadCustomThemes()
        // If the deleted theme was active, fall back to default
        if activeTheme.name == name {
            activeTheme = .synthaerDark
        }
    }

    var isActiveThemeBuiltin: Bool {
        ThemeDefinition.builtins.contains(where: { $0.name == activeTheme.name })
    }

    // MARK: - Color Resolution

    func color(from hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return .clear }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    // Convenience accessors matching current Theme enum slots
    var bg: Color { color(from: activeTheme.colors.bg) }
    var bgCard: Color { color(from: activeTheme.colors.bgCard) }
    var bgHover: Color { color(from: activeTheme.colors.bgHover) }
    var cream: Color { color(from: activeTheme.colors.cream) }
    var creamBold: Color { color(from: activeTheme.colors.creamBold) }
    var creamDim: Color { color(from: activeTheme.colors.creamDim) }
    var accent: Color { color(from: activeTheme.colors.accent) }
    var accentLime: Color { color(from: activeTheme.colors.accentLime) }
    var accentBlue: Color { color(from: activeTheme.colors.accentBlue) }
    var accentMagenta: Color { color(from: activeTheme.colors.accentMagenta) }
    var muted: Color { color(from: activeTheme.colors.muted) }
    var teal: Color { color(from: activeTheme.colors.teal) }
    var green: Color { color(from: activeTheme.colors.green) }
    var red: Color { color(from: activeTheme.colors.red) }
    var yellow: Color { color(from: activeTheme.colors.yellow) }
    var blue: Color { color(from: activeTheme.colors.blue) }

    // MARK: - Font Resolution

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let adjusted = max(
            CGFloat(activeTheme.fonts.minimumSize),
            size * activeTheme.fonts.sizeMultiplier
        )
        if activeTheme.fonts.family == "system" {
            return .system(size: adjusted, weight: weight)
        }
        return .custom(activeTheme.fonts.family, size: adjusted)
    }
}
