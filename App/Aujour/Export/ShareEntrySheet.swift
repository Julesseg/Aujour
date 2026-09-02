import AujourCore
import SwiftUI

/// The way a day leaves the app: the two things it can leave as, the page it
/// would leave as, and the hand-off to everywhere on the device.
///
/// A sheet rather than a menu of two items, because the choice is not one
/// anybody can make from the names. A **PDF** is the day to read — mailed to
/// somebody, or printed. **Plain text** is the day to keep working on — pasted
/// into a message, or dropped into another vault. Which one somebody wants is
/// a question about what the thing will *look like* at the other end, so the
/// sheet answers it by showing them.
///
/// Nothing here decides what is in either file. Which day and what it says is
/// ``AujourCore/EntryExport``'s, what a page looks like is ``EntryPaper``'s,
/// and writing it out is ``SharedEntry``'s — the same three as before, in the
/// same order. What is added is a look at the result before it goes.
struct ShareEntrySheet: View {
    /// This day as the thing it would be sent as — taken when the sheet came
    /// up, so that the page previewed and the file handed over are the same
    /// words. The editor is behind this sheet and nobody is typing into it.
    let export: EntryExport

    /// The photographs the day on screen has already found, so that the page
    /// carries the pictures the screen does.
    let pictures: EmbeddedPictures

    /// This day on its way out — asked to write the file, and holding it while
    /// the system's sheet is up.
    ///
    /// Bindable because the system's sheet comes up over the file it is
    /// holding, and goes down by letting go of it.
    @Bindable var shared: SharedEntry

    /// Which of the two forms is being looked at. A PDF to begin with: it is
    /// the one somebody who has not thought about it wants, and the one the
    /// preview has the most to say about.
    @State private var form: EntryExport.Form = .pdf

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.apart) {
            Text("Share \(export.title())")
                .lettering(.sheetTitle)
                .foregroundStyle(Palette.inkColor)
                .accessibilityIdentifier("shareEntryTitle")

            // The platform's own segmented control, like the ones on the
            // appearance page: that screen is where the token layer was proved
            // and it left these deliberately untokenised, so a second
            // segmented idiom here would be this sheet deciding something the
            // app had already decided.
            Picker("How to send it", selection: $form) {
                ForEach(EntryExport.Form.asOffered, id: \.self) { form in
                    Text(form.name).tag(form)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("shareEntryForm")

            ThePageItWouldLeaveAs(export: export, form: form, pictures: pictures)
                .frame(maxWidth: .infinity)

            Note(form.previewCaption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if let problem = shared.problem {
                // A share that quietly did nothing is the one outcome somebody
                // would sit and repeat, and this is where they are standing
                // when it happens.
                SharingProblemNotice(problem: problem)
            }

            Spacer(minLength: 0)

            handOff
        }
        .padding(Spacing.apart)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The system's own screen, over the file Aujour has just written — put
        // up from here rather than from the Entry behind, because a sheet
        // cannot present anything while another one is covering it.
        .sheet(item: $shared.file) { file in
            ShareSheet(file: file)
        }
        .onChange(of: shared.file) { before, now in
            // The day has been handed over and the user is finished with the
            // system's sheet, so this one has done its job too — leaving it up
            // would be the app asking again how to send what it just sent.
            guard before != nil, now == nil else { return }
            dismiss()
        }
        // A failure belongs to the sheet it happened on. Left behind, it would
        // be waiting on the next one somebody opened, about a share they had
        // already given up on.
        .onDisappear { shared.acknowledge() }
        // Full height. The page being previewed is the point of the sheet,
        // and a preview small enough to fit in half a screen is a preview
        // nobody can tell two forms apart from.
        .presentationDetents([.large])
    }

    /// The button that writes the file and puts the system's sheet up over it.
    ///
    /// The file is made *before* the sheet comes up — the PDF drawn, the
    /// photographs it embeds waited for, the bytes on disk — so what the user
    /// hands to Mail or to Files or to a printer is a finished document rather
    /// than a promise to make one.
    @ViewBuilder private var handOff: some View {
        if shared.isPreparing {
            // In the button's own place, so nothing moves: a PDF of a long day
            // with photographs in it takes a moment, and a button that looks
            // idle is one somebody presses again.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.close)
                .accessibilityIdentifier("preparingShare")
        } else {
            Button {
                Task { await shared.share(export, as: form, drawnWith: pictures) }
            } label: {
                // The one thing to press on this sheet, drawn the way the
                // welcome draws the one thing to press on a page of its own:
                // the accent filled, the word on it in the ink the identity
                // keeps for words on the accent (ADR 0006).
                Text("Share")
                    .lettering(.rowLabel)
                    .foregroundStyle(Palette.onAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.comfortable)
                    .background(.tint, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .elevated(.resting)
            .accessibilityIdentifier("shareEntryNow")
        }
    }
}

extension EntryExport.Form {
    /// The order the two are offered in: the day to read, and then the day to
    /// keep working on. Written out rather than taken off `allCases`, because
    /// the order a control reads in is the screen's business — and a test
    /// holds this to every form there is, so a third cannot arrive with no way
    /// to pick it.
    static let asOffered: [EntryExport.Form] = [.pdf, .plainText]

    /// What a user is offered this form as.
    var name: String {
        switch self {
        case .pdf: "PDF"
        case .plainText: "Plain Text"
        }
    }

    /// What the preview above it is showing.
    var previewCaption: String {
        switch self {
        case .pdf: "The page as it will arrive — your own typography, set for print."
        case .plainText: "The day's own characters, exactly as the file holds them."
        }
    }
}

/// The day as the thing it would be sent as, small enough to hold.
///
/// The two forms preview as the two different things they are. A **PDF** is
/// the first page of the document itself, drawn by the same ``EntryPaper``
/// that writes the file — so what is on screen is the file and not an
/// impression of it. **Plain text** is the Entry's own characters, in a face
/// that shows them as characters: what makes that form worth choosing is that
/// the marks survive, and a preview that hid them would be previewing the
/// other one.
private struct ThePageItWouldLeaveAs: View {
    let export: EntryExport
    let form: EntryExport.Form
    let pictures: EmbeddedPictures

    /// The page, once it has been drawn — `nil` while the photographs it
    /// embeds are being found, and for a day that would not draw at all.
    ///
    /// The drawing itself is not something anybody waits through: `EntryPaper`
    /// is TextKit over a graphics context, so it is main-actor work exactly as
    /// the share it is previewing is. What the spinner covers is the folder
    /// read before it.
    @State private var page: UIImage?

    /// How tall the page is held, growing with the reader's text size like
    /// everything else — a preview that stayed put while the words around it
    /// doubled would be the smallest thing on the sheet.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 250

    var body: some View {
        paper
            .frame(height: height)
            .background(Palette.cardColor, in: RoundedRectangle(cornerRadius: Rounding.chip))
            .clipShape(RoundedRectangle(cornerRadius: Rounding.chip))
            .elevated(.floating)
            // Drawn once, when a page is what is being looked at: the words
            // were taken when the sheet came up, so the page they make is the
            // same page every time — and the plain text form needs no drawing
            // at all.
            //
            // The photographs the day embeds are waited for first, exactly as
            // the share itself waits for them. Without that the preview would
            // show `![the market](…)` where the file carries the photograph,
            // which is the one way a preview can lie about the document it is
            // previewing.
            .task(id: form) {
                guard form == .pdf, page == nil else { return }
                await pictures.findEverything(embeddedIn: export.markdown)
                page = EntryPaper(pictures: pictures).firstPage(of: export)
            }
            .accessibilityIdentifier("sharePreview")
            // What a picture of a page cannot say out loud.
            .accessibilityLabel("A preview of \(export.title())")
    }

    @ViewBuilder private var paper: some View {
        switch form {
        case .pdf:
            if let page {
                Image(uiImage: page)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .plainText:
            Text(export.markdown)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.inkColor)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Spacing.comfortable)
        }
    }
}

/// A day that could not be got ready to send, said on the sheet that asked for
/// it.
///
/// In the alarm ink and not the ordinary one: nothing about the journal has
/// gone wrong — the Entry is where it was — but the thing the user asked for
/// did not happen, and a share that quietly did nothing is the one outcome
/// somebody would sit and repeat.
private struct SharingProblemNotice: View {
    let problem: StorageProblem

    var body: some View {
        ProblemNotice(
            saying: problem.message,
            suggestion: problem.suggestion,
            identifier: "shareProblemNotice",
            ink: Palette.alarmColor
        )
    }
}

#Preview("A day on its way out") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)

    Color.clear.sheet(isPresented: .constant(true)) {
        ShareEntrySheet(
            export: EntryExport(
                today,
                markdown: """
                    # Notes on the day

                    Woke before the alarm and the flat was already warm. Made \
                    coffee, sat by the window and did nothing for twenty minutes.

                    - [x] Water the fig
                    - [ ] Ring Robin
                    """
            ),
            pictures: EmbeddedPictures(),
            shared: SharedEntry()
        )
        .sheetChrome()
    }
}
