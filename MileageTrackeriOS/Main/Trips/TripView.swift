import SwiftUI
import MapKit

// MARK: - TripDetailView

struct TripDetailView: View {
    let trip: Trip

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .automatic
    @State private var route: MKRoute?
    @State private var isFetchingRoute = false
    @State private var showActualPath = true   // toggle between modes

    // Start / end coordinates
    private var startCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: trip.startLat, longitude: trip.startLng)
    }
    private var endCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: trip.endLat, longitude: trip.endLng)
    }
    private var isSamePoint: Bool {
        trip.startLat == trip.endLat && trip.startLng == trip.endLng
    }

    // Actual driven coordinates from saved locations
    private var actualCoordinates: [CLLocationCoordinate2D] {
        let locations = appState.tripRepo.tripPoints(for: trip)
        return locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // MARK: Map
                Map(position: $position) {
                    if showActualPath {
                        // Actual driven path
                        if actualCoordinates.count > 1 {
                            MapPolyline(coordinates: actualCoordinates)
                                .stroke(Color.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                    } else {
                        // Planned route polyline
                        if let route {
                            MapPolyline(route.polyline)
                                .stroke(Color.mtGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                    }

                    // Start annotation
                    Annotation("Start", coordinate: startCoord, anchor: .bottom) {
                        TripPinView(color: .mtGreen, systemImage: "location.fill")
                    }

                    // End annotation (only when different from start)
                    if !isSamePoint {
                        Annotation("End", coordinate: endCoord, anchor: .bottom) {
                            TripPinView(color: .red, systemImage: "flag.checkered")
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea(edges: .top)

                // MARK: Info Card
                TripInfoCard(trip: trip)
                    .padding(MTSpacing.md)
                    .padding(.bottom, MTSpacing.lg)
            }
            .navigationTitle("Trip Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            appState.tripRepo.categorise(trip, as: .business)
                        } label: {
                            Label("Mark as Business", systemImage: "briefcase.fill")
                        }
                        Button {
                            appState.tripRepo.categorise(trip, as: .personal)
                        } label: {
                            Label("Mark as Personal", systemImage: "person.fill")
                        }

                        Divider()

                        Button {
                            showActualPath.toggle()
                            if !showActualPath {
                                Task { await fetchRouteIfNeeded() }
                            }
                        } label: {
                            Label(
                                showActualPath ? "Show Road Route" : "Show Actual Path",
                                systemImage: showActualPath ? "road.lanes" : "point.topleft.down.to.point.bottomright.curvepath.fill"
                            )
                        }

                        Button {
                            // TODO:
//                            appState.tripRepo.fixStartEnd
                        } label: {
                            Label("Fix start/end", systemImage: "person.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .fontWeight(.semibold)
                    }
                }
            }
            .task { await fetchRouteIfNeeded() }
        }
    }

    // MARK: - Route Fetching

    private func fetchRouteIfNeeded() async {
        guard !isSamePoint else {
            position = .region(MKCoordinateRegion(
                center: startCoord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
            return
        }

        guard route == nil else { return }   // already fetched, no need to re-fetch on toggle back

        let midLat = (startCoord.latitude + endCoord.latitude) / 2
        let midLng = (startCoord.longitude + endCoord.longitude) / 2
        let latDelta = abs(startCoord.latitude - endCoord.latitude) * 1.5 + 0.01
        let lngDelta = abs(startCoord.longitude - endCoord.longitude) * 1.5 + 0.01
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        ))

        isFetchingRoute = true
        defer { isFetchingRoute = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: endCoord))
        request.transportType = .automobile

        if let result = try? await MKDirections(request: request).calculate() {
            route = result.routes.first
            if route != nil {
                position = .automatic
            }
        }
    }
}

// MARK: - Trip Info Card

private struct TripInfoCard: View {
    let trip: Trip

    var body: some View {
        VStack(spacing: 0) {
            // Route header
            HStack(alignment: .top, spacing: MTSpacing.sm) {
                VStack(spacing: 4) {
                    Circle().fill(Color.mtGreen).frame(width: 10, height: 10)
                    Rectangle().fill(Color.mtBorder).frame(width: 1.5, height: 28)
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.startAddress.isEmpty ? "Unknown start" : trip.startAddress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTextPrimary)
                        .lineLimit(2)

                    Text(trip.endAddress.isEmpty ? "Unknown end" : trip.endAddress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTextPrimary)
                        .lineLimit(2)
                }

                Spacer()

                if let val = trip.dollarValue {
                    Text("$\(String(format: "%.2f", val))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.mtGreen)
                }
            }
            .padding(MTSpacing.md)

            Divider().padding(.horizontal, MTSpacing.md)

            // Stats row
            HStack(spacing: 0) {
                StatCell(label: "Distance", value: trip.distanceString)
                if let dur = trip.durationString {
                    Divider().frame(height: 32)
                    StatCell(label: "Duration", value: dur)
                }
                Divider().frame(height: 32)
                StatCell(label: "Date", value: trip.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                Divider().frame(height: 32)
                StatCell(label: "Category", value: trip.category.rawValue.capitalized, valueColor: categoryColor)
            }
            .padding(.vertical, MTSpacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: MTRadius.lg)
                .fill(Color.mtSurface)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        )
    }

    private var categoryColor: Color {
        switch trip.category {
        case .business:      return .mtGreen
        case .personal:      return .blue
        case .uncategorised: return .mtWarning
        }
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    var valueColor: Color = .mtTextPrimary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.mtTextSub)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trip Pin

private struct TripPinView: View {
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Teardrop tail
            Triangle()
                .fill(color)
                .frame(width: 10, height: 8)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Preview

#Preview {
    let t = Trip()
    t.startAddress = "1 Lambton Quay, Wellington"
    t.endAddress   = "Wellington Airport"
    t.startLat     = -41.2784; t.startLng = 174.7767
    t.endLat       = -41.3272; t.endLng   = 174.8052
    t.startedAt    = Date()
    t.endedAt      = Date().addingTimeInterval(1320)
    t.distanceMetres = 8_400
    t.category     = .business
    t.dollarValue  = 4.07
    return TripDetailView(trip: t)
}
