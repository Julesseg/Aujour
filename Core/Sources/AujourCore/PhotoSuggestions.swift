import Foundation
import Observation

/// One photograph the device holds from a Journal Day, as everything above the
/// library sees it.
///
/// A name the library answers to and the moment it was taken, and nothing
/// else: what it looks like needs a screen, and what it weighs needs a
/// download. Both are asked for by name, later and only for the ones somebody
/// actually wants — a day can hold two hundred photographs, and a panel that
/// fetched every one of them to offer them would be a day that took a while to
/// open.
public struct DayPhotograph: Hashable, Sendable, Identifiable {
    /// What the library calls it. Opaque here, and handed straight back when
    /// its thumbnail or its bytes are wanted.
    public let id: String

    /// When it was taken, which is the whole of why it is being offered.
    public let takenAt: Date

    public init(id: String, takenAt: Date) {
        self.id = id
        self.takenAt = takenAt
    }
}

/// Whether Aujour may read the user's photo library.
///
/// Three answers rather than a `Bool`, because the panel does something
/// different with each: an undecided library is one worth offering to look
/// in, a refused one is a panel that is not there, and only an allowed one is
/// ever read.
public enum PhotoLibraryAccess: Hashable, Sendable {
    /// Nobody has been asked yet.
    case undecided

    /// Aujour may read it — all of it, or the part of it the user picked out.
    case allowed

    /// The user said no, or this device does not allow it at all.
    case refused
}

/// The user's photo library, as the suggestions panel sees it.
///
/// The third seam between the domain and the device, after the Journal Store
/// and Day Data, and it is shaped by the same two promises:
///
/// - **Reading never asks.** ``photographs(during:)`` answers with nothing at
///   all where access is anything but granted. Asking is ``ask()``, which
///   happens because the user said to look and never because a day was opened
///   — the library permission is the suggestions panel's alone, and manual
///   insert through the system picker needs none of it.
/// - **Reading never fails.** A library that is not there, not permitted or
///   not answering is a day with no photographs to offer, which is a panel
///   that is simply absent. Nothing about a photo library ever reaches the
///   user as a journal that would not open (ADR 0001).
///
/// That second promise is about what is *offered*. A photograph somebody has
/// tapped is a different thing: they asked for it to go in the day, and one
/// that would not come is the app failing at the thing that was asked — which
/// is said where a photograph is added, and not here.
///
/// The two byte-shaped members are here and not on a seam of their own because
/// they are the same library answering about the same photograph, and a second
/// object to say that would be a second thing to keep in step. What those bytes
/// *are* is nothing this module looks at: a thumbnail is for a screen and a
/// photograph is for the attachment pipeline, and both are the app's.
public protocol PhotoLibrary: Sendable {
    /// Where the permission stands, without asking for it.
    var access: PhotoLibraryAccess { get }

    /// Puts the system's question in front of the user, and answers what they
    /// said.
    ///
    /// Called because somebody asked to see their photographs and at no other
    /// time. A permission already decided — granted or refused — is left
    /// decided and answered from what is already known, because the way back
    /// from a refusal is Settings and not another alert.
    func ask() async -> PhotoLibraryAccess

    /// The photographs taken during this stretch of the day, or none — which
    /// is also what an unallowed library answers.
    func photographs(during span: DateInterval) async -> [DayPhotograph]

    /// Something small enough to draw a strip of, or `nil` for one that would
    /// not come.
    func thumbnail(of photograph: DayPhotograph) async -> Data?

    /// The photograph itself, for the attachment pipeline to keep — or `nil`
    /// for one the library would not hand over, an iCloud photograph that is
    /// not on the device and will not come down.
    func contents(of photograph: DayPhotograph) async -> Data?
}

/// What the editor offers the day on screen: the photographs the device
/// already holds from it.
///
/// A day is written up in the evening, or a week later, and the pictures of it
/// are already on the phone — so Aujour offers them where the day is being
/// written, and adding one is a tap rather than a trip to the picker and back.
/// Which photographs those are is the only question here, and it has one
/// answer: the ones taken during the Entry's *Journal Day*, so that a Monday
/// filled in on Friday is offered Monday's.
///
/// It holds no pixels and no permission alert. Both are the app's, behind
/// ``PhotoLibrary`` — which is what lets every rule above be unit-tested on
/// Linux against a library that is said rather than read.
///
/// ## The panel is absent far more often than it is there
///
/// Three of the four states of the world show nothing at all: a library the
/// user refused, a device that will not allow one, and a day with no
/// photographs in it. None of them is a failure and none of them is said out
/// loud — a notice about a photo library would be a notice in front of
/// somebody who is writing, and the photo button on the accessory row goes on
/// working in every one of them, because the system picker needs no permission
/// (``AujourCore/Attachment``).
@MainActor
@Observable
public final class PhotoSuggestions {
    /// What the panel should be showing.
    public enum State: Hashable, Sendable {
        /// No panel. A refused library, a device with none, or a day the
        /// library holds nothing from.
        case nothingToOffer

        /// Nobody has been asked about the library yet, so there is something
        /// worth offering to look for — and asking is the user's to set going.
        case couldLook

        /// The day's photographs, in the order the day took them.
        case offering([DayPhotograph])
    }

    public private(set) var state: State = .nothingToOffer

    /// The library, or none at all — which is a preview, and a test of
    /// something else, and offers nothing.
    @ObservationIgnored private let library: (any PhotoLibrary)?

    /// The zone the day's midnight is measured in — the device's, which is the
    /// one the Entry around it is written in.
    @ObservationIgnored private let timeZone: TimeZone

    /// The day the panel is currently about, so that an answer arriving about
    /// a day that has since been left is dropped rather than shown. Opening a
    /// day from the calendar while another is still being read for is exactly
    /// that, and so is an app left open overnight moving on to today.
    @ObservationIgnored private var lookingFor: JournalDay?

    /// - Parameters:
    ///   - library: where the day's photographs are read from. `nil` is
    ///     suggestions with no library behind them — nothing to offer, ever,
    ///     which is what a preview and a test of something else want.
    ///   - timeZone: where the day's midnight is measured.
    public init(from library: (any PhotoLibrary)? = nil, in timeZone: TimeZone = .current) {
        self.library = library
        self.timeZone = timeZone
    }

    /// Points the panel at a day, and reads the library for it if that is
    /// allowed without asking anybody anything.
    ///
    /// Called with the day going on screen, and again when the app comes back
    /// to the front — a photograph taken five minutes ago is exactly the one
    /// somebody came back to write about.
    public func look(for day: JournalDay) async {
        // A different day is a different set of photographs, and the library
        // takes a moment to answer about it — so the last day's go now rather
        // than when the answer lands. Otherwise the morning an app left open
        // overnight moves on would offer yesterday's photographs over today's
        // Entry, and a tap in that window would put one of them in it.
        //
        // Only on a *different* day: looking again at the same one — coming
        // back to the front — must not blink the strip away and back.
        if lookingFor != day { state = .nothingToOffer }
        lookingFor = day
        guard let library else { return offer(.nothingToOffer, for: day) }

        switch library.access {
        case .refused:
            offer(.nothingToOffer, for: day)
        case .undecided:
            offer(.couldLook, for: day)
        case .allowed:
            await read(library, for: day)
        }
    }

    /// Asks for the library, because the user said to look — and shows what is
    /// there if they allowed it.
    ///
    /// The only thing in Aujour that ever asks for a photo library. A refusal
    /// leaves the panel absent and says nothing about it: they answered the
    /// question that was put to them, and the answer was no.
    public func askToLook() async {
        guard let library, let day = lookingFor else { return }

        guard await library.ask() == .allowed else {
            return offer(.nothingToOffer, for: day)
        }
        await read(library, for: day)
    }

    /// Something small enough to draw, for one of the photographs on offer.
    public func thumbnail(of photograph: DayPhotograph) async -> Data? {
        await library?.thumbnail(of: photograph)
    }

    /// The photograph itself, for the attachment pipeline — or `nil` for one
    /// the library would not hand over.
    public func contents(of photograph: DayPhotograph) async -> Data? {
        await library?.contents(of: photograph)
    }

    // MARK: - Reading

    private func read(_ library: any PhotoLibrary, for day: JournalDay) async {
        // Midnight to midnight where the device is, which is the stretch the
        // day's meetings are read for too (``JournalDay/span(in:)``) and the
        // one the user's own photos app draws this day as.
        let found = await library.photographs(during: day.span(in: timeZone))
        // In the order the day took them, however the library answered:
        // a strip of a day reads left to right the way the day did.
        let inOrder = found.sorted { $0.takenAt < $1.takenAt }
        offer(inOrder.isEmpty ? .nothingToOffer : .offering(inOrder), for: day)
    }

    /// Puts a state on screen, unless the day it is about has been left.
    private func offer(_ offered: State, for day: JournalDay) {
        guard lookingFor == day else { return }
        state = offered
    }
}
