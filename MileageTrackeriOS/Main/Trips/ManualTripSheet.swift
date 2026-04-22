// ManualTripSheet — bottom-sheet for logging a trip manually.
// User picks start + end address, date, and optionally a time range.
// MKDirections calculates the driving distance; haversine is the offline fallback.

import SwiftUI
import MapKit

struct ManualTripSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // MARK: Form state
    @State private var startResult : AddressResult?
    @State private var endResult   : AddressResult?
    @State private var tripDate    : Date = Date()
    @State private var startTime   : Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime     : Date = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var notes       : String = ""
    @State private var category    : TripCategory = .business

    // MARK: Resolution state
    @State private var searcher          = AddressSearcher()
    @State private var resolvedDistanceM : Double?
    @State private var isCalculating     : Bool = false
    @State private var routeError        : String?

    // MARK: Search sheet
    @State private var searchTarget : SearchTarget?
    enum SearchTarget: Identifiable {
        case start, end
        var id: Int { hashValue }
        var placeholder: String {
            switch self { case .start: return "Start location"; case .end: return "End location" }
        }
    }

    // MARK: Save state
    @State private var isSaving  : Bool = false
    @State private var saveError : String?

    private var canSave: Bool {
        startResult != nil && endResult != nil && resolvedDistanceM != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MTSpacing.lg) {
                    routeSection
                    detailsSection
                    if let err = routeError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.mtRecording)
                            .padding(.horizontal, MTSpacing.md)
                    }
                    if let err = saveError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.mtRecording)
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
                icon      : "circle.fill",
                iconColor : .mtGreen,
                label     : "Start",
                value     : startResult?.title,
                subtitle  : startResult?.subtitle,
                placeholder: "Pick a start location"
            ) {
                searchTarget = .start
            }

            // Connector line
            HStack {
                Rectangle()
                    .fill(Color.mtBorder)
                    .frame(width: 1, height: 24)
                    .padding(.leading, MTSpacing.md + 9)  // align with icon centre
                Spacer()
            }
            .padding(.vertical, -4)

            // End
            AddressField(
                icon      : "mappin.circle.fill",
                iconColor : .mtRecording,
                label     : "End",
                value     : endResult?.title,
                subtitle  : endResult?.subtitle,
                placeholder: "Pick an end location"
            ) {
                searchTarget = .end
            }

            // Distance pill
            if isCalculating {
                HStack(spacing: MTSpacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating route…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
                .padding(.top, MTSpacing.sm)
                .padding(.leading, MTSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let dist = resolvedDistanceM {
                HStack(spacing: MTSpacing.sm) {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mtGreen)
                    Text(formatDistance(dist))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtGreen)
                    Text("driving distance")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
                .padding(.top, MTSpacing.sm)
                .padding(.leading, MTSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MTSpacing.md)
        .padding(.vertical, MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.lg))
        .padding(.horizontal, MTSpacing.md)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(spacing: 0) {
            // Category
            HStack {
                Label("Category", systemImage: "tag")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextPrimary)
                Spacer()
                Picker("", selection: $category) {
                    Text("Business").tag(TripCategory.business)
                    Text("Personal").tag(TripCategory.personal)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(MTSpacing.md)

            Divider().padding(.leading, MTSpacing.md)

            // Date
            DatePicker("Date", selection: $tripDate, displayedComponents: .date)
                .font(.system(size: 15))
                .padding(MTSpacing.md)

            Divider().padding(.leading, MTSpacing.md)

            // Start time
            DatePicker("Departed", selection: $startTime, displayedComponents: .hourAndMinute)
                .font(.system(size: 15))
                .padding(MTSpacing.md)
                .onChange(of: startTime) { _, new in
                    // Keep end time at least 1 min after start
                    if endTime <= new {
                        endTime = new.addingTimeInterval(60)
                    }
                }

            Divider().padding(.leading, MTSpacing.md)

            // End time
            DatePicker("Arrived", selection: $endTime, displayedComponents: .hourAndMinute)
                .font(.system(size: 15))
                .padding(MTSpacing.md)

            Divider().padding(.leading, MTSpacing.md)

            // Notes
            HStack(alignment: .top) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextPrimary)
                    .padding(.top, 3)
                Spacer()
                TextField("Optional", text: $notes, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextPrimary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .frame(maxWidth: 220)
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
            if isSaving {
                ProgressView().tint(.white)
            } else {
                Text("Save Trip")
            }
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
            }
            await recalculateDistance()
        } catch {
            routeError = "Couldn't resolve location: \(error.localizedDescription)"
        }
    }

    private func recalculateDistance() async {
        guard let start = startResult, let end = endResult else { return }
        isCalculating     = true
        routeError        = nil
        resolvedDistanceM = nil
        let dist = await searcher.drivingDistance(from: start, to: end)
        resolvedDistanceM = dist
        isCalculating     = false
        if dist == 0 { routeError = "Could not calculate a driving route. Distance may be approximate." }
    }

    // MARK: - Save

    private func save() async {
        guard let start = startResult,
              let end   = endResult,
              let dist  = resolvedDistanceM else { return }

        isSaving  = true
        saveError = nil

        // Combine date + time components
        let cal      = Calendar.current
        let startedAt = cal.date(
            bySettingHour   : cal.component(.hour,   from: startTime),
            minute          : cal.component(.minute, from: startTime),
            second          : 0,
            of              : tripDate
        ) ?? tripDate

        let endedAt = cal.date(
            bySettingHour   : cal.component(.hour,   from: endTime),
            minute          : cal.component(.minute, from: endTime),
            second          : 0,
            of              : tripDate
        ) ?? tripDate

        let vehicleId = appState.profileRepo.defaultVehicle?.id ?? ""

        appState.tripRepo.saveManualTrip(
            vehicleId       : vehicleId,
            startedAt       : startedAt,
            endedAt         : endedAt,
            distanceMetres  : dist,
            startAddress    : start.fullAddress,
            endAddress      : end.fullAddress,
            startLat        : start.coordinate.latitude,
            startLng        : start.coordinate.longitude,
            endLat          : end.coordinate.latitude,
            endLng          : end.coordinate.longitude,
            category        : category,
            notes           : notes.isEmpty ? nil : notes
        )

        isSaving = false
        dismiss()
    }

    // MARK: - Helpers

    private func formatDistance(_ metres: Double) -> String {
        if metres < 1000 { return String(format: "%.0f m", metres) }
        return String(format: "%.1f km", metres / 1000)
    }
}

// MARK: - AddressField

private struct AddressField: View {
    let icon       : String
    let iconColor  : Color
    let label      : String
    let value      : String?
    let subtitle   : String?
    let placeholder: String
    let onTap      : () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mtTextSub)
                    if let v = value {
                        Text(v)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.mtTextPrimary)
                            .lineLimit(1)
                        if let sub = subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mtTextSub)
                                .lineLimit(1)
                        }
                    } else {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mtTextSub)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.mtBorder)
            }
            .padding(MTSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
