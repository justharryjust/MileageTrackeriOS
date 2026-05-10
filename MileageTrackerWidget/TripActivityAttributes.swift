import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    var vehicleName: String

    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var distanceMetres: Double
        var elapsedSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }

        var distanceKm: Double { distanceMetres / 1000 }

        var distanceDisplay: String {
            if distanceMetres < 1000 {
                return String(format: "%.0f m", distanceMetres)
            }
            return String(format: "%.1f km", distanceKm)
        }

        var durationDisplay: String {
            let h = elapsedSeconds / 3600
            let m = (elapsedSeconds % 3600) / 60
            let s = elapsedSeconds % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%02d:%02d", m, s)
        }
    }
}
