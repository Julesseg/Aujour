import AujourCore
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Aujour

// The suggestions panel's one tap, minus the screen it happens on. Which
// photographs a day is offered and whether there is a panel at all are decided
// in Core and tested there against a library that is said rather than read;
// what is left is what needs a device — that a tapped photograph goes through
// the same attachment pipeline the picker's does, and comes out as the same
// markdown in the same folder.

/// Whether this machine's ImageIO can *write* HEIC, which is what a test needs
/// in order to have one for the library to hand over.
private let canWriteHEIC = CGImageDestinationCreateWithData(
    NSMutableData(), UTType.heic.identifier as CFString, 1, nil
) != nil

@MainActor
@Suite("A photograph tapped in the suggestions panel")
struct SuggestedPhotographTests {
    // The whole of one tap: the file is in the folder under the Attachment
    // Path Template for this day, and the Entry points at it — which is the
    // same pipeline and the same embed the picker's photograph goes through.
    @Test("goes into the folder and its embed into the day")
    func inserting() async throws {
        let store = InMemoryJournalStore()
        let day = try await open(EntryEditor(store: store))
        let library = ALibrary(handing: photograph(as: .png))
        let suggestions = PhotoSuggestions(from: library)
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Walked to the market.")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)

        await photographs.insert(theMarket, from: suggestions)

        let path = "\(AttachmentPathTemplate.default.render(day.day))/\(day.day).png"
        #expect(try await store.fileExists(at: path))
        #expect(open.textView.text == "Walked to the market.\n![](../../\(path))")
        // Which is what saves it: a suggested picture reaches the Entry the
        // way a keystroke does.
        #expect(open.written == open.textView.text)
        #expect(photographs.problem == nil)
    }

    // Nobody is writing in this day — the panel was tapped over an Entry that
    // has not been touched — and a text view reports a caret at its very start
    // whether or not anyone is in it. The picture goes at the end of the day,
    // which is where the next thing written would go.
    @Test("goes at the end of a day nobody is writing in")
    func atTheEndOfADayNobodyIsWritingIn() async throws {
        let day = try await open(EntryEditor(store: InMemoryJournalStore()))
        let suggestions = PhotoSuggestions(from: ALibrary(handing: photograph(as: .png)))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "# Saturday\n\nWalked to the market.")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)
        // Where a text view that nobody has touched says its caret is.
        open.cursor(at: 0)

        await photographs.insert(theMarket, from: suggestions)

        #expect(open.textView.text.hasPrefix("# Saturday\n\nWalked to the market.\n!["))
    }

    // The one edit Aujour makes to somebody's photograph, and the library is
    // where HEICs come from: an iPhone camera writes them, so a suggested
    // photograph is one every time.
    @Test("is kept as a JPEG when the library hands over a HEIC", .enabled(if: canWriteHEIC))
    func aHeicFromTheLibrary() async throws {
        let store = InMemoryJournalStore()
        let day = try await open(EntryEditor(store: store))
        let suggestions = PhotoSuggestions(from: ALibrary(handing: photograph(as: .heic)))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)

        await photographs.insert(theMarket, from: suggestions)

        let path = "\(AttachmentPathTemplate.default.render(day.day))/\(day.day).jpg"
        #expect(try await store.fileExists(at: path))
    }

    // A picture is an edit like any other, whichever door it came in by.
    @Test("can be undone like anything else typed")
    func undoing() async throws {
        let day = try await open(EntryEditor(store: InMemoryJournalStore()))
        let suggestions = PhotoSuggestions(from: ALibrary(handing: photograph(as: .png)))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)
        await photographs.insert(theMarket, from: suggestions)

        let undo = try #require(open.textView.undoManager)
        #expect(undo.canUndo)
        undo.undo()

        #expect(open.textView.text == "Milk")
    }

    // Tapping a photograph and getting nothing is the app failing to do the
    // one thing that was asked, and an iCloud library that has not finished
    // downloading is exactly when it happens — so it is said, unlike a picker
    // nobody chose from.
    @Test("says so when the library will not hand it over")
    func aPhotographThatWouldNotCome() async throws {
        let day = try await open(EntryEditor(store: InMemoryJournalStore()))
        let suggestions = PhotoSuggestions(from: ALibrary(handing: nil))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)

        await photographs.insert(theMarket, from: suggestions)

        #expect(open.textView.text == "Milk")
        #expect(open.written == nil)
        #expect(photographs.problem != nil)
    }

    @Test("says so when the folder will not take it, and writes nothing in the day")
    func aFolderThatRefuses() async throws {
        let day = try await open(EntryEditor(store: AFolderThatRefusesAPhotograph()))
        let suggestions = PhotoSuggestions(from: ALibrary(handing: photograph(as: .png)))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.insertsPhotographs(from: photographs, into: open.textView)

        await photographs.insert(theMarket, from: suggestions)

        #expect(open.textView.text == "Milk")
        #expect(open.written == nil)
        #expect(photographs.problem != nil)
    }

    // MARK: - A day to add one to

    /// The photograph every test above taps. Which one it is never matters:
    /// what the library hands back for it is what the test seeded.
    private var theMarket: DayPhotograph {
        DayPhotograph(id: "market", takenAt: Date(timeIntervalSince1970: 1_773_484_800))
    }

    private func open(_ editor: EntryEditor) async throws -> EntryEditor {
        await editor.open()
        try #require(editor.state.isEditing)
        return editor
    }

    private func photograph(as type: UTType) -> Data? {
        UITestingJournal.photograph(as: type)
    }
}

/// A photo library that hands back one photograph, or none at all.
///
/// It is never asked which photographs a day holds — that is Core's question
/// and Core's tests. What these tests need of it is the other half: the bytes
/// behind a photograph somebody tapped.
private struct ALibrary: PhotoLibrary {
    let handing: Data?

    let access = PhotoLibraryAccess.allowed
    func ask() async -> PhotoLibraryAccess { .allowed }
    func photographs(during span: DateInterval) async -> [DayPhotograph] { [] }
    func thumbnail(of photograph: DayPhotograph) async -> Data? { handing }
    func contents(of photograph: DayPhotograph) async -> Data? { handing }
}

/// A folder that will not be written to — a disk that filled up, an iCloud
/// container that has gone.
private struct AFolderThatRefusesAPhotograph: JournalStore {
    struct ItWillNotGo: LocalizedError {
        var errorDescription: String? { "Aujour couldn't add that photo." }
    }

    func listFiles() async throws -> [String] { [] }
    func fileExists(at relativePath: String) async throws -> Bool { false }
    func read(at relativePath: String) async throws -> Data {
        throw JournalStoreError.fileNotFound(relativePath)
    }
    func write(_ contents: Data, at relativePath: String) async throws { throw ItWillNotGo() }
    func create(_ contents: Data, at relativePath: String) async throws { throw ItWillNotGo() }
    func move(from source: String, to destination: String) async throws { throw ItWillNotGo() }
}
