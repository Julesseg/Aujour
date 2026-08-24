import CoreLocation
import Foundation
import MapKit

import AujourCore

/// Where the device is, as the `{{location}}` widget reads it.
///
/// CoreLocation's half of ``AujourCore/Places``, and nothing besides: when the
/// widget looks, what it offers, and what answering writes are all decided
/// above this, over places that are said rather than found.
///
/// ## What "the current place" is made of
///
/// A coordinate is not a place — nobody writes 48.854, 2.333 in their journal.
/// So a fix is turned into words two ways at once, and both are handed up as
/// ``AujourCore/Surroundings``:
///
/// - **The points of interest around it**, within a short walk, nearest first
///   and each with how far off it is. A café, a park, a station: the specific
///   thing somebody means when they say where they were.
/// - **The address the coordinate reverse-geocodes to** — the neighbourhood,
///   or the town. Vaguer, and always there.
///
/// Which of them the widget leads with is not decided here. That is
/// ``AujourCore/Surroundings/toOffer``, unit-tested in metres a test can name
/// — because "vague and right beats specific and wrong" is a rule about
/// somebody's journal rather than about CoreLocation, and a rule that could
/// only be checked by standing in a café is one nobody checks.
///
/// ## Asking, and being answered
///
/// A location manager answers through a delegate, so every call here is a
/// continuation waiting on one. Two things make that safe rather than a source
/// of hangs: a permission whose status is already decided is answered from
/// what is known without asking CoreLocation anything, and a fix that never
/// arrives is given up on after ``longEnoughForAFix`` — a widget spinning for
/// ever is worse than a widget offering nothing, because the second is still
/// answerable by typing.
final class CoreLocationPlaces: NSObject, Places, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()

    /// Everything below is touched from the delegate's queue and from whoever
    /// is awaiting an answer, which are not the same one.
    private let lock = NSLock()

    /// Where the permission stands, kept rather than read.
    ///
    /// ``access`` is answered without waiting for anything — the seam says so,
    /// because the widget reads it while deciding what to draw — and the
    /// manager it would be read from is not free to touch from wherever that
    /// happens. The delegate is told every time it changes, including once as
    /// soon as it is set, so what is kept here is never behind.
    private var standing: PlaceAccess = .undecided

    private var whoIsAsking: [CheckedContinuation<PlaceAccess, Never>] = []
    private var whoIsWaitingForAFix: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        // Good enough for a place name, and cheap: the difference between ten
        // metres and one is nothing to a café's name, and everything to how
        // long the fix takes and what it costs the battery.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Read before the delegate is set, and never after: setting the
        // delegate is what starts the callbacks that write this under the
        // lock, and a seeding racing them could put a stale answer back.
        standing = Self.standing(of: manager.authorizationStatus)
        manager.delegate = self
    }

    var access: PlaceAccess {
        lock.withLock { standing }
    }

    func ask() async -> PlaceAccess {
        await withCheckedContinuation { continuation in
            // A permission already decided is decided, and asking again would
            // be an alert the system does not even show — the way back from a
            // refusal is Settings.
            let settled: PlaceAccess? = lock.withLock {
                guard standing == .undecided else { return standing }
                whoIsAsking.append(continuation)
                return nil
            }
            guard settled == nil else { return continuation.resume(returning: settled!) }

            // When in use, which is the whole of what Aujour needs: it asks
            // where the device is because somebody tapped a widget and is
            // looking at the answer. There is nothing it would do with a
            // location in the background.
            Task { @MainActor in manager.requestWhenInUseAuthorization() }
            // And given up on, like a fix is. An alert that is never presented
            // — Location Services off for the whole device, the app sent to
            // the background with the question still up — would otherwise
            // leave this waiting for a callback that is not coming, and a
            // sheet spinning on it for ever. Whatever the permission is by
            // then is the answer; undecided reads as nothing to offer, which
            // is a place typed instead.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.longEnoughToBeAsked))
                self?.settleTheAsking()
            }
        }
    }

    /// Hands the permission as it now stands to everybody still waiting to be
    /// told what the user said.
    private func settleTheAsking() {
        let (now, waiting) = lock.withLock {
            let waiting = whoIsAsking
            whoIsAsking = []
            return (standing, waiting)
        }
        waiting.forEach { $0.resume(returning: now) }
    }

    func around() async -> Surroundings {
        // Never asks, and answers nothing where it may not read — the seam's
        // first promise, and what keeps a system alert out from in front of
        // somebody who only opened a sheet.
        guard access == .allowed else { return Surroundings() }
        guard let here = await fix() else { return Surroundings() }

        // Both at once: they are two lookups over one fix, and a sheet is
        // waiting on the pair of them.
        async let pointsOfInterest = pointsOfInterest(around: here)
        async let address = address(of: here)
        return Surroundings(named: await pointsOfInterest, area: await address)
    }

    // MARK: - Where the device is

    /// One fix, or `nil` for a device that would not give one.
    ///
    /// `requestLocation` answers exactly once, through one delegate call or
    /// the other — but "answers" is CoreLocation's promise and not something
    /// this can hold it to, and the thing waiting on it is a sheet in front of
    /// somebody. So it is given ``longEnoughForAFix`` and then given up on.
    ///
    /// Giving up settles every fix being waited on, not only this one. There
    /// is at most one sheet asking at a time, and the cost of being wrong
    /// about that is an offer that does not appear — which is the same thing
    /// as being somewhere with no place to name, and answerable the same way.
    private func fix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            lock.withLock { whoIsWaitingForAFix.append(continuation) }
            Task { @MainActor in manager.requestLocation() }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.longEnoughForAFix))
                self?.settleTheFix(with: nil)
            }
        }
    }

    /// Hands one answer to everybody waiting for a fix, whoever got there
    /// first — a location, a failure, or the clock running out.
    private func settleTheFix(with location: CLLocation?) {
        let waiting = lock.withLock {
            let waiting = whoIsWaitingForAFix
            whoIsWaitingForAFix = []
            return waiting
        }
        waiting.forEach { $0.resume(returning: location) }
    }

    // MARK: - Turning it into words

    /// The places around a fix that have names somebody would use, nearest
    /// first — each with how far off it is, which is what decides whether the
    /// nearest of them is where the user *is*.
    private func pointsOfInterest(around here: CLLocation) async -> [NearbyPlace] {
        let asked = MKLocalPointsOfInterestRequest(
            center: here.coordinate, radius: Self.aShortWalk
        )
        guard let found = try? await MKLocalSearch(request: asked).start() else { return [] }

        return
            found.mapItems
            .compactMap { item -> NearbyPlace? in
                guard let place = Self.place(item) else { return nil }
                return NearbyPlace(place: place, metresAway: here.distance(from: item.location))
            }
            .sorted { $0.metresAway < $1.metresAway }
            .prefix(Self.asManyAsAreWorthOffering)
            .map { $0 }
    }

    /// The address a fix reverse-geocodes to, as one place — the
    /// neighbourhood where there is one, and the town otherwise.
    ///
    /// The answer that is always available and never wrong, which is what
    /// earns it a place in the list however many points of interest were
    /// found: somebody standing somewhere with no name still knows what to
    /// call it, and this is usually what they would call it.
    private func address(of here: CLLocation) async -> Place? {
        guard let asked = MKReverseGeocodingRequest(location: here),
            let found = try? await asked.mapItems.first
        else { return nil }

        // The town, before the street: "Paris" is what somebody writes about
        // their day, and 12 Rue de Buci is what a delivery driver writes.
        let addressed = found.addressRepresentations
        guard let name = addressed?.cityName ?? found.name else { return nil }
        let region = [addressed?.cityWithContext, addressed?.regionName]
            .compactMap { $0 }
            .first { $0 != name }

        return Place(id: "address:\(Self.identity(of: here.coordinate))", name: name, region: region)
    }

    private static func place(_ item: MKMapItem) -> Place? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return nil }

        // Enough of an address to tell this Starbucks from the one two streets
        // over, and no more: it is read in a picker row, not written into
        // anybody's entry.
        let region = [item.address?.shortAddress, item.addressRepresentations?.cityWithContext]
            .compactMap { $0 }
            .first { $0 != name }

        return Place(
            id: "poi:\(name)@\(identity(of: item.location.coordinate))",
            name: name,
            region: region
        )
    }

    /// A coordinate rounded to about a metre, as text — enough to tell two
    /// places apart in a list, and stable enough that the same place read
    /// twice is the same row.
    private static func identity(of coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - The delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let now = Self.standing(of: manager.authorizationStatus)
        let waiting: [CheckedContinuation<PlaceAccess, Never>] = lock.withLock {
            standing = now
            // Still undecided is the alert being on screen, which is not an
            // answer — including the call that arrives as soon as the delegate
            // is set, before anybody has asked anything.
            guard now != .undecided else { return [] }
            let waiting = whoIsAsking
            whoIsAsking = []
            return waiting
        }
        waiting.forEach { $0.resume(returning: now) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        settleTheFix(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Not said out loud anywhere. A device that cannot say where it is is
        // a widget with nothing to offer, which is a place typed instead.
        settleTheFix(with: nil)
    }

    /// Where a permission stands, as the widget means it.
    ///
    /// Reduced access — the coarse location somebody granted instead of the
    /// precise one — is allowed, deliberately: a few hundred metres is the
    /// difference between two cafés, and it is no difference at all to the
    /// name of the neighbourhood. Which is a smaller answer rather than a
    /// refused one. `.restricted`, a device managed so that nobody may allow
    /// it, is a refusal, because it is one that will never change by asking.
    private static func standing(of status: CLAuthorizationStatus) -> PlaceAccess {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .notDetermined: .undecided
        case .denied, .restricted: .refused
        @unknown default: .refused
        }
    }

    // MARK: - The numbers

    /// How far around the fix to look for somewhere with a name. A couple of
    /// minutes on foot: far enough to find the café on the corner, near enough
    /// that nothing in the list is somewhere the user was not.
    private static let aShortWalk: CLLocationDistance = 250

    /// How many places the picker shows. A list somebody reads at arm's length
    /// while a sentence waits, not a directory.
    private static let asManyAsAreWorthOffering = 8

    /// How long a fix is waited for before the widget offers nothing.
    private static let longEnoughForAFix: Double = 10

    /// How long the system's permission alert is waited on before the answer
    /// is taken to be whatever the permission already says.
    ///
    /// Long, because there is a human reading an alert at the other end of it
    /// — this is a backstop against an alert that never appeared at all, not a
    /// clock on somebody making up their mind.
    private static let longEnoughToBeAsked: Double = 60
}
