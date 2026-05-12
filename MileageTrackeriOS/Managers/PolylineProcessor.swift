// PolylineProcessor — Geometric post-processing of GPS polylines.
//
// §3.3: Douglas–Peucker simplification — removes points that fall within
// `epsilon` metres of a straight line between their neighbours. Reduces GPS
// jitter inflation of distance (typically 2–5% on real-world trips) without
// losing any meaningful shape information. Conservative-but-truthful figures
// matter for tax purposes — overestimating mileage is an audit red flag.
//
// §3.1: full-polyline map matching — breaks a long trip into ~5km chunks and
// snaps each chunk to MKDirections automobile routes. Returns the road-snapped
// polyline with interpolated timestamps. Rate-limited through MKDirectionsRateLimiter.
// Falls back to the simplified polyline (and a `.pending` processing status) when
// quota is exhausted.

import Foundation
import CoreLocation
import MapKit

enum PolylineProcessor {

    // MARK: - §3.3 Douglas–Peucker simplification

    /// Simplifies a polyline by removing points within `epsilonMetres` of the
    /// straight line between their context neighbours. Returns a polyline with
    /// the same first/last points and a subset of the originals.
    /// Typical epsilon for GPS jitter: 3-5m.
    static func simplify(_ locations: [CLLocation], epsilonMetres: Double = 4) -> [CLLocation] {
        guard locations.count > 2 else { return locations }
        var keepFlags = [Bool](repeating: false, count: locations.count)
        keepFlags[0] = true
        keepFlags[locations.count - 1] = true
        simplifyRecursive(locations, startIdx: 0, endIdx: locations.count - 1,
                          epsilon: epsilonMetres, flags: &keepFlags)
        return zip(locations, keepFlags).compactMap { $0.1 ? $0.0 : nil }
    }

    private static func simplifyRecursive(_ locations: [CLLocation], startIdx: Int, endIdx: Int,
                                          epsilon: Double, flags: inout [Bool]) {
        guard endIdx > startIdx + 1 else { return }
        // Find the point with the maximum perpendicular distance from the start–end segment
        var maxDist: Double = 0
        var maxIdx = startIdx
        let start = locations[startIdx]
        let end = locations[endIdx]
        for i in (startIdx + 1)..<endIdx {
            let d = perpendicularDistanceMetres(point: locations[i], lineStart: start, lineEnd: end)
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }
        if maxDist > epsilon {
            flags[maxIdx] = true
            simplifyRecursive(locations, startIdx: startIdx, endIdx: maxIdx, epsilon: epsilon, flags: &flags)
            simplifyRecursive(locations, startIdx: maxIdx, endIdx: endIdx, epsilon: epsilon, flags: &flags)
        }
    }

    /// Approximate perpendicular distance from `point` to the great-circle segment
    /// `[lineStart, lineEnd]`, in metres. Uses equirectangular projection — fine for
    /// segments under a few km.
    private static func perpendicularDistanceMetres(point: CLLocation,
                                                    lineStart: CLLocation,
                                                    lineEnd: CLLocation) -> Double {
        let earthR = 6_371_000.0
        let latRad = (lineStart.coordinate.latitude + lineEnd.coordinate.latitude) / 2 * .pi / 180
        let mPerLat = earthR * .pi / 180
        let mPerLng = mPerLat * cos(latRad)
        let ax = lineStart.coordinate.longitude * mPerLng
        let ay = lineStart.coordinate.latitude * mPerLat
        let bx = lineEnd.coordinate.longitude * mPerLng
        let by = lineEnd.coordinate.latitude * mPerLat
        let px = point.coordinate.longitude * mPerLng
        let py = point.coordinate.latitude * mPerLat
        let dx = bx - ax
        let dy = by - ay
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return point.distance(from: lineStart) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        let qx = ax + t * dx
        let qy = ay + t * dy
        return sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy))
    }

    // MARK: - Distance

    /// Sum of consecutive Haversine distances along the polyline.
    static func totalDistanceMetres(_ locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total
    }

    // MARK: - §3.1 Full-polyline map matching

    /// Splits the input into ~maxChunkLengthMetres segments and snaps each to a
    /// driving route via MKDirections, returning the concatenated road-snapped
    /// polyline with interpolated timestamps. Rate-limited; on quota exhaustion
    /// returns whatever portion was snapped (and the original tail).
    ///
    /// Defaults: 5km chunks, capped at 12 chunks per trip (60km of snapping).
    /// Beyond that the marginal accuracy gain doesn't justify the latency/quota.
    static func mapMatch(_ locations: [CLLocation],
                         maxChunkLengthMetres: Double = 5_000,
                         maxChunks: Int = 12) async -> [CLLocation] {
        guard locations.count >= 2 else { return locations }

        // Identify chunk boundary indices by cumulative distance
        var boundaries = [0]
        var runningDist = 0.0
        for i in 1..<locations.count {
            runningDist += locations[i].distance(from: locations[i - 1])
            if runningDist >= maxChunkLengthMetres {
                boundaries.append(i)
                runningDist = 0
            }
        }
        if boundaries.last != locations.count - 1 {
            boundaries.append(locations.count - 1)
        }
        guard boundaries.count >= 2 else { return locations }

        // Cap the number of MKDirections calls
        let chunkCount = min(boundaries.count - 1, maxChunks)

        struct ChunkResult { let index: Int; let snapped: [CLLocation]? }
        var results: [Int: [CLLocation]] = [:]
        await withTaskGroup(of: ChunkResult.self) { group in
            for ci in 0..<chunkCount {
                let startIdx = boundaries[ci]
                let endIdx   = boundaries[ci + 1]
                let start    = locations[startIdx]
                let end      = locations[endIdx]
                group.addTask { [start, end] in
                    guard await MKDirectionsRateLimiter.shared.tryAcquire() else {
                        return ChunkResult(index: ci, snapped: nil)
                    }
                    let snap = await Self.requestSnappedRoute(from: start, to: end)
                    return ChunkResult(index: ci, snapped: snap)
                }
            }
            for await r in group {
                if let s = r.snapped { results[r.index] = s }
            }
        }

        // Stitch chunks back together — fall back to raw locations for chunks that failed
        var out: [CLLocation] = []
        for ci in 0..<chunkCount {
            if let snapped = results[ci] {
                if ci == 0 || out.isEmpty {
                    out.append(contentsOf: snapped)
                } else {
                    // Skip the first snapped point to avoid duplicate at boundary
                    out.append(contentsOf: snapped.dropFirst())
                }
            } else {
                let startIdx = boundaries[ci]
                let endIdx   = boundaries[ci + 1]
                let fallback = Array(locations[startIdx...endIdx])
                if out.isEmpty {
                    out.append(contentsOf: fallback)
                } else {
                    out.append(contentsOf: fallback.dropFirst())
                }
            }
        }
        // Append any unsnapped tail (when boundaries.count - 1 > maxChunks)
        if chunkCount < boundaries.count - 1 {
            let tailStart = boundaries[chunkCount]
            out.append(contentsOf: locations[tailStart...].dropFirst())
        }
        return out
    }

    private static func requestSnappedRoute(from start: CLLocation, to end: CLLocation) async -> [CLLocation]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .automobile
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }

        let coords = route.polyline.coordinates
        guard coords.count >= 2 else { return nil }

        // Cumulative distances
        var dists: [Double] = [0]
        for j in 1..<coords.count {
            let d = CLLocation(latitude: coords[j].latitude, longitude: coords[j].longitude)
                .distance(from: CLLocation(latitude: coords[j-1].latitude, longitude: coords[j-1].longitude))
            dists.append(dists[j - 1] + d)
        }
        let totalDist = dists.last!

        // 1 Hz sampling, capped
        let timeGap = end.timestamp.timeIntervalSince(start.timestamp)
        let sampleCount = max(2, min(Int(timeGap), 600))
        let step = totalDist / Double(sampleCount - 1)

        var snapped: [CLLocation] = []
        var nextTarget = 0.0
        var segIdx = 0
        snapped.append(start)
        for _ in 1..<sampleCount {
            nextTarget += step
            while segIdx < dists.count - 1 && dists[segIdx + 1] < nextTarget {
                segIdx += 1
            }
            let segDist = dists[segIdx + 1] - dists[segIdx]
            let t = segDist > 0 ? (nextTarget - dists[segIdx]) / segDist : 0
            let lat = coords[segIdx].latitude + (coords[segIdx + 1].latitude - coords[segIdx].latitude) * t
            let lng = coords[segIdx].longitude + (coords[segIdx + 1].longitude - coords[segIdx].longitude) * t
            let fraction = Double(snapped.count) / Double(sampleCount - 1)
            let ts = start.timestamp.addingTimeInterval(timeGap * fraction)
            snapped.append(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: -1,
                horizontalAccuracy: 5,
                verticalAccuracy: -1,
                course: -1,
                speed: -1,
                timestamp: ts
            ))
        }
        return snapped
    }
}
