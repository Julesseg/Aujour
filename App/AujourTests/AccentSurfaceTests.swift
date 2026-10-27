import AujourCore
import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("Surfaces follow the chosen accent")
struct AccentSurfaceTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func everyAccentHasItsOwnSurfaces(style: UIUserInterfaceStyle) {
        for surface in AccentSurface.allCases {
            let colors = Accent.allCases.map { surface.color(for: $0).hex(in: style) }
            #expect(Set(colors).count == Accent.allCases.count)
        }
    }

    @Test(arguments: Accent.allCases)
    func surfacesResolveAgainstTheirOwnAppearance(accent: Accent) {
        for surface in AccentSurface.allCases {
            let color = surface.color(for: accent)
            #expect(color.hex(in: .light) != color.hex(in: .dark))
            #expect(color.hex(in: .unspecified) == color.hex(in: .light))
            #expect(color === surface.color(for: accent))
        }
    }

    @Test(arguments: Accent.allCases)
    func theInkStaysLegibleOnTintedSurfaces(accent: Accent) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for surface in AccentSurface.allCases {
                let color = surface.color(for: accent)
                let ground = Landed(color, in: style)
                for ink in [Palette.ink, Palette.inkMuted, Palette.alarm, accent.uiColor] {
                    let contrast = Landed(ink, in: style, over: color).contrast(against: ground)
                    #expect(contrast >= 4.5, "\(accent) \(surface) \(style): \(contrast)")
                }
                #expect(Landed(Palette.inkFaint, in: style, over: color)
                    .contrast(against: ground) >= 3)
                let wash = Landed(accent.softColor, in: style, over: color)
                let chipContrast = Landed(accent.inkColor, in: style).contrast(against: wash)
                #expect(chipContrast >= 4.5, "\(accent) chip on \(surface) \(style): \(chipContrast)")
            }
        }
    }
}
