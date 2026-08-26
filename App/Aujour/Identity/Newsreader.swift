import UIKit

/// The identity's prose voice — the face a journal's own words, its empty
/// states and its quiet asides are set in.
///
/// Bundled rather than reached for on the system, because there is no serif on
/// iOS that looks like this one and prose is the thing the identity is *for*.
/// It travels under the SIL Open Font License 1.1, whose terms are met by
/// shipping the licence beside the font — `Newsreader-OFL.txt`, which is in
/// the bundle and is asserted to be there by a test, since a licence dropped
/// from a resource copy is a licence nobody notices is gone.
///
/// One file per slant rather than one per weight: Newsreader is a variable
/// font, and every weight below is a named instance cut out of the same two
/// files. That is the whole reason to bundle a variable font — a static set
/// covering three weights in two slants would be six files and roughly three
/// times the bytes, for the same six faces.
enum Newsreader {
    /// The three weights the identity draws prose at, and no more. Newsreader
    /// carries eight; the other five are not in the design and a face nobody
    /// has chosen to use is a face that gets used inconsistently.
    enum Weight: CaseIterable {
        /// The empty states and the asides — the identity's quietest voice.
        case light
        /// Running prose.
        case regular
        /// A heading inside an entry.
        case medium
    }

    enum Slant: CaseIterable {
        case roman
        case italic
    }

    /// The face, at a size, before Dynamic Type has had it.
    ///
    /// Callers on the type scale go through `Lettering` and never come here;
    /// this is the seam under it, and the one a test can ask whether the font
    /// actually made it into the bundle.
    ///
    /// Falls back to the system's own serif rather than to nothing, so a
    /// resource that failed to copy is a screen that looks wrong rather than
    /// one that draws in Helvetica or crashes. The tests are what catch the
    /// fallback — by the time a user could see it, it is too late to be told.
    static func face(_ weight: Weight, _ slant: Slant, size: CGFloat) -> UIFont {
        UIFont(name: postScriptName(weight, slant), size: size) ?? systemSerif(weight, slant, size)
    }

    /// What the two font files call each face.
    ///
    /// The regular is the odd one out, and that is the file and not a typo:
    /// the default instance of a variable font keeps the font's own PostScript
    /// name, and every other instance is named after the axis position it
    /// pins. `NewsreaderRoman-Regular` does not exist and never will.
    private static func postScriptName(_ weight: Weight, _ slant: Slant) -> String {
        switch (weight, slant) {
        case (.light, .roman): "NewsreaderRoman-Light"
        case (.regular, .roman): "Newsreader16pt-Regular"
        case (.medium, .roman): "NewsreaderRoman-Medium"
        case (.light, .italic): "NewsreaderItalic-Light"
        case (.regular, .italic): "Newsreader16pt-Italic"
        case (.medium, .italic): "NewsreaderItalic-Medium"
        }
    }

    private static func systemSerif(_ weight: Weight, _ slant: Slant, _ size: CGFloat) -> UIFont {
        let plain = UIFont.systemFont(ofSize: size, weight: weight.systemEquivalent)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if slant == .italic { traits.insert(.traitItalic) }
        guard
            let descriptor = plain.fontDescriptor.withDesign(.serif)?
                .withSymbolicTraits(traits.union(plain.fontDescriptor.symbolicTraits))
        else { return plain }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Newsreader.Weight {
    /// Where this sits on the variable font's weight axis — the number the
    /// named instance pins, kept here so the mapping is readable next to the
    /// names rather than only inside a binary.
    var axisValue: CGFloat {
        switch self {
        case .light: 300
        case .regular: 400
        case .medium: 500
        }
    }

    /// The nearest system weight, for the fallback face.
    var systemEquivalent: UIFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        }
    }
}
