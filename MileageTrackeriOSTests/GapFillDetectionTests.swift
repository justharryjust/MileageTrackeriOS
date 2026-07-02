import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Gap-Fill Detection")
struct GapFillDetectionTests {

    @Test("Small gap below thresholds does not trigger gap-fill")
    func smallGapNotFilled() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.849, longitude: 174.764),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(5))
        // ~130m gap over 5s — both below spatial (300m) and speed thresholds
        let dist = b.distance(from: a)
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false,
                "Gap of \(Int(dist))m over 5s should not trigger gap-fill")
    }

    @Test("Tunnel dropout with realistic gap triggers gap-fill")
    func tunnelDropoutTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 20, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.835, longitude: 174.780),
                           altitude: 10, horizontalAccuracy: 50, verticalAccuracy: 5,
                           course: 0, speed: 25, timestamp: a.timestamp.addingTimeInterval(30))
        // ~1.8km gap over 30s = 60 m/s implied — should trigger on speed alone
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true)
    }

    @Test("Cold-start delay with moderate gap triggers on distance alone")
    func coldStartDelayTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: -1, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.840, longitude: 174.770),
                           altitude: 10, horizontalAccuracy: 50, verticalAccuracy: 5,
                           course: 0, speed: 15, timestamp: a.timestamp.addingTimeInterval(25))
        // ~900m gap over 25s = 36 m/s — below 54 km/h speed threshold but above 500m spatial
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true,
                "900m gap should trigger via spatial threshold alone")
    }

    @Test("Urban gap (350m over 30s) triggers via speed threshold")
    func urbanGapTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.845, longitude: 174.770),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(30))
        // ~650m gap over 30s = ~78 km/h implied — above 54 km/h threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true,
                "650m urban gap should trigger via speed threshold")
    }

    @Test("Gap below 300m does not trigger regardless of timing")
    func shortGapNeverTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.8485, longitude: 174.7635),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(60))
        // ~60m gap over 60s — below 300m spatial threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 17 — Leading-Walking Trim Updates startedAt
// MARK: ═══════════════════════════════════════════════════════

