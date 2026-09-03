import SwiftUI

/// The pieces every sheet in Aujour is built out of: the paper it is cut from,
/// the corner it is cut with, the grabber at the top of it, and the way it
/// arrives from the control that summoned it.
///
/// Shared rather than repeated, for the reason the pieces in `SettingsChrome.swift`
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
