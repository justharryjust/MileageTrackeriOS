////
////  MapsManager.swift
////  MileageTrackeriOS
////
////  Created by Harry Just on 23/04/2026.
////
//import MapKit
//
//// TODO: For long trips the zoom makes it pointless to create an actual trip... Just draw between the points
//
//class MapsManager {
//    
//    // TODO: put in the right place...
//    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async throws -> String {
////        Caveats
////        Rate limited — Apple throttles CLGeocoder heavily. Don't call it in a loop for many coordinates — you'll get errors back. For bulk reverse geocoding, space calls out or cache aggressively.
////        One instance at a time — CLGeocoder should not have multiple requests in flight simultaneously. Queue them if needed.
////        Network required — hits Apple's servers, no offline support.
//        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
//        let geocoder = MKReverseGeocodingRequest(location: <#T##CLLocation#>)
//        
//        let placemarks = try await geocoder?.mapItems
//        
//        guard let placemark = placemarks?.first else { return "Unknown location" }
//        
//        // Build a readable string from whatever's available
//        let components: [String?] = [
//            placemark.name           // e.g. "Sky Tower"
////            placemark.address.,   // street name
////            placemark.locality,       // city
////            placemark.administrativeArea, // state/region
////            placemark.country
//        ]
//        
//        return components.compactMap { $0 }.joined(separator: ", ")
//    }
//    
//    func humanReadableLocation(coordinate: CLLocationCoordinate2D) async -> String {
//        guard let result = try? await reverseGeocode(coordinate) else {
//            return "\(coordinate.latitude), \(coordinate.longitude)"
//        }
//        return result
//    }
//    
//    func fetchRoadSnappedRoute(from stops: [TripStop]) async throws -> [CLLocationCoordinate2D] {
//        var allCoordinates: [CLLocationCoordinate2D] = []
//        
//        // Request route between each consecutive pair of stops
//        for i in 0..<stops.count - 1 {
//            let request = MKDirections.Request()
//            request.source = MKMapItem(placemark: MKPlacemark(coordinate: stops[i].coordinate))
//            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stops[i + 1].coordinate))
//            request.transportType = .automobile  // snaps to driveable roads
//            
//            let directions = MKDirections(request: request)
//            let response = try await directions.calculate()
//            
//            // Take the first (best) route
//            if let route = response.routes.first {
//                allCoordinates += route.polyline.coordinates  // road-snapped points
//            }
//        }
//        
//        return allCoordinates
//    }
//    
//    extension MKPolyline {
//        var coordinates: [CLLocationCoordinate2D] {
//            var coords = [CLLocationCoordinate2D](
//                repeating: kCLLocationCoordinate2DInvalid,
//                count: pointCount
//            )
//            getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
//            return coords
//        }
//    }
//    
//    struct TripMapView: View {
//        let stops: [TripStop]
//        @State private var routeCoordinates: [CLLocationCoordinate2D] = []
//
//        var body: some View {
//            Map(initialPosition: .automatic) {
//                ForEach(stops) { stop in
//                    Marker(stop.name, coordinate: stop.coordinate)
//                }
//
//                if !routeCoordinates.isEmpty {
//                    MapPolyline(coordinates: routeCoordinates)
//                        .stroke(.blue, lineWidth: 3)  // road-snapped route
//                }
//            }
//            .task {
//                routeCoordinates = (try? await fetchRoadSnappedRoute(from: stops)) ?? []
//            }
//        }
//    }
//    
//    func simplify(_ coords: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
//        guard coords.count > 2 else { return coords }
//        
//        var maxDistance = 0.0
//        var maxIndex = 0
//        let end = coords.count - 1
//        
//        for i in 1..<end {
//            let d = perpendicularDistance(coords[i], from: coords[0], to: coords[end])
//            if d > maxDistance { maxDistance = d; maxIndex = i }
//        }
//        
//        if maxDistance > tolerance {
//            let left = simplify(Array(coords[0...maxIndex]), tolerance: tolerance)
//            let right = simplify(Array(coords[maxIndex...end]), tolerance: tolerance)
//            return left.dropLast() + right
//        }
//        return [coords[0], coords[end]]
//    }
//
//    func perpendicularDistance(
//        _ point: CLLocationCoordinate2D,
//        from start: CLLocationCoordinate2D,
//        to end: CLLocationCoordinate2D
//    ) -> Double {
//        // Convert to simple 2D — good enough for small distances
//        let dx = end.longitude - start.longitude
//        let dy = end.latitude - start.latitude
//        let mag = sqrt(dx*dx + dy*dy)
//        guard mag > 0 else { return 0 }
//        return abs((point.latitude - start.latitude) * dx - (point.longitude - start.longitude) * dy) / mag
//    }
//    
//    func fetchRouteChunked(coordinates: [CLLocationCoordinate2D]) async throws -> [CLLocationCoordinate2D] {
//        let chunkSize = 10
//        let chunks = stride(from: 0, to: coordinates.count, by: chunkSize - 1).map {
//            Array(coordinates[$0..<min($0 + chunkSize, coordinates.count)])
//        }
//        
//        var result: [CLLocationCoordinate2D] = []
//        
//        for chunk in chunks {
//            let request = MKDirections.Request()
//            request.source = MKMapItem(placemark: MKPlacemark(coordinate: chunk.first!))
//            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: chunk.last!))
//            request.transportType = .automobile
//            
//            // Add intermediate waypoints if supported
//            if chunk.count > 2 {
//                request.waypoints = chunk.dropFirst().dropLast().map {
//                    MKMapItem(placemark: MKPlacemark(coordinate: $0))
//                }
//            }
//            
//            // Respect rate limit
//            try await Task.sleep(for: .milliseconds(1500))
//            
//            let directions = MKDirections(request: request)
//            if let route = try? await directions.calculate() {
//                result += route.routes.first?.polyline.coordinates ?? []
//            }
//        }
//        
//        return result
//    }
//
//
//}
