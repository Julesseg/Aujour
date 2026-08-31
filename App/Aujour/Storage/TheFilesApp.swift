import Foundation
import UIKit

/// The Files app, as somewhere Aujour can send somebody.
///
/// One errand and no other: showing a file where it lies. It is what the
/// Journal Root being a folder the user owns is *for* (ADR 0001) — the way
/// out of Aujour and into the vault, at the file this screen is talking
/// about.
///
/// A URL scheme and not an API, because there is no API. Nothing on iOS
/// reveals a file in Files the way `NSWorkspace` does on the Mac, and the
/// alternative — a document browser inside Aujour — would be Aujour's own
/// second Files app over the user's own folder, which is precisely what
/// handing them a real folder was meant to avoid.
enum TheFilesApp {
    /// Where to send somebody so they land on this file.
    ///
    /// The same path under the scheme the Files app answers to, so that
    /// whatever the folder is called and whatever is in the name survives the
    /// trip — a journal in "My Journal" is a path with a space in it, and a
    /// path put back together by hand is a path that loses one.
    ///
    /// `nil` for anything that is not a file on this device, which is nowhere
    /// to send anybody.
    static func url(showing file: URL) -> URL? {
        guard file.isFileURL else { return nil }
        var address = URLComponents(url: file.standardizedFileURL, resolvingAgainstBaseURL: false)
        address?.scheme = "shareddocuments"
        return address?.url
    }

    /// Opens the Files app on this file, or on the folder holding it.
    ///
    /// The folder as a second try rather than as a worse first one: what the
    /// Files app does with a path that names a file rather than a folder has
    /// not been the same in every iOS, and a banner whose one action silently
    /// did nothing would be worse than a banner with no action. The folder is
    /// where the file lies either way — a Parked File sits beside the Entry
    /// precisely so that it is found there.
    @MainActor
    static func show(_ file: URL) {
        guard let address = url(showing: file) else { return }
        Task {
            if await UIApplication.shared.open(address) { return }
            guard let folder = url(showing: file.deletingLastPathComponent()) else { return }
            _ = await UIApplication.shared.open(folder)
        }
    }
}
