// OdometerLogView — Manage odometer readings for the logbook claim method.
// Shows reading history grouped by vehicle with delta from previous reading.

import SwiftUI

struct OdometerLogView: View {
    @Environment(AppState.self) private var appState

    @State private var showingAddSheet = false
    @State private var newReadingKm: String = ""
    @State private var selectedVehicleId: String = ""

    private var repo: OdometerReadingRepository { appState.odometerRepo }
    private var vehicles: [Vehicle] { appState.profileRepo.vehicles }
    private var defaultVehicleId: String { appState.profileRepo.defaultVehicle?.id ?? "" }

    var body: some View {
        List {
            if vehicles.isEmpty {
                ContentUnavailableView(
                    "No Vehicle",
                    systemImage: "car.fill",
                    description: Text("Add a vehicle in Settings first.")
                )
            } else if repo.readings.isEmpty {
                ContentUnavailableView(
                    "No Readings",
                    systemImage: "speedometer",
                    description: Text("Record your first odometer reading to begin tracking for the logbook method.")
                )
            } else {
                ForEach(vehicles) { vehicle in
                    let readings = repo.readings(for: vehicle.id)
                    if !readings.isEmpty {
                        Section(vehicle.name.isEmpty ? vehicle.registration : vehicle.name) {
                            ForEach(readings) { reading in
                                let idx = readings.firstIndex(of: reading) ?? 0
                                let prevReading = idx + 1 < readings.count ? readings[idx + 1] : nil
                                let delta = prevReading.map { reading.readingKm - $0.readingKm }

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reading.recordedAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 14, weight: .medium))
                                        if let notes = reading.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.mtTextSub)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.0f km", reading.readingKm))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.mtTextPrimary)
                                        if let delta {
                                            Text(String(format: "+%.0f km", delta))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.mtGreen)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete { offsets in
                                for idx in offsets {
                                    repo.deleteReading(readings[idx])
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Odometer Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedVehicleId = defaultVehicleId
                    newReadingKm = ""
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                Form {
                    Section("Vehicle") {
                        Picker("Vehicle", selection: $selectedVehicleId) {
                            ForEach(vehicles) { v in
                                Text(v.name.isEmpty ? v.registration : v.name).tag(v.id)
                            }
                        }
                    }

                    Section("Reading") {
                        TextField("Odometer (km)", text: $newReadingKm)
                            .keyboardType(.decimalPad)
                    }

                    Section {
                        Button("Record Reading") {
                            if let km = Double(newReadingKm), km > 0 {
                                repo.recordReading(
                                    vehicleId: selectedVehicleId.isEmpty ? defaultVehicleId : selectedVehicleId,
                                    readingKm: km,
                                    source: .manual
                                )
                                showingAddSheet = false
                            }
                        }
                        .buttonStyle(MTPrimaryButtonStyle())
                        .disabled(Double(newReadingKm) == nil || (Double(newReadingKm) ?? 0) <= 0)
                    }
                }
                .navigationTitle("Record Reading")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showingAddSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
