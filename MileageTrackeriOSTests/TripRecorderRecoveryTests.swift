import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("TripRecorder Recovery Handlers")
struct TripRecorderRecoveryTests {

    @MainActor
    @Test("handleRecoveryResume sets up active trip state")
    func resumeSetsUpActiveState() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()

        h.recorder.handleRecoveryResume(tripId: tripId)

        #expect(h.recorder.state.isActive)
    }

    @MainActor
    @Test("handleRecoveryResume is no-op for unknown trip ID")
    func resumeUnknownTripIsNoOp() throws {
        let h = try Harness()

        h.recorder.handleRecoveryResume(tripId: "non-existent")

        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoverySaveAsIs saves the inflight trip")
    func saveAsIsFinalisesTrip() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()
        #expect(h.tripRepo.trip(id: tripId) != nil)

        h.recorder.handleRecoverySaveAsIs(tripId: tripId)

        // After save-as-is, the trip should still exist but no longer be inflight
        let trip = h.tripRepo.trip(id: tripId)
        #expect(trip != nil)
        #expect(trip?.source != .inflight)

        // State should reset to idle after saving
        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoveryDiscard deletes the inflight trip")
    func discardRemovesTrip() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()
        #expect(h.tripRepo.trip(id: tripId) != nil)

        h.recorder.handleRecoveryDiscard(tripId: tripId)

        // Trip should be deleted
        #expect(h.tripRepo.trip(id: tripId) == nil)
        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoveryDiscard is no-op for unknown trip ID")
    func discardUnknownTripIsNoOp() throws {
        let h = try Harness()

        // Should not crash
        h.recorder.handleRecoveryDiscard(tripId: "non-existent")
        #expect(h.recorder.state.isIdle)
    }
}

// MARK: - Harness Helpers

extension Harness {
    /// Set up an inflight trip in Realm and return its ID.
    @MainActor
    func setupInflightTrip() throws -> String {
        let trip = Trip()
        trip.startedAt = Date().addingTimeInterval(-3600)
        trip.distanceMetres = 10_000
        trip.source = .inflight
        try realm.write {
            realm.add(trip)
        }
        return trip.id
    }
}
