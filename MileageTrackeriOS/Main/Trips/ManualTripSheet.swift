// ManualTripSheet — bottom-sheet for logging a trip manually.
// User picks start, optional stops, and end addresses. MKDirections calculates
// the chained driving distance. Saves TripPoints for each waypoint so the map
// renders a polyline through all stops.

import SwiftUI
import MapKit

struct ManualTripSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // MARK: Form state
    @State private var startResult: AddressResult?
    @State private var stops:      [AddressResult] = []
    @State private var endResult:  AddressResult?
    @State private var tripDate:   Date = Date()
    @State private var startTime:  Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime:    Date = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var notes:      String = ""

    // MARK: Resolution state
    @State private var searcher         = AddressSearcher()
    @State private var resolvedDistanceM: Double?
    @State private var isCalculating    = false
    @State private var routeError: String?

    // MARK: Search sheet
    @State private var searchTarget: SearchTarget?
    enum SearchTarget: Identifiable {
        case start, stop(Int), end
        var id: Int {
            switch self {
            case .start: return -2
            case .end:   return -1
            case .stop(let i): return i
            }
        }
    }

    // MARK: Save state
    @State private var isSaving  = false
    @State private var saveError: String?

    private var allResolved: Bool {
        startResult != nil && endResult != nil && !stops.contains(where: { $0.title.isEmpty })
    }

    private var canSave: Bool {
        allResolved && resolvedDistanceM != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MTSpacing.lg) {
                    routeSection
                    detailsSection
                    if let err = routeError {
                        Text(err).font(.caption).foregroundStyle(Color.mtRecording)
                            .padding(.horizontal, MTSpacing.md)
                    }
                    if let err = saveError {
                        Text(err).font(.caption).foregroundStyle(Color.mtRecording)
                            .padding(.horizontal, MTSpacing.md)
                    }
                    saveButton
                }
                .padding(.vertical, MTSpacing.lg)
            }
            .background(Color.mtBackground)
            .navigationTitle("Log Trip Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $searchTarget) { target in
                AddressSearchScreen(placeholder: target.placeholder) { completion in
                    Task { await resolve(completion, for: target) }
                }
            }
        }
    }

    // MARK: - Route Section

    private var routeSection: some View {
        VStack(spacing: 0) {
            // Start
            AddressField(
                icon: "circle.fill", iconColor: .mtGreen,
                label: "Start", value: startResult?.title,
                subtitle: startResult?.subtitle, placeholder: "Pick a start location"
            ) { searchTarget = .start }

            // Connector + stops
            ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                StopConnector()
                StopRow(
                    index: idx, stop: stop,
                    onTap: { searchTarget = .stop(idx) },
                    onRemove: {
                        stops.remove(at: idx)
                        Task { await recalculateDistance() }
                    }
                )
            }

            // Connector to end
            StopConnector()

            // End
            AddressField(
                icon: "mappin.circle.fill", iconColor: .mtRecording,
                label: "End", value: endResult?.title,
                subtitle: endResult?.subtitle, placeholder: "Pick an end location"
            ) { searchTarget = .end }

            // Add stop button
            Button {
                stops.append(AddressResult(title: "", subtitle: "", coordinate: .init()))
                searchTarget = .stop(stops.count - 1)
            } label: {
                Label("Add Stop", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.mtGreen)
                    .padding(.top, MTSpacing.sm)
                    .padding(.leading, MTSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Distance
            distancePill
        }
        .padding(.horizontal, MTSpacing.md)
        .padding(.vertical, MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.lg))
        .padding(.horizontal, MTSpacing.md)
    }

    private var distancePill: some View {
        Group {
            if isCalculating {
                HStack(spacing: MTSpacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating route…").font(.system(size: 13)).foregroundStyle(Color.mtTextSub)
                }
                .padding(.top, MTSpacing.sm)
                .padding(.leading, MTSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let dist = resolvedDistanceM {
                HStack(spacing: MTSpacing.sm) {
                    Image(systemName: "road.lanes").font(.system(size: 12)).foregroundStyle(Color.mtGreen)
                    Text(formatDistance(dist)).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.mtGreen)
                    Text("· \(stops.count + 1) leg\(stops.count + 1 != 1 ? "s" : "")").font(.system(size: 13)).foregroundStyle(Color.mtTextSub)
                }
                .padding(.top, MTSpacing.sm)
                .padding(.leading, MTSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: $tripDate, displayedComponents: .date)
                .font(.system(size: 15)).padding(MTSpacing.md)
            Divider().padding(.leading, MTSpacing.md)
            DatePicker("Departed", selection: $startTime, displayedComponents: .hourAndMinute)
                .font(.system(size: 15)).padding(MTSpacing.md)
                .onChange(of: startTime) { _, new in
                    if endTime <= new { endTime = new.addingTimeInterval(60) }
                }
            Divider().padding(.leading, MTSpacing.md)
            DatePicker("Arrived", selection: $endTime, displayedComponents: .hourAndMinute)
                .font(.system(size: 15)).padding(MTSpacing.md)
            Divider().padding(.leading, MTSpacing.md)
            HStack(alignment: .top) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 15)).foregroundStyle(Color.mtTextPrimary).padding(.top, 3)
                Spacer()
                TextField("Optional", text: $notes, axis: .vertical)
                    .font(.system(size: 15)).foregroundStyle(Color.mtTextPrimary)
                    .multilineTextAlignment(.trailing).lineLimit(3).frame(maxWidth: 220)
            }
            .padding(MTSpacing.md)
        }
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.lg))
        .padding(.horizontal, MTSpacing.md)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving { ProgressView().tint(.white) }
            else { Text("Save Trip") }
        }
        .buttonStyle(MTPrimaryButtonStyle())
        .disabled(!canSave)
        .padding(.horizontal, MTSpacing.md)
        .opacity(canSave ? 1 : 0.5)
    }

    // MARK: - Resolution

    private func resolve(_ completion: MKLocalSearchCompletion, for target: SearchTarget) async {
        routeError = nil
        do {
            let result = try await searcher.resolve(completion)
            switch target {
            case .start: startResult = result
            case .end:   endResult   = result
            case .stop(let i):
                if i < stops.count { stops[i] = result }
            }
            await recalculateDistance()
        } catch {
            routeError = "Couldn't resolve location: \(error.localizedDescription)"
        }
    }

    private func recalculateDistance() async {
        guard let start = startResult, let end = endResult else { return }
        // Don't recalculate if any stop hasn't been resolved yet
        guard !stops.contains(where: { $0.title.isEmpty }) else { return }

        isCalculating     = true
        routeError        = nil
        resolvedDistanceM = nil

        // Chain directions through all stops
        var total: Double = 0
        var prev = start
        let waypoints = stops + [end]
        for wp in waypoints {
            let leg = await searcher.drivingDistance(from: prev, to: wp)
            if leg == 0 { routeError = "Could not calculate a driving route."; break }
            total += leg
            prev = wp
        }
        resolvedDistanceM = total > 0 ? total : nil
        isCalculating     = false
    }

    // MARK: - Save

    private func save() async {
        guard let start = startResult, let end = endResult, let dist = resolvedDistanceM else { return }
        isSaving  = true
        saveError = nil

        let cal = Calendar.current
        let startedAt = cal.date(
            bySettingHour: cal.component(.hour, from: startTime),
            minute: cal.component(.minute, from: startTime), second: 0, of: tripDate
        ) ?? tripDate
        let endedAt = cal.date(
            bySettingHour: cal.component(.hour, from: endTime),
            minute: cal.component(.minute, from: endTime), second: 0, of: tripDate
        ) ?? tripDate

        let vehicleId = appState.profileRepo.defaultVehicle?.id ?? ""

        let stopCoords: [(lat: Double, lng: Double)] = stops.compactMap { stop in
            guard !stop.title.isEmpty else { return nil }
            return (stop.coordinate.latitude, stop.coordinate.longitude)
        }

        appState.tripRepo.saveManualTrip(
            vehicleId: vehicleId, startedAt: startedAt, endedAt: endedAt,
            distanceMetres: dist,
            startAddress: start.fullAddress, endAddress: end.fullAddress,
            startLat: start.coordinate.latitude, startLng: start.coordinate.longitude,
            endLat: end.coordinate.latitude, endLng: end.coordinate.longitude,
            stops: stopCoords,
            category: .business,
            notes: notes.isEmpty ? nil : notes
        )

        isSaving = false
        dismiss()
    }

    private func formatDistance(_ metres: Double) -> String {
        if metres < 1000 { return String(format: "%.0f m", metres) }
        return String(format: "%.1f km", metres / 1000)
    }
}

// MARK: - Stop Row

private struct StopRow: View {
    let index: Int
    let stop: AddressResult
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: MTSpacing.sm) {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
            }

            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop \(index + 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mtTextSub)
                        Text(stop.title.isEmpty ? "Tap to search" : stop.title)
                            .font(.system(size: 14, weight: stop.title.isEmpty ? .regular : .medium))
                            .foregroundStyle(stop.title.isEmpty ? Color.mtTextSub : Color.mtTextPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.mtBorder)
                }
                .padding(MTSpacing.sm + 2)
                .background(Color.mtBackground)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, MTSpacing.sm)
    }
}

// MARK: - Stop Connector

private struct StopConnector: View {
    var body: some View {
        HStack {
            Rectangle().fill(Color.mtBorder).frame(width: 1, height: 24)
                .padding(.leading, MTSpacing.md + 9)
            Spacer()
        }
        .padding(.vertical, -4)
    }
}

// MARK: - SearchTarget placeholder

private extension ManualTripSheet.SearchTarget {
    var placeholder: String {
        switch self {
        case .start: return "Start location"
        case .end:   return "End location"
        case .stop(let i): return "Stop \(i + 1)"
        }
    }
}

// MARK: - AddressField (unchanged from original)

private struct AddressField: View {
    let icon: String; let iconColor: Color
    let label: String; let value: String?; let subtitle: String?
    let placeholder: String; let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                Image(systemName: icon).foregroundStyle(iconColor).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 11)).foregroundStyle(Color.mtTextSub)
                    if let v = value {
                        Text(v).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.mtTextPrimary).lineLimit(1)
                        if let sub = subtitle, !sub.isEmpty {
                            Text(sub).font(.system(size: 12)).foregroundStyle(Color.mtTextSub).lineLimit(1)
                        }
                    } else {
                        Text(placeholder).font(.system(size: 15)).foregroundStyle(Color.mtTextSub)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.mtBorder)
            }
            .padding(MTSpacing.md).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
