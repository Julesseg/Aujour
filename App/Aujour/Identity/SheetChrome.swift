import SwiftUI

/// The pieces every sheet in Aujour is built out of: the paper it is cut from,
/// the corner it is cut with, the grabber at the top of it, and the way it
/// arrives from the control that summoned it.
///
/// Shared rather than repeated, for the reason the pieces in `PageChrome.swift`
/// are: a sheet is one
/// of the two shapes this app has — a page, and something in front of a page —
/// and two sheets that came up differently would say they were two apps. What
/// a sheet is *about* is its own; what it looks like on the way in is not.

/// What a sheet and the control that summons it agree to call the journey
/// between them.
///
/// Named in one place rather than spelled out at both ends: a sheet whose
/// identifier does not match its button's does not fail — it quietly comes up
/// from the bottom of the screen instead, which is the kind of wrong nobody
/// notices for a release.
///
/// One name, because there is one control. Everything the bar can put up comes
/// out of the same button, and only ever one of them at a time.
enum Sheets {
    static let theBar = "theBar"
}

extension View {
    /// Dresses a sheet in the identity: the paper, the corner and the grabber.
    ///
    /// The identity's own sheet paper, which is a hair off the page's so that
    /// a sheet over a screen reads as being in front of it. The corner is much
    /// rounder than anything drawn on a page, because it is the one corner cut
    /// against the device's own (`Rounding.sheet`).
    ///
    /// The grabber is the system's rather than a bar of the identity's own
    /// drawing: it is the thing that moves under the finger dragging the
    /// sheet, and one drawn here would be a picture of that.
    ///
    /// The scrim is the system's too, and there is no seam to replace it —
    /// which is no loss. What the design file draws behind a sheet is a dim
    /// and a slight blur, and that is what a sheet already comes up over.
    ///
    /// Nothing here tints anything: the accent this device chose is already on
    /// the whole app, and a sheet inherits the environment of the view that put
    /// it up.
    ///
    /// How *tall* a sheet is stays the caller's, because it is a fact about
    /// what is on it — a search box over a list is not a page of settings.
    func sheetChrome() -> some View {
        presentationBackground(Palette.sheetColor)
            .presentationCornerRadius(Rounding.sheet)
            .presentationDragIndicator(.visible)
    }

    /// The same chrome, on a sheet that rises out of the control that summoned
    /// it.
    ///
    /// The control has to be marked as the place it comes from, with
    /// ``SwiftUI/View/matchedTransitionSource(id:in:)`` under the same
    /// identifier and namespace. Where it is not — the control has scrolled
    /// away, or the sheet was put up by something else — the sheet comes up
    /// the ordinary way, which is why nothing here has to check.
    @ViewBuilder
    func sheetChrome(risingFrom id: some Hashable & Sendable, in namespace: Namespace.ID?)
        -> some View
    {
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
                .sheetChrome()
        } else {
            sheetChrome()
        }
    }

    /// Dresses a settings page: the paper it is cut from, and the page's name
    /// said in the bar's inline place.
    ///
    /// Half of the surfaces. A grouped `Form` draws two — the page under
    /// everything, and one card per section — and this deals with the first
    /// only. Hiding the scroll background gets rid of the cold grey a grouped
    /// list lays the page down in; the cards are ``settingsRows()``, which has
    /// to be said on each `Section` and cannot be said here.
    ///
    /// The paper is stated rather than inherited, and that is the half that is
    /// easy to get wrong. The settings sheet has ``sheetChrome()`` behind it,
    /// so the *root* of the stack shows through to cream whether or not
    /// anything here says so — but a pushed page does not: the navigation
    /// container puts its own white behind it, and a `Form` that has hidden
    /// its background shows that instead. Left alone, every page one step in
    /// came out white on white, with the rows invisible against the page they
    /// were on.
    ///
    /// The **text is left to the system**, and that is a decision rather than
    /// an omission. A list draws its values, its group headings and its
    /// chevrons in a neutral grey where the rest of this app is warm, and the
    /// palette has two steps that look like exactly what those roles want —
    /// `inkMuted` for a value, `inkFaint` for a heading and a chevron. Naming
    /// them was tried and reverted: `foregroundStyle` reaches a grouped list's
    /// parts in the wrong order, and what came out was headings at full ink
    /// and values with no step down from their labels — a louder screen than
    /// the one the system draws for free.
    ///
    /// Which is the whole bargain of #111. A settings screen is where being
    /// recognisably iOS beats being recognisably Aujour, and the identity is
    /// carried by the two surfaces above — the paper and the card — with the
    /// type hierarchy left to the platform that already has one.
    ///
    /// Named in one place rather than written out on each of the seven, for
    /// the reason ``sheetChrome()`` is: which paper a page is cut from is the
    /// identity's and not a screen's own idea.
    func settingsPage(titled title: String) -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.sheetColor)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    /// The card a group of settings rows sits on.
    ///
    /// The other half of ``settingsPage(titled:)``, and separate from it
    /// because the system will only take it here. A grouped `Form` draws two
    /// surfaces: the page, which ``settingsPage(titled:)`` deals with, and one
    /// card per section — `secondarySystemGroupedBackground`, which is pure
    /// white in light and a *neutral* grey in dark, on paper that is warm in
    /// both. `listRowBackground` is a row's own modifier: put on the `Form` it
    /// is silently ignored, and it has to be said on each `Section`. Which is
    /// why it is a named thing rather than a colour repeated twenty times —
    /// a section that forgets it does not fail, it just comes out as somebody
    /// else's app in the middle of this one.
    func settingsRows() -> some View {
        listRowBackground(Palette.cardColor)
    }

    /// Marks this control as the place a sheet comes out of — the other half
    /// of ``sheetChrome(risingFrom:in:)``.
    ///
    /// Named as a pair with it rather than left as the system's
    /// `matchedTransitionSource`, because the failure is silent: a control and
    /// a sheet under two different identifiers do not stop working, they just
    /// stop being connected, and the sheet comes up from the bottom of the
    /// screen as though nobody had asked.
    func summonsASheet(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }
}
