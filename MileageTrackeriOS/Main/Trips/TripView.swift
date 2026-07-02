import SwiftUI
import MapKit
import RealmSwift

// MARK: - TripDetailView

/// Frozen snapshot of trip data — survives Realm object invalidation
/// when the underlying trip is merged or deleted.
fileprivate struct TripSnapshot {
    let id: String
    let startLat: Double; let startLng: Double
    let endLat: Double;   let endLng: Double
    let startedAt: Date;  let endedAt: Date?
    let distanceMetres: Double
    let startAddress: String; let endAddress: String
    let category: TripCategory
    let dollarValue: Double?
    let processingStatus: TripProcessingStatus

    init(from trip: Trip) {
        id = trip.id
        startLat = trip.startLat; startLng = trip.startLng
        endLat   = trip.endLat;   endLng   = trip.endLng
        startedAt = trip.startedAt; endedAt = trip.endedAt
        distanceMetres = trip.distanceMetres
        startAddress = trip.startAddress; endAddress = trip.endAddress
        category = trip.category
        dollarValue = trip.dollarValue
        processingStatus = .complete// trip.processingStatus
    }

    var startCoord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: startLat, longitude: startLng) }
    var endCoord:   CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: endLat,   longitude: endLng) }
    var isSamePoint: Bool { startLat == endLat && startLng == endLng }

    var distanceString: String {
        if distanceMetres < 1000 { return String(format: "%.0f m", distanceMetres) }
        return String(format: "%.1f km", distanceMetres / 1000)
    }
    var durationString: String? {
        guard let end = endedAt else { return nil }
        let s = Int(end.timeIntervalSince(startedAt))
        let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm", m)
    }
}

struct TripDetailView: View {
    let trip: Trip

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: TripSnapshot
    @State private var position: MapCameraPosition = .automatic
    @State private var route: MKRoute?
    @State private var isFetchingRoute = false
    @State private var showActualPath = true   // toggle between modes

    init(trip: Trip) {
        self.trip = trip
        _snapshot = State(initialValue: TripSnapshot(from: trip))
    }

    // Actual driven coordinates from saved locations
    private var actualCoordinates: [CLLocationCoordinate2D] {
        guard !trip.isInvalidated else { return [] }
        let locations = appState.tripRepo.tripPoints(for: trip)
        return locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Group {
            if trip.isInvalidated {
                Color.clear.onAppear { dismiss() }
            } else {
                mainContent
            }
        }
    }

    @State private var showPaywallForTrip = false

    private var isTripAccessible: Bool {
        !trip.isInvalidated && appState.subscriptionManager.isTripAccessible(trip)
    }

    private var mainContent: some View {
        Group {
            if isTripAccessible {
                tripMapContent
            } else {
                lockedTripView
            }
        }
    }

    private var lockedTripView: some View {
        VStack(spacing: MTSpacing.lg) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtTextSub)

            VStack(spacing: MTSpacing.sm) {
                Text("Trip Locked")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.mtTextPrimary)
                Text("This trip was recorded outside your active subscription period. Subscribe to view and manage this trip.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mtTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MTSpacing.lg)
            }

            Button("Subscribe to Unlock") {
                showPaywallForTrip = true
            }
            .buttonStyle(MTPrimaryButtonStyle())
            .padding(.horizontal, MTSpacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mtBackground)
        .sheet(isPresented: $showPaywallForTrip) {
            PaywallView()
                .environment(appState)
        }
    }

    private var tripMapContent: some View {
        Map(position: $position) {
            if showActualPath {
                if actualCoordinates.count > 1 {
                    MapPolyline(coordinates: actualCoordinates)
                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            } else {
                if let route {
                    MapPolyline(route.polyline)
                        .stroke(Color.mtGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }

            Annotation("Start", coordinate: snapshot.startCoord, anchor: .bottom) {
                TripPinView(color: .mtGreen, systemImage: "location.fill")
            }

            if !snapshot.isSamePoint {
                Annotation("End", coordinate: snapshot.endCoord, anchor: .bottom) {
                    TripPinView(color: .red, systemImage: "flag.checkered")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .safeAreaInset(edge: .bottom) {
            TripInfoCard(snapshot: snapshot)
                .padding(.horizontal, MTSpacing.md)
                .padding(.bottom, MTSpacing.sm)
        }
        .navigationTitle("Trip Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if appState.subscriptionManager.isTripAccessible(trip) {
                        Button {
                            guard !trip.isInvalidated else { return }
                            appState.tripRepo.categorise(trip, as: .business)
                        } label: {
                            Label("Mark as Business", systemImage: "briefcase.fill")
                        }
                        Button {
                            guard !trip.isInvalidated else { return }
                            appState.tripRepo.categorise(trip, as: .personal)
                        } label: {
                            Label("Mark as Personal", systemImage: "person.fill")
                        }

                        Divider()
                    }

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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { position = .automatic }
        .task { await fetchRouteIfNeeded() }
    }

    // MARK: - Route Fetching

    private func fetchRouteIfNeeded() async {
        guard !snapshot.isSamePoint else {
            position = .region(MKCoordinateRegion(
                center: snapshot.startCoord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
            return
        }

        guard route == nil else { return }   // already fetched, no need to re-fetch on toggle back

        let midLat = (snapshot.startCoord.latitude + snapshot.endCoord.latitude) / 2
        let midLng = (snapshot.startCoord.longitude + snapshot.endCoord.longitude) / 2
        let latDelta = abs(snapshot.startCoord.latitude - snapshot.endCoord.latitude) * 1.5 + 0.01
        let lngDelta = abs(snapshot.startCoord.longitude - snapshot.endCoord.longitude) * 1.5 + 0.01
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        ))

        isFetchingRoute = true
        defer { isFetchingRoute = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: snapshot.startCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: snapshot.endCoord))
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
    @Environment(AppState.self) private var appState
    let snapshot: TripSnapshot

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
                    Text(snapshot.startAddress.isEmpty ? "Unknown start" : snapshot.startAddress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTextPrimary)
                        .lineLimit(2)

                    Text(snapshot.endAddress.isEmpty ? "Unknown end" : snapshot.endAddress)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTextPrimary)
                        .lineLimit(2)
                }

                Spacer()

                // Value + category badge
                VStack(alignment: .trailing, spacing: 4) {
                    if let val = snapshot.dollarValue {
                        let fmt = MileageCalculator.currencyFormatter(for: appState.profileRepo.profile.jurisdiction.currencyCode)
                        Text(fmt.string(from: NSNumber(value: val)) ?? "")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.mtGreen)
                    }
                    HStack(spacing: 4) {
                        if snapshot.processingStatus == .pending {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        categoryBadge
                    }
                }
            }
            .padding(MTSpacing.md)

            Divider().padding(.horizontal, MTSpacing.md)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    StatCell(label: "Distance", value: snapshot.distanceString)
                    Divider().frame(height: 32)
                    StatCell(label: "Duration", value: snapshot.durationString ?? "—")
                }
            }
            .padding(.vertical, MTSpacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: MTRadius.lg)
                .fill(Color.mtSurface)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        )
    }

    private var categoryBadge: some View {
        Text(snapshot.category == .uncategorised ? "Review" : snapshot.category.rawValue.capitalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var categoryColor: Color {
        switch snapshot.category {
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
                .lineLimit(2)
                .multilineTextAlignment(.center)
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
