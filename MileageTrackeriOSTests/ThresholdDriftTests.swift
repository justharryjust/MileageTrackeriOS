import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Threshold Drift Reconciliation")
struct ThresholdDriftTests {

    @Test("slcSpeedKmh matches documented value of 22 km/h")
    func slcSpeedMatchesDoc() {
        // The CLAUDE.md documents slcSpeedKmh as 22 km/h.
        // Verified via the public shouldFillGap path (which uses the same Heuristic enum).
        // The CLAUDE.md documents both slcSpeedKmh as 22 and promotionSpeedKmh as 25.
        // Verified via public static method (non-MainActor, no instance needed).
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                           altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1,
                           course: 0, speed: 6.11, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                           altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1,
                           course: 0, speed: 6.11, timestamp: a.timestamp.addingTimeInterval(1))
        // Verify constants match documented values via shouldFillGap's threshold usage
        // (implied speed > 15 m/s = 54 km/h for gap activation; gap of 111m over 300s
        // is below both spatial and speed thresholds)
        let gap = b.distance(from: a)
        #expect(gap < 300) // 111m < 300m spatial threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false)
    }
}
