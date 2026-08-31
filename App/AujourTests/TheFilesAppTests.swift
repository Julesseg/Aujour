import Foundation
import Testing

@testable import Aujour

// The one way out of the app a Parked File gets: shown where it lies, in the
// app the folder actually belongs to. Aujour never opens one itself — reading
// two versions against each other is the user's work in their own editor
// (`CONTEXT.md`, Parked File).
//
// What can be held to anything headlessly is the address. Whether tapping it
// lands in the Files app is the device's answer, and a build machine has no
// way to ask.

@Suite("Showing a file where it lies")
struct TheFilesAppTests {
    @Test("a file in the journal is addressed to the Files app by its own path")
    func aFileIsAddressedByItsOwnPath() throws {
        let file = URL(filePath: "/private/var/mobile/Aujour/2026/03/2026-03-01_1.md")

        let shown = try #require(TheFilesApp.url(showing: file))

        #expect(shown.scheme == "shareddocuments")
        #expect(shown.path() == file.path())
    }

    @Test("a folder with a space in its name arrives with the space still in it")
    func aNameWithSpacesSurvivesTheTrip() throws {
        let file = URL(filePath: "/private/var/mobile/My Journal/2026-03-01_1.md")

        let shown = try #require(TheFilesApp.url(showing: file))

        #expect(shown.absoluteString.contains("My%20Journal"))
        #expect(shown.path() == file.path())
    }

    @Test("something that is not a file on this device is nowhere to send anybody")
    func onlyAFileOnThisDeviceCanBeShown() throws {
        let notAFile = try #require(URL(string: "https://example.com/2026-03-01_1.md"))

        #expect(TheFilesApp.url(showing: notAFile) == nil)
    }
}
