// ReportExportView — Date-range picker, trip preview, and CSV export for mileage expense reports.

import SwiftUI
import StoreKit

struct ReportExportView: View {
    @Environment(AppState.self) private var appState

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedVehicleId: String = ""
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showPaywallForExport = false

    private var subscriptionManager: SubscriptionManager { appState.subscriptionManager }

    private var profile: UserProfile { appState.profileRepo.profile }
    private var trips: [Trip] { appState.tripRepo.allTrips }
    private var vehicles: [Vehicle] { appState.profileRepo.vehicles }

    private var filteredTrips: [Trip] {
        trips.filter { trip in
            let inRange = trip.startedAt >= startDate && trip.startedAt <= endDate
            let matchesVehicle = selectedVehicleId.isEmpty || trip.vehicleId == selectedVehicleId
            let isBusiness = trip.category == .business
            return inRange && matchesVehicle && isBusiness
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    private var totalDistance: Double {
        filteredTrips.reduce(0) { $0 + ($1.distanceMetres / 1000) }
    }

    /// Cumulative business km from tax-year start to the report's start date.
    private var baseCumulativeKm: Double {
        let taxYearStart = profile.jurisdiction.taxYear.containing(startDate).start
        return appState.tripRepo.allTrips
            .filter { $0.category == .business && $0.startedAt >= taxYearStart && $0.startedAt < startDate }
            .reduce(0) { $0 + ($1.distanceMetres / 1000) }
    }

    private var totalValue: Double {
        var cumKm = baseCumulativeKm
        return filteredTrips.reduce(0) { total, trip in
            cumKm += trip.distanceMetres / 1000
            return total + appState.mileageCalculator.dollarValue(for: trip, profile: profile, cumulativeKm: cumKm)
        }
    }

    init(startDate: Date, endDate: Date) {
        _startDate = State(initialValue: startDate)
        _endDate = State(initialValue: endDate)
    }

    var body: some View {
        List {
            // MARK: Date Range
            Section("Period") {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)

                HStack(spacing: MTSpacing.sm) {
                    ForEach(presets, id: \.label) { preset in
                        Button(preset.label) {
                            (startDate, endDate) = preset.range()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.mtGreen)
                        .font(.system(size: 13))
                    }
                }
            }

            // MARK: Method
            Section("Claim Method") {
                HStack {
                    Text("Method")
                    Spacer()
                    Text(profile.claimMethod.displayName)
                        .foregroundStyle(Color.mtTextSub)
                }
                HStack {
                    Text("Jurisdiction")
                    Spacer()
                    Text(profile.jurisdiction.displayName)
                        .foregroundStyle(Color.mtTextSub)
                }
                if vehicles.count > 1 {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        Text("All").tag("")
                        ForEach(vehicles) { v in
                            Text(v.name.isEmpty ? v.registration : v.name).tag(v.id)
                        }
                    }
                }
            }

            // MARK: Summary
            Section("Summary") {
                HStack {
                    Text("Trips")
                    Spacer()
                    Text("\(filteredTrips.count)")
                        .foregroundStyle(Color.mtTextSub)
                }
                HStack {
                    Text("Total Distance")
                    Spacer()
                    Text(String(format: "%.1f \(unit)", totalDistance))
                        .foregroundStyle(Color.mtTextSub)
                }
                HStack {
                    Text("Estimated Value")
                    Spacer()
                    Text(String(format: "$%.2f", totalValue))
                        .foregroundStyle(Color.mtGreen)
                        .fontWeight(.semibold)
                }
            }

            // MARK: Trip Preview
            Section("Trips") {
                if filteredTrips.isEmpty {
                    Text("No trips in this period")
                        .foregroundStyle(Color.mtTextSub)
                } else {
                    ForEach(filteredTrips.prefix(10)) { trip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 14, weight: .medium))
                            Text("\(trip.distanceString) — \(trip.startAddress)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mtTextSub)
                                .lineLimit(1)
                        }
                    }
                    if filteredTrips.count > 10 {
                        Text("… and \(filteredTrips.count - 10) more")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextSub)
                    }
                }
            }

            // MARK: Export
            Section {
                Button {
                    if subscriptionManager.subscriptionState.status.allowsAccess
                        || subscriptionManager.areAllTripsAccessible(filteredTrips) {
                        performExport()
                    } else {
                        showPaywallForExport = true
                    }
                } label: {
                    Label("Export CSV Report", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(filteredTrips.isEmpty)

                Button {
                    if subscriptionManager.subscriptionState.status.allowsAccess
                        || subscriptionManager.areAllTripsAccessible(filteredTrips) {
                        let url = appState.reportGenerator.exportPDF(
                            trips: filteredTrips,
                            calculator: appState.mileageCalculator,
                            profile: profile,
                            vehicles: vehicles,
                            dateRange: (startDate, endDate),
                            baseCumulativeKm: baseCumulativeKm
                        )
                        exportURL = url
                        isExporting = true
                    } else {
                        showPaywallForExport = true
                    }
                } label: {
                    Label("Export PDF Logbook", systemImage: "doc.richtext.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MTPrimaryButtonStyle())
                .tint(Color.mtGreen)
                .disabled(filteredTrips.isEmpty)
            }
        }
        .navigationTitle("Mileage Report")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isExporting) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showPaywallForExport) {
            PaywallView()
                .environment(appState)
        }
        .onAppear {
            selectedVehicleId = appState.profileRepo.defaultVehicle?.id ?? ""
        }
    }

    private var unit: String { profile.distanceUnit.shortName }

    private var presets: [(label: String, range: () -> (Date, Date))] {
        let now = Date()
        let ty = profile.jurisdiction.taxYear
        let current = ty.containing(now)
        return [
            ("This Year", { current }),
            ("Last Year", { ty.containing(
                Calendar.current.date(byAdding: .year, value: -1, to: current.start) ?? current.start
            )}),
            ("All Time", { (
                trips.map(\.startedAt).min() ?? Date().addingTimeInterval(-365 * 24 * 3600),
                Date()
            )}),
        ]
    }

    private func performExport() {
        let url = appState.reportGenerator.exportCSV(
            trips: filteredTrips,
            calculator: appState.mileageCalculator,
            profile: profile,
            dateRange: (startDate, endDate),
            baseCumulativeKm: baseCumulativeKm
        )
        exportURL = url
        isExporting = true
    }
}
