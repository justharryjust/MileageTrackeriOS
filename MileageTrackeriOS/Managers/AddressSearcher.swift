// AddressSearcher — wraps MKLocalSearchCompleter and MKLocalSearch.
//
// Usage:
//   let searcher = AddressSearcher()
//   searcher.query = "Britomart"   // completions update automatically
//   let result = await searcher.resolve(completion)  // → AddressResult

import Foundation
import MapKit

// MARK: - AddressResult

struct AddressResult: Identifiable, Equatable {
    let id         = UUID()
    let title      : String   // primary line  e.g. "Britomart Transport Centre"
    let subtitle   : String   // secondary line e.g. "Auckland, New Zealand"
    let coordinate : CLLocationCoordinate2D

    var fullAddress: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }

    // Equatable — ignore id
    static func == (lhs: AddressResult, rhs: AddressResult) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

// MARK: - AddressSearcher

@Observable
final class AddressSearcher: NSObject, MKLocalSearchCompleterDelegate {

    var query: String = "" {
        didSet {
            if query.isEmpty {
                completions = []
            } else {
                completer.queryFragment = query
            }
        }
    }

    private(set) var completions: [MKLocalSearchCompletion] = []
    private(set) var isSearching: Bool = false
    private(set) var error: String?

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        // .address gives street-level results; .pointOfInterest adds named places
        completer.resultTypes = [.address, .pointOfInterest]
    }

    // MARK: - Resolve completion → coordinate

    /// Converts an MKLocalSearchCompletion (just text) into a full AddressResult with coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> AddressResult {
        let request = MKLocalSearch.Request(completion: completion)
        let search  = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let item = response.mapItems.first else {
            throw AddressSearchError.noResults
        }
        let coord = item.placemark.coordinate
        return AddressResult(
            title      : completion.title,
            subtitle   : completion.subtitle,
            coordinate : coord
        )
    }

    // MARK: - Driving distance between two results

    /// Returns the driving route distance in metres between two resolved addresses.
    /// Falls back to straight-line haversine if routing fails (offline, no route).
    func drivingDistance(from start: AddressResult, to end: AddressResult) async -> Double {
        let origin      = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))

        let req = MKDirections.Request()
        req.source             = origin
        req.destination        = destination
        req.transportType      = .automobile
        req.requestsAlternateRoutes = false

        do {
            let directions = MKDirections(request: req)
            let response   = try await directions.calculate()
            return response.routes.first?.distance ?? haversine(start.coordinate, end.coordinate)
        } catch {
            // Offline or no automobile route — fall back to straight-line
            return haversine(start.coordinate, end.coordinate)
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
        self.error  = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        self.error  = error.localizedDescription
    }

    // MARK: - Private: Haversine fallback

    private func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R   = 6_371_000.0  // Earth radius in metres
        let φ1  = a.latitude  * .pi / 180
        let φ2  = b.latitude  * .pi / 180
        let Δφ  = (b.latitude  - a.latitude)  * .pi / 180
        let Δλ  = (b.longitude - a.longitude) * .pi / 180
        let s   = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        return R * 2 * atan2(sqrt(s), sqrt(1 - s))
    }
}

// MARK: - Error

enum AddressSearchError: LocalizedError {
    case noResults
    var errorDescription: String? { "No location found for that address." }
}
