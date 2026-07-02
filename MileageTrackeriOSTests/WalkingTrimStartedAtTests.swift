import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Walking Trim Updates startedAt")
@MainActor
struct WalkingTrimStartedAtTests {

    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    @Test("Leading-walking trim updates tripStartedAt before save")
    func trimUpdatesStartedAt() throws {
        let h = try Harness()
        h.enterActive()

        // Fire a walking-speed location first to simulate pre-drive walking
        h.fireLocation(speedMs: 1.0, lat: -36.850, lng: 174.760, timestamp: Date().addingTimeInterval(-120))
        h.fireLocation(speedMs: 1.2, lat: -36.850, lng: 174.761, timestamp: Date().addingTimeInterval(-60))
        // Then a driving-speed location
        let driveTime = Date()
        h.fireLocation(speedMs: 15.0, lat: -36.848, lng: 174.763, timestamp: driveTime)
        h.fireLocation(speedMs: 15.0, lat: -36.840, lng: 174.770, timestamp: driveTime.addingTimeInterval(30))

        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)

        // The saved trip's startedAt should reflect the trimmed first point,
        // not the walking preamble
        let trips = savedTrips(in: h.tripRepo)
        #expect(!trips.isEmpty)
        let trip = trips.first!
        // startedAt should be close to driveTime, not 120s before it
        let drift = abs(trip.startedAt.timeIntervalSince(driveTime))
        #expect(drift < 30, "startedAt should be near the first driving point, not the walking preamble. Drift: \(drift)s")
    }

    @Test("No walking preamble leaves startedAt unchanged")
    func noTrimLeavesStartedAt() throws {
        let h = try Harness()
        h.enterActive()

        let startTime = Date()
        h.fireLocation(speedMs: 15.0, lat: -36.848, lng: 174.763, timestamp: startTime)
        h.fireLocation(speedMs: 15.0, lat: -36.840, lng: 174.770, timestamp: startTime.addingTimeInterval(30))

        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)

        let trips = savedTrips(in: h.tripRepo)
        #expect(!trips.isEmpty)
        let trip = trips.first!
        #expect(abs(trip.startedAt.timeIntervalSince(startTime)) < 5)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 18 — Auto-Merge Integration (commitTrip path)
// MARK: ═══════════════════════════════════════════════════════

