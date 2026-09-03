import AujourCore
import SwiftUI
import UIKit

// PROTOTYPE — THROWAWAY. Not shipped, not tested, not tidy.
//
// One question: can the date pill move up into the navigation bar's row and
// share it with the trailing overflow button — and if it cannot, where should
// the overflow go instead?
//
// Four variants on the app's existing header, switchable from the floating bar
// at the bottom. Everything is drawn with the real tokens, the real lettering
// and the real strings, because the whole question is one of *width* and a
// mock with approximate type would answer it wrong.
//
// Three things widen the pill and all of them are on the pickers, because the
// day the app opens on is the narrowest case it ever has:
//
//   - Dynamic Type. Chrome follows the system size (`Lettering`), so the day
//     grows with it.
//   - A day that is not today, which puts a "Today" chip inside the pill.
//   - A day in another year, which spells the year out too.
//
// And the width to fit it in is the *device's*: CI's iPhone leg is an SE at
// 320pt, not the 402pt phone this gets looked at on.

// MARK: - The variants

enum HeaderVariant: String, CaseIterable, Identifiable {
    case pillBesideTheMenu = "A"
    case menuAtTheBottom = "B"
    case theMenuIsInThePill = "C"
    case theDateShortens = "D"
    case shortensAsItMust = "E"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pillBesideTheMenu: "Pill in the bar, menu beside it"
        case .menuAtTheBottom: "Pill has the bar, menu at the bottom"
        case .theMenuIsInThePill: "Pill in the bar, menu inside the pill"
        case .theDateShortens: "Pill in the bar, date always shortened"
        case .shortensAsItMust: "Pill in the bar, shortening only as it must"
        }
    }

    /// What it is actually proposing, in the one sentence that would go in the
    /// decisions file if it won.
    var claim: String {
        switch self {
        case .pillBesideTheMenu:
            "The row holds both. Costs whatever width the ellipsis takes, every day."
        case .menuAtTheBottom:
            "The bar is the day and nothing else; everything you can *do* moves to the bottom edge, where the thumbs are."
        case .theMenuIsInThePill:
            "One control on the bar. The pill names the day, opens the calendar, and carries the rest behind a second glyph."
        case .theDateShortens:
            "Both, by giving up the spelled-out day: \u{201C}Wed 2 Sep\u{201D} while it shares the row."
        case .shortensAsItMust:
            "Both, and the day stays spelled out wherever it fits: the pill gives up a word at a time, and only when the room runs out."
        }
    }
}

// MARK: - What is being measured

/// How wide the closed pill wants to be, measured rather than worked out —
/// the real view, hosted and asked.
@MainActor
func widthWanted(by pill: some View, at size: DynamicTypeSize) -> CGFloat {
    let host = UIHostingController(rootView: pill.dynamicTypeSize(size))
    host.view.backgroundColor = .clear
    return host.sizeThatFits(in: CGSize(width: 2000, height: 2000)).width
}

/// The phones this has to fit on. The SE is the one that decides it.
let phones: [(name: String, width: CGFloat)] = [
    ("SE (CI's leg)", 320),
    ("13 mini", 375),
    ("17", 402),
    ("17 Pro Max", 440),
]

/// What the bar spends on things that are not the pill.
enum Bar {
    /// The inset at each end of a navigation bar.
    static let edge: CGFloat = 20
    /// The overflow button — a 44pt tap target, which is the floor.
    static let menu: CGFloat = 44
    /// The gap between the pill and the button.
    static let gap = Spacing.close
}

// MARK: - The prototype

struct PrototypeTheHeader: View {
    @State private var variant: HeaderVariant = .pillBesideTheMenu
    @State private var phone = 0
    @State private var textSize: DynamicTypeSize = .large
    @State private var day: DayOnThePill = .today

    /// Which day the pill is naming, since that is what its width is made of.
    enum DayOnThePill: String, CaseIterable, Identifiable {
        case today = "Today"
        case backfilled = "A day this year"
        case yearsBack = "A day years back"

        var id: String { rawValue }

        /// A "Today" chip sits inside the pill on any day that is not today.
        var hasTodayChip: Bool { self != .today }

        var named: String {
            switch self {
            case .today: "Thursday, 3 September"
            case .backfilled: "Saturday, 14 February"
            case .yearsBack: "Saturday, 14 February 2021"
            }
        }

        /// The same day, given up on being spelled out.
        var shortened: String { forms.last ?? named }

        /// Every length the pill could name this day at, longest first.
        ///
        /// Built with the same `Date.FormatStyle` the app's own `spelledOut`
        /// uses rather than written out, so the ladder is as true in French as
        /// it is in English — which is the whole reason a fallback can be
        /// trusted to have somewhere to fall to.
        var forms: [String] {
            let date =
                Calendar(identifier: .gregorian)
                .date(from: components) ?? .now
            let year = self == .yearsBack

            return [
                style(weekday: .wide, month: .wide, year: year),
                style(weekday: .abbreviated, month: .wide, year: year),
                style(weekday: .abbreviated, month: .abbreviated, year: year),
                style(weekday: nil, month: .abbreviated, year: year),
            ].map { date.formatted($0) }
        }

        private var components: DateComponents {
            switch self {
            case .today: DateComponents(year: 2026, month: 9, day: 3)
            case .backfilled: DateComponents(year: 2026, month: 2, day: 14)
            case .yearsBack: DateComponents(year: 2021, month: 2, day: 14)
            }
        }

        private func style(
            weekday: Date.FormatStyle.Symbol.Weekday?,
            month: Date.FormatStyle.Symbol.Month,
            year: Bool
        ) -> Date.FormatStyle {
            var style = Date.FormatStyle(locale: .current, timeZone: .current)
                .day()
                .month(month)
            if let weekday { style = style.weekday(weekday) }
            if year { style = style.year() }
            return style
        }
    }

    private var width: CGFloat { phones[phone].width }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.backgroundColor.ignoresSafeArea()

            VStack(spacing: Spacing.apart) {
                pickers
                theHeader
                readout
                Spacer(minLength: 90)
            }
            .padding(Spacing.apart)

            switcher
        }
        .dynamicTypeSize(textSize)
    }

    // MARK: The header, four ways

    private var theHeader: some View {
        VStack(spacing: 0) {
            switch variant {
            case .pillBesideTheMenu:
                barRow { PrototypePill(naming: day.named, todayChip: day.hasTodayChip) }
                thePageUnder
            case .menuAtTheBottom:
                HStack {
                    PrototypePill(naming: day.named, todayChip: day.hasTodayChip)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Bar.edge)
                .frame(height: 54)
                thePageUnder
                HStack {
                    Spacer()
                    PrototypeMenuButton()
                }
                .padding(.horizontal, Bar.edge)
                .padding(.vertical, Spacing.close)
            case .theMenuIsInThePill:
                HStack {
                    PrototypePill(
                        naming: day.named,
                        todayChip: day.hasTodayChip,
                        carryingTheMenu: true
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Bar.edge)
                .frame(height: 54)
                thePageUnder
            case .theDateShortens:
                barRow { PrototypePill(naming: day.shortened, todayChip: day.hasTodayChip) }
                thePageUnder
            case .shortensAsItMust:
                barRow { PrototypeAdaptivePill(day: day, chip: .aCalendar) }
                thePageUnder
            }
        }
        .frame(width: width)
        .background(Palette.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.ruleColor))
        .frame(maxWidth: .infinity)
    }

    /// The bar as the app draws it: the pill, then whatever room is left, then
    /// the button pinned to the trailing end.
    private func barRow(@ViewBuilder _ pill: () -> some View) -> some View {
        HStack(spacing: Bar.gap) {
            pill()
            Spacer(minLength: 0)
            PrototypeMenuButton()
        }
        .padding(.horizontal, Bar.edge)
        .frame(height: 54)
    }

    /// Enough of a day's writing under it to judge the header against, because
    /// a header on a blank rectangle always looks fine.
    private var thePageUnder: some View {
        Text(
            """
            Woke before the alarm and the flat was already warm. Made coffee, \
            sat by the window and did nothing for twenty minutes.

            The trees are doing that late-summer thing where they look tired.
            """
        )
        .lettering(.prose)
        .foregroundStyle(Palette.inkColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.apart)
        .frame(height: 190, alignment: .top)
    }

    // MARK: Surfacing the state

    /// The whole point: what the pill wants, what the bar has, and whether one
    /// fits in the other — for this phone and every phone, since the one being
    /// looked at is never the one that breaks.
    private var readout: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            Text(variant.claim)
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)

            Hairline()

            ForEach(phones, id: \.name) { phone in
                let wanted = wantedWidth
                let room = roomFor(phone.width)
                HStack(spacing: Spacing.close) {
                    Text(phone.name)
                        .lettering(.rowValue)
                        .foregroundStyle(Palette.inkMutedColor)
                        .frame(width: 110, alignment: .leading)
                    Text("wants \(Int(wanted.rounded()))pt")
                        .lettering(.note)
                        .foregroundStyle(Palette.inkMutedColor)
                    Text("has \(Int(room.rounded()))pt")
                        .lettering(.note)
                        .foregroundStyle(Palette.inkMutedColor)
                    Spacer(minLength: 0)
                    Text(wanted <= room ? "fits" : "shrinks \(Int((wanted - room).rounded()))pt")
                        .lettering(.chipLabel)
                        .foregroundStyle(wanted <= room ? Palette.inkColor : Palette.alarmColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wantedWidth: CGFloat {
        switch variant {
        case .pillBesideTheMenu:
            widthWanted(
                by: PrototypePill(naming: day.named, todayChip: day.hasTodayChip),
                at: textSize
            )
        case .theDateShortens:
            widthWanted(
                by: PrototypePill(naming: day.shortened, todayChip: day.hasTodayChip),
                at: textSize
            )
        case .theMenuIsInThePill:
            widthWanted(
                by: PrototypePill(
                    naming: day.named,
                    todayChip: day.hasTodayChip,
                    carryingTheMenu: true
                ),
                at: textSize
            )
        case .menuAtTheBottom, .shortensAsItMust:
            widthWanted(
                by: PrototypePill(naming: day.named, todayChip: day.hasTodayChip),
                at: textSize
            )
        }
    }

    /// How much of the row the pill actually gets. Only the variants that put
    /// a button beside it pay for one.
    private func roomFor(_ deviceWidth: CGFloat) -> CGFloat {
        switch variant {
        case .pillBesideTheMenu, .theDateShortens, .shortensAsItMust:
            deviceWidth - Bar.edge * 2 - Bar.menu - Bar.gap
        case .menuAtTheBottom, .theMenuIsInThePill:
            deviceWidth - Bar.edge * 2
        }
    }

    // MARK: Driving it

    private var pickers: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            Picker("Phone", selection: $phone) {
                ForEach(phones.indices, id: \.self) { Text(phones[$0].name).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Day", selection: $day) {
                ForEach(DayOnThePill.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Text size", selection: $textSize) {
                Text("XS").tag(DynamicTypeSize.xSmall)
                Text("L").tag(DynamicTypeSize.large)
                Text("XXL").tag(DynamicTypeSize.xxLarge)
                Text("A11y 1").tag(DynamicTypeSize.accessibility1)
                Text("A11y 3").tag(DynamicTypeSize.accessibility3)
            }
            .pickerStyle(.segmented)
        }
        // The pickers drive the prototype and are not part of what is being
        // judged, so they never move with the size being tried out.
        .dynamicTypeSize(.large)
    }

    private var switcher: some View {
        HStack(spacing: Spacing.comfortable) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            VStack(spacing: 0) {
                Text("\(variant.rawValue) — \(variant.name)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 230)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, Spacing.apart)
        .padding(.vertical, Spacing.comfortable)
        .background(.black, in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 12, y: 4)
        .padding(.bottom, Spacing.apart)
        .dynamicTypeSize(.large)
    }

    private func step(_ by: Int) {
        let all = HeaderVariant.allCases
        let at = all.firstIndex(of: variant) ?? 0
        variant = all[(at + by + all.count) % all.count]
    }
}

// MARK: - Stand-ins

/// The closed pill, rebuilt with the real tokens: the "Today" chip when the
/// day is not today, the day, and the chevron. A replica rather than the real
/// `DatePillView`, which needs a live `JournalCalendar` — what is being
/// measured is its *width*, and that is made of these three things.
/// How the way back to today is drawn inside the pill.
enum TodayChip: String, CaseIterable, Identifiable {
    /// As it ships: the glyph and the word.
    case theWord = "↰ Today"
    /// The word given up, a calendar left in its place.
    case aCalendar = "calendar"
    /// The same, said with the glyph the word came with.
    case theArrow = "↰"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .theWord, .theArrow: "arrow.uturn.forward"
        case .aCalendar: "calendar"
        }
    }

    var saysTheWord: Bool { self == .theWord }
}

struct PrototypePill: View {
    let naming: String
    var todayChip = false
    var chip: TodayChip = .theWord
    var carryingTheMenu = false

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.close) {
            if todayChip {
                theWayBackToToday
            }
            Text(naming)
                .lettering(.dayOnScreen)
                .foregroundStyle(Palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkFaintColor)

            if carryingTheMenu {
                Rectangle()
                    .fill(Palette.ruleColor)
                    .frame(width: 1, height: 18)
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMutedColor)
            }
        }
        .padding(.horizontal, Spacing.comfortable)
        .frame(height: height)
        .glassEffect(.regular, in: Capsule())
    }

    /// Whatever it is drawn as, it is still "Today" to anything that reads the
    /// screen out — a chip that lost its name along with its word would be a
    /// control nobody could ask for.
    @ViewBuilder private var theWayBackToToday: some View {
        Group {
            if chip.saysTheWord {
                Label("Today", systemImage: chip.symbol)
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Today", systemImage: chip.symbol)
                    .labelStyle(.iconOnly)
            }
        }
        .imageScale(.small)
        .lettering(.chipLabel)
        .foregroundStyle(Accent.driftwood.ink)
        .padding(.horizontal, chip.saysTheWord ? Spacing.comfortable : Spacing.close)
        .padding(.vertical, Spacing.tight)
        .background(Accent.driftwood.soft, in: Capsule())
        .accessibilityLabel("Today")
    }
}

private struct PrototypeMenuButton: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.inkColor)
            .frame(width: Bar.menu, height: Bar.menu)
            .glassEffect(.regular, in: Circle())
    }
}

// MARK: - The same question, answered headlessly

/// The measurements as a table, so the answer is a number rather than a
/// squint at a canvas. Printed by a throwaway test; nothing ships this.
@MainActor
enum PrototypeMeasurements {
    static func table() -> String {
        var lines: [String] = []
        let sizes: [(String, DynamicTypeSize)] = [
            ("XS", .xSmall), ("L (factory)", .large), ("XXL", .xxLarge),
            ("A11y1", .accessibility1), ("A11y3", .accessibility3),
        ]
        let days: [(String, String, Bool)] = [
            ("today", "Thursday, 3 September", false),
            ("a day this year", "Saturday, 14 February", true),
            ("a day years back", "Saturday, 14 February 2021", true),
        ]

        // What the chip itself costs, which is the thing being traded.
        lines.append("=== the way back to today, on its own ===")
        for chip in TodayChip.allCases {
            var row = "\(chip.rawValue)".padding(toLength: 12, withPad: " ", startingAt: 0)
            for (sizeName, size) in sizes where sizeName == "L (factory)" || sizeName == "XXL" {
                let wide = widthWanted(
                    by: PrototypePill(naming: "x", todayChip: true, chip: chip), at: size
                )
                let bare = widthWanted(by: PrototypePill(naming: "x"), at: size)
                row += "\(sizeName): \(Int((wide - bare).rounded()))pt   "
            }
            lines.append(row)
        }

        for chip in TodayChip.allCases {
            for (dayName, naming, hasChip) in days {
                // A day that is today has no chip at all, so it is only worth
                // saying once.
                if !hasChip, chip != .theWord { continue }
                lines.append("")
                lines.append(
                    "=== \(dayName)\(hasChip ? ", chip as \(chip.rawValue)" : "") ==="
                )
                lines.append("size          wants   SE|A   SE|B   17|A   17|B")
                for (sizeName, size) in sizes {
                    let wanted = widthWanted(
                        by: PrototypePill(naming: naming, todayChip: hasChip, chip: chip),
                        at: size
                    )
                    var row = sizeName.padding(toLength: 14, withPad: " ", startingAt: 0)
                    row += "\(Int(wanted.rounded()))pt".padding(
                        toLength: 8, withPad: " ", startingAt: 0
                    )
                    for width in [CGFloat(320), CGFloat(402)] {
                        // A: the pill shares the row with the menu.
                        // B: the pill has the whole bar.
                        for room in [
                            width - Bar.edge * 2 - Bar.menu - Bar.gap,
                            width - Bar.edge * 2,
                        ] {
                            let verdict =
                                wanted <= room ? "fits" : "-\(Int((wanted - room).rounded()))"
                            row += verdict.padding(toLength: 7, withPad: " ", startingAt: 0)
                        }
                    }
                    lines.append(row)
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - A contact sheet, for looking at rather than driving

/// Every variant at both widths, side by side, with the fit under each — the
/// thing to look at when the question is "can I see it?" rather than "let me
/// poke it".
struct PrototypeContactSheet: View {
    let chip: TodayChip
    let day: PrototypeTheHeader.DayOnThePill

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.apart) {
            Text("The bar, four ways — \(day.rawValue.lowercased()), chip as \(chip.rawValue)")
                .lettering(.sheetTitle)
                .foregroundStyle(Palette.inkColor)

            ForEach(HeaderVariant.allCases) { variant in
                VStack(alignment: .leading, spacing: Spacing.close) {
                    Text("\(variant.rawValue) — \(variant.name)")
                        .lettering(.sectionHeader)
                        .foregroundStyle(Palette.inkFaintColor)
                    HStack(alignment: .top, spacing: Spacing.apart) {
                        ForEach([CGFloat(320), CGFloat(402)], id: \.self) { width in
                            VStack(alignment: .leading, spacing: Spacing.tight) {
                                PrototypeHeaderBlock(
                                    variant: variant, chip: chip, day: day, width: width
                                )
                                Text(verdict(variant, width))
                                    .lettering(.note)
                                    .foregroundStyle(Palette.inkMutedColor)
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.apart)
        .background(Palette.backgroundColor)
    }

    private func verdict(_ variant: HeaderVariant, _ width: CGFloat) -> String {
        let phone = width == 320 ? "SE 320" : "17 402"
        if variant == .shortensAsItMust {
            let room = width - Bar.edge * 2 - Bar.menu - Bar.gap
            let forms = day.forms
            for (rung, form) in forms.enumerated() {
                let wanted = widthWanted(
                    by: PrototypePill(naming: form, todayChip: day.hasTodayChip, chip: chip),
                    at: .large
                )
                if wanted <= room {
                    return
                        "\(phone): says \u{201C}\(form)\u{201D} — rung \(rung + 1) of \(forms.count)"
                }
            }
            return "\(phone): shortest form still over"
        }
        let wanted = widthWanted(
            by: PrototypePill(
                naming: variant == .theDateShortens ? day.shortened : day.named,
                todayChip: day.hasTodayChip,
                chip: chip,
                carryingTheMenu: variant == .theMenuIsInThePill
            ),
            at: .large
        )
        let room: CGFloat =
            switch variant {
            case .pillBesideTheMenu, .theDateShortens, .shortensAsItMust:
                width - Bar.edge * 2 - Bar.menu - Bar.gap
            case .menuAtTheBottom, .theMenuIsInThePill:
                width - Bar.edge * 2
            }
        let over = wanted - room
        return over <= 0
            ? "\(phone): fits, \(Int(-over))pt spare"
            : "\(phone): \(Int(over))pt over — shrinks to \(Int(room / wanted * 100))%"
    }
}

/// The pill, saying the day as fully as the room allows.
///
/// `ViewThatFits` and not a measurement of our own: it proposes the room to
/// each candidate in turn and takes the first that does not need more, which is
/// exactly the question — and it asks it again when the room changes, so a
/// rotation or a text-size change re-answers it without anything having to
/// notice.
///
/// The ladder is longest first. What it gives up, in order: the weekday's full
/// name, then the month's, then the weekday altogether. The day and the month
/// are the last things standing, because a date with no number is not a date.
struct PrototypeAdaptivePill: View {
    let day: PrototypeTheHeader.DayOnThePill
    let chip: TodayChip

    var body: some View {
        let forms = day.forms
        ViewThatFits(in: .horizontal) {
            pill(forms[0])
            pill(forms[1])
            pill(forms[2])
            pill(forms[3])
        }
    }

    private func pill(_ naming: String) -> some View {
        PrototypePill(naming: naming, todayChip: day.hasTodayChip, chip: chip)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// One variant's bar, at one width, over enough of a day to judge it against.
struct PrototypeHeaderBlock: View {
    let variant: HeaderVariant
    let chip: TodayChip
    let day: PrototypeTheHeader.DayOnThePill
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            switch variant {
            case .pillBesideTheMenu:
                bar { pill(naming: day.named) }
            case .theDateShortens:
                bar { pill(naming: day.shortened) }
            case .shortensAsItMust:
                bar { PrototypeAdaptivePill(day: day, chip: chip) }
            case .menuAtTheBottom:
                HStack { pill(naming: day.named) }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Bar.edge)
                    .frame(height: 54)
            case .theMenuIsInThePill:
                HStack { pill(naming: day.named, carryingTheMenu: true) }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Bar.edge)
                    .frame(height: 54)
            }

            words

            if variant == .menuAtTheBottom {
                HStack {
                    Spacer()
                    PrototypeMenuButton()
                }
                .padding(.horizontal, Bar.edge)
                .padding(.bottom, Spacing.close)
            }
        }
        .frame(width: width)
        .background(Palette.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.ruleColor))
    }

    private func pill(naming: String, carryingTheMenu: Bool = false) -> some View {
        PrototypePill(
            naming: naming,
            todayChip: day.hasTodayChip,
            chip: chip,
            carryingTheMenu: carryingTheMenu
        )
    }

    private func bar(@ViewBuilder _ pill: () -> some View) -> some View {
        HStack(spacing: Bar.gap) {
            pill()
            Spacer(minLength: 0)
            PrototypeMenuButton()
        }
        .padding(.horizontal, Bar.edge)
        .frame(height: 54)
    }

    private var words: some View {
        Text("Woke before the alarm and the flat was already warm. Made coffee.")
            .lettering(.prose)
            .foregroundStyle(Palette.inkColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.apart)
            .padding(.vertical, Spacing.comfortable)
            .frame(height: 80, alignment: .top)
    }
}

#Preview("Contact sheet") {
    ScrollView { PrototypeContactSheet(chip: .aCalendar, day: .backfilled) }
}

#Preview("The header, four ways") {
    PrototypeTheHeader()
}
