import AujourCore
import SwiftUI
import UIKit

enum AccentSurface: CaseIterable {
    case sheet
    case card

    func color(for accent: Accent) -> UIColor {
        switch self {
        case .sheet: Self.sheets[accent]!
        case .card: Self.cards[accent]!
        }
    }

    private static let sheets = colors(light: 0.04, dark: 0.14)
    private static let cards = colors(light: 0.08, dark: 0.21)

    private static func colors(light: CGFloat, dark: CGFloat) -> [Accent: UIColor] {
        Dictionary(uniqueKeysWithValues: Accent.allCases.map { accent in
            (accent, UIColor { traits in
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                accent.uiColor.resolvedColor(with: traits)
                    .getRed(&red, green: &green, blue: &blue, alpha: nil)
                let isDark = traits.userInterfaceStyle == .dark
                let weight = isDark ? dark : light
                let paper: CGFloat = isDark ? 0 : 1 - weight
                return UIColor(
                    red: paper + red * weight,
                    green: paper + green * weight,
                    blue: paper + blue * weight,
                    alpha: 1
                )
            })
        })
    }
}

struct SurfaceFill: View {
    let surface: AccentSurface
    @Environment(\.accent) private var accent

    init(_ surface: AccentSurface) {
        self.surface = surface
    }

    var body: some View {
        Color(surface.color(for: accent))
    }
}

extension View {
    func surfaceBackground(_ surface: AccentSurface, in shape: some Shape) -> some View {
        background { SurfaceFill(surface).clipShape(shape) }
    }
}

extension EnvironmentValues {
    var accent: Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = DeviceSettings.default.accent
}
