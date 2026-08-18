import AujourCore
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Aujour

// Adding a photograph, minus the one part that is another process's screen.
// Where the file goes and what the embed says is Core's and is tested there
// against the paths it comes out as; what is left is what needs a device to
// answer — what a HEIC becomes, and that pressing the control on the row puts
// a file in the folder and its embed in the day.

/// Whether this machine's ImageIO can *write* HEIC, which is what a test needs
/// in order to have one to hand over. Reading one is a separate question, and
/// it is the one the app actually depends on — an iPhone's camera writes them
/// whatever a build machine can do.
///
/// Outside the suite because a trait is evaluated off the main actor, and this
/// suite is on it.
private let canWriteHEIC = CGImageDestinationCreateWithData(
    NSMutableData(), UTType.heic.identifier as CFString, 1, nil
) != nil


@MainActor
@Suite("A photograph added from the row")
struct InsertedPhotographsTests {
    // MARK: - What a vault can hold

    // The acceptance criterion, and the one edit Aujour makes to somebody's
    // photograph: HEIC is what an iPhone camera writes, and what a folder
    // opened on anything else cannot show.
    @Test("a HEIC photograph is kept as a JPEG", .enabled(if: canWriteHEIC))
    func heicBecomesJpeg() throws {
        let picked = try #require(photograph(as: .heic))

        let kept = try #require(InsertedPhotographs.keeping(picked))

        #expect(kept.format == .jpeg)
        #expect(format(of: kept.contents) == UTType.jpeg.identifier)
    }

    // Which way up a photograph is lives in its metadata rather than in its
    // rows, so a re-encode that dropped it would turn every landscape photo on
    // its side.
    @Test("what a photograph says about itself survives the conversion", .enabled(if: canWriteHEIC))
    func metadataSurvives() throws {
        // 6: rotated 90°, which is an iPhone held on its side.
        let picked = try #require(photograph(as: .heic, orientation: 6))

        let kept = try #require(InsertedPhotographs.keeping(picked))

        #expect(orientation(of: kept.contents) == 6)
    }

    @Test("a format a vault can hold is kept byte for byte", arguments: [
        (UTType.png, AttachmentFormat.png), (UTType.jpeg, .jpeg),
    ])
    func portableFormatsAreLeftAlone(type: UTType, format: AttachmentFormat) throws {
        let picked = try #require(photograph(as: type))

        let kept = try #require(InsertedPhotographs.keeping(picked))

        #expect(kept.format == format)
        #expect(kept.contents == picked)
    }

    // A picker only hands back images, so this is the defensive answer rather
    // than a case anybody meets — and it is `nil` rather than an error,
    // because there is nothing a user could do about it.
    @Test("something that is not an image at all goes no further")
    func notAnImage() {
        #expect(InsertedPhotographs.keeping(Data("not a photograph".utf8)) == nil)
    }

    // MARK: - Pressing the control

    // The whole of it, minus the picker: the file is in the folder, the embed
    // is at the caret, and the Entry has been told — which is what saves it.
    @Test("the file lands in the folder and its embed at the caret")
    func insertingAPhotograph() async throws {
        let store = InMemoryJournalStore()
        let day = try await open(EntryEditor(store: store))
        let photographs = InsertedPhotographs(picking: { _ in self.photograph(as: .png) })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Walked to the market.")
        open.coordinator.photographs = photographs
        open.cursor(at: 21)

        await open.coordinator.insertAPhotograph(in: open.textView)?.value

        let name = "\(day.day).png"
        let path = "\(AttachmentPathTemplate.default.render(day.day))/\(name)"
        #expect(try await store.fileExists(at: path))
        #expect(
            open.textView.text
                == "Walked to the market.\n![](../../\(path))"
        )
        // Which is what saves it: the text view announces what it was told to
        // change, and a picture goes in the way a tapped control does.
        #expect(open.written == open.textView.text)
        #expect(photographs.problem == nil)
    }

    // A picture is an edit like any other, and the day it is in is full of
    // typing: shaking to undo after adding the wrong photograph should take
    // back the picture, not the sentence before it.
    @Test("a photograph can be undone like anything else typed")
    func undoingAPhotograph() async throws {
        let store = InMemoryJournalStore()
        let day = try await open(EntryEditor(store: store))
        let photographs = InsertedPhotographs(picking: { _ in self.photograph(as: .png) })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.photographs = photographs
        open.cursor(at: 4)
        await open.coordinator.insertAPhotograph(in: open.textView)?.value

        let undo = try #require(open.textView.undoManager)
        #expect(undo.canUndo)
        undo.undo()

        #expect(open.textView.text == "Milk")
        // The file stays where it was written, deliberately: nothing in v1
        // takes a file out of the Journal Root, and an undo that deleted
        // somebody's photograph would be the app doing what it promises never
        // to do (ADR 0001).
        #expect(try await store.listFiles().count == 1)
    }

    // A photograph that inserted nothing without saying why is the one outcome
    // somebody would sit and repeat — and the folder failing is exactly when
    // they would.
    @Test("a folder that will not take it says so, and writes nothing in the day")
    func aFolderThatRefuses() async throws {
        let day = try await open(EntryEditor(store: AFolderThatRefusesToBeWrittenTo()))
        let photographs = InsertedPhotographs(picking: { _ in self.photograph(as: .png) })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.photographs = photographs
        open.cursor(at: 4)

        await open.coordinator.insertAPhotograph(in: open.textView)?.value

        #expect(open.textView.text == "Milk")
        #expect(open.written == nil)
        #expect(photographs.problem != nil)
    }

    // The picker was put away without choosing anything, which is not a
    // failure and not a notice — it is the commonest thing that happens after
    // a picker is opened.
    @Test("a picker nobody chose from leaves the day exactly as it was")
    func aPickerNobodyChoseFrom() async throws {
        let day = try await open(EntryEditor(store: InMemoryJournalStore()))
        let photographs = InsertedPhotographs(picking: { _ in nil })
        photographs.adds(to: day)

        let open = OpenEditor(holding: "Milk")
        open.coordinator.photographs = photographs
        open.cursor(at: 4)

        await open.coordinator.insertAPhotograph(in: open.textView)?.value

        #expect(open.textView.text == "Milk")
        #expect(photographs.problem == nil)
    }

    // MARK: - The control itself

    // The row is built once, with the editor, so what makes the photograph
    // control live is being handed a way to add one at all.
    @Test("the editor offers the photograph control exactly when there is a day to add one to")
    func theControlIsOffered() throws {
        let withoutAnEntry = OpenEditor(holding: "Milk")
        #expect(try !photoControl(of: withoutAnEntry).isEnabled)

        let overADay = OpenEditor(holding: "Milk", addingPhotographs: InsertedPhotographs())
        #expect(try photoControl(of: overADay).isEnabled)
    }

    private func photoControl(of editor: OpenEditor) throws -> UIButton {
        let row = try #require(editor.textView.inputAccessoryView as? MarkdownAccessoryRow)
        func buttons(in view: UIView) -> [UIButton] {
            view.subviews.flatMap { subview in
                (subview as? UIButton).map { [$0] } ?? buttons(in: subview)
            }
        }
        return try #require(
            buttons(in: row).first { $0.accessibilityIdentifier == "insertPhoto" }
        )
    }

    // MARK: - A day to add one to

    /// An Entry open over a folder, which is what a photograph is added to.
    private func open(_ editor: EntryEditor) async throws -> EntryEditor {
        await editor.open()
        try #require(editor.state.isEditing)
        return editor
    }

    /// A photograph in the format a test means to hand over. The UI suite needs
    /// exactly the same thing, and it is drawn where that one can reach it.
    private func photograph(as type: UTType, orientation: Int? = nil) -> Data? {
        UITestingJournal.photograph(as: type, orientation: orientation)
    }

    private func format(of photograph: Data) -> String? {
        CGImageSourceCreateWithData(photograph as CFData, nil)
            .flatMap { CGImageSourceGetType($0) as String? }
    }

    private func orientation(of photograph: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(photograph as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyOrientation] as? Int
    }
}

/// A folder that will not be written to — a disk that filled up, an iCloud
/// container that has gone.
private struct AFolderThatRefusesToBeWrittenTo: JournalStore {
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
