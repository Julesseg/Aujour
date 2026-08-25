import Foundation
import Testing

@testable import AujourCore

// The welcome is three pages and one promise: whatever the user does with it,
// the app is theirs to write in the moment it is over, and nothing has been
// turned on that they did not turn on. So what there is to get right is which
// page is on screen, that ending it ends it for good, and that the reminder is
// set only by somebody taking the offer up.

@MainActor
@Suite("The welcome")
struct WelcomeTests {
    // MARK: - Whether there is a welcome at all

    @Test("a device nobody has welcomed is due one, on the first page")
    func dueOnAFreshInstall() {
        let welcome = aWelcome()

        #expect(welcome.isDue)
        #expect(welcome.page == .whatThisIs)
    }

    @Test("a device that has been through it is not due another")
    func notDueAfterwards() {
        let storage = InMemoryLocalKeyValueStore()
        let settings = DeviceSettingsStore(storedOn: storage)
        settings.update { $0.hasBeenWelcomed = true }

        #expect(!aWelcome(settings: settings).isDue)
    }

    @Test("a welcome that is over is over in the next launch too")
    func overForGood() async {
        let storage = InMemoryLocalKeyValueStore()
        let welcome = aWelcome(settings: DeviceSettingsStore(storedOn: storage))

        await welcome.end(remindingAt: nil)

        #expect(!welcome.isDue)
        // The next launch reads the same storage and finds the same answer:
        // a welcome is a thing that happens once per device, and one that came
        // back every launch would be the app introducing itself to somebody
        // who lives in it.
        #expect(!aWelcome(settings: DeviceSettingsStore(storedOn: storage)).isDue)
    }

    // MARK: - Moving through it

    @Test("the pages come in order and can be gone back over")
    func forwardsAndBack() {
        let welcome = aWelcome()

        welcome.next()
        #expect(welcome.page == .whereYourWordsGo)
        welcome.next()
        #expect(welcome.page == .theDailyReminder)

        welcome.back()
        #expect(welcome.page == .whereYourWordsGo)
        welcome.back()
        #expect(welcome.page == .whatThisIs)
    }

    @Test("the ends of it hold: there is nothing before the first page or after the last")
    func theEndsHold() {
        let welcome = aWelcome()

        welcome.back()
        #expect(welcome.page == .whatThisIs)

        welcome.next()
        welcome.next()
        #expect(welcome.isOnTheLastPage)
        welcome.next()
        #expect(welcome.page == .theDailyReminder)
        // And going on past the last page is not a way out of the welcome:
        // ending it is a thing the user does, and only `end` does it.
        #expect(welcome.isDue)
    }

    // MARK: - The offer on the last page

    @Test("a time taken up sets the reminder, and asks to be allowed to keep it")
    func takingTheOfferUp() async {
        let device = ADeviceToBeAskedOnce()
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let welcome = aWelcome(settings: settings, nudges: device)

        await welcome.end(remindingAt: TimeOfDay(hour: 21, minute: 0))

        #expect(settings.settings.dailyReminder == TimeOfDay(hour: 21, minute: 0))
        #expect(await device.timesAsked == 1)
        #expect(!welcome.isDue)
    }

    @Test("skipping it leaves the reminder off, and asks the device nothing at all")
    func skippingTheOffer() async {
        let device = ADeviceToBeAskedOnce()
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let welcome = aWelcome(settings: settings, nudges: device)

        await welcome.end(remindingAt: nil)

        // The whole of the promise: a fresh install has never nudged anybody
        // who did not ask it to, and a permission alert nobody invited is the
        // first thing an App Store product must not do.
        #expect(settings.settings.dailyReminder == nil)
        #expect(await device.timesAsked == 0)
        #expect(!welcome.isDue)
    }

    @Test("a device that says no keeps the welcome up, and declining takes the time back off")
    func aDeviceThatSaysNo() async {
        let device = ADeviceToBeAskedOnce(answering: .refused)
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let welcome = aWelcome(settings: settings, nudges: device)
        welcome.next()
        welcome.next()

        await welcome.end(remindingAt: TimeOfDay(hour: 21, minute: 0))

        // Still here, and still on the page with the offer on it: a reminder
        // the device will not deliver is one somebody has to be told about,
        // and a welcome that had closed over it would have left them believing
        // they set one up.
        #expect(welcome.isDue)
        #expect(welcome.page == .theDailyReminder)
        #expect(await device.timesAsked == 1)

        // And the way on from there is the one already on screen. Declining
        // takes the time with it: a time set on a device that will not ring is
        // not a reminder, and leaving it written down would be a setting the
        // journal sheet showed as on.
        await welcome.end(remindingAt: nil)

        #expect(!welcome.isDue)
        #expect(settings.settings.dailyReminder == nil)
    }

    @Test("it can be left from any page, and leaving it turns nothing on")
    func leftFromTheFirstPage() async {
        let device = ADeviceToBeAskedOnce()
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let welcome = aWelcome(settings: settings, nudges: device)

        #expect(welcome.page == .whatThisIs)
        await welcome.end(remindingAt: nil)

        #expect(!welcome.isDue)
        #expect(settings.settings.dailyReminder == nil)
        #expect(await device.timesAsked == 0)
    }

    // MARK: -

    private func aWelcome(
        settings: DeviceSettingsStore? = nil,
        nudges: any Nudges = ADeviceToBeAskedOnce()
    ) -> Welcome {
        let settings = settings ?? DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        return Welcome(
            settings: settings,
            reminder: DailyReminder(settings: settings, nudges: nudges)
        )
    }
}

/// A device that counts the times it was asked, which is what the welcome's
/// two answers differ by: taking the offer up is the one moment Aujour has a
/// reason to want a notification permission, and skipping it is not one.
private actor ADeviceToBeAskedOnce: Nudges {
    private(set) var timesAsked = 0

    /// Undecided until it is asked, like a device nobody has answered for yet.
    private var permission: NudgeAccess = .undecided

    /// What it says when it is.
    private let answering: NudgeAccess

    init(answering: NudgeAccess = .allowed) {
        self.answering = answering
    }

    func access() async -> NudgeAccess { permission }

    func ask() async -> NudgeAccess {
        timesAsked += 1
        permission = answering
        return permission
    }

    func book(_ nudges: [Nudge]) async {}
}
