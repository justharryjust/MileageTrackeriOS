import SwiftUI
struct LogbookPeriodView: View {
    @Environment(AppState.self) private var appState
    private var activePeriod: LogbookPeriod? {
        guard let vid = appState.profileRepo.defaultVehicle?.id else { return nil }
        return appState.logbookPeriodRepo.activePeriod(for: vid)
    }
    private var completedPeriods: [LogbookPeriod] {
        guard let vid = appState.profileRepo.defaultVehicle?.id else { return [] }
        return appState.logbookPeriodRepo.completedPeriods(for: vid)
    }
    private var jurisdiction: Jurisdiction { appState.profileRepo.jurisdiction }
    var body: some View {
        List {
            if let p = activePeriod { activePeriodSection(p) } else { noActivePeriodSection() }
            if !completedPeriods.isEmpty { completedPeriodsSection() }
        }.navigationTitle("Logbook Period")
    }
    @ViewBuilder
    private func activePeriodSection(_ period: LogbookPeriod) -> some View {
        if jurisdiction.logbookRegime == .continuous {
            continuousActivePeriodSection(period)
        } else {
            sampleActivePeriodSection(period)
        }
    }

    @ViewBuilder
    private func sampleActivePeriodSection(_ period: LogbookPeriod) -> some View {
        Section("Active Period") {
            VStack(alignment: .leading, spacing: 12) {
                let total = period.totalDays; let remaining = period.daysRemaining; let elapsed = max(0, total - remaining)
                let progress = total > 0 ? Double(elapsed) / Double(total) : 0
                HStack { Text("\(elapsed) of \(total) days").font(.system(size: 15, weight: .medium)); Spacer(); Text("\(remaining) remaining").font(.system(size: 13)).foregroundStyle(Color.mtTextSub) }
                ProgressView(value: progress).tint(Color.mtGreen)
                detailRow("Started", period.startedAt.formatted(date: .abbreviated, time: .omitted))
                if let e = period.endedAt { detailRow("Ends", e.formatted(date: .abbreviated, time: .omitted)) }
                if let v = appState.profileRepo.vehicles.first(where: { $0.id == period.vehicleId }) { detailRow("Vehicle", v.name.isEmpty ? v.registration : v.name) }
                if let odo = period.odometerStartKm { detailRow("Start Odometer", String(format: "%.0f km", odo)) }
                else {
                    detailRow("Start Odometer", "Not recorded")
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Record an odometer reading in Odometer Log for accurate business-use calculation.").font(.system(size: 12)).foregroundStyle(.orange)
                    }.padding(10).background(.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Button("Complete Period", role: .destructive) { completePeriod(period) }.font(.system(size: 15, weight: .medium))
        }
    }

    @ViewBuilder
    private func continuousActivePeriodSection(_ period: LogbookPeriod) -> some View {
        Section("Active Logbook Record") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.closed.fill").foregroundStyle(Color.mtGreen)
                    Text("Ongoing every-trip record").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.mtGreen)
                    Spacer()
                }
                detailRow("Started", period.startedAt.formatted(date: .abbreviated, time: .omitted))
                if let v = appState.profileRepo.vehicles.first(where: { $0.id == period.vehicleId }) { detailRow("Vehicle", v.name.isEmpty ? v.registration : v.name) }
                if let odo = period.odometerStartKm { detailRow("Start Odometer", String(format: "%.0f km", odo)) }
                else {
                    detailRow("Start Odometer", "Not recorded")
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Record an odometer reading in Odometer Log for accurate business-use calculation.").font(.system(size: 12)).foregroundStyle(.orange)
                    }.padding(10).background(.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Button("Complete Period", role: .destructive) { completePeriod(period) }.font(.system(size: 15, weight: .medium))
        }
    }

    @ViewBuilder
    private func noActivePeriodSection() -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "book.closed").font(.system(size: 40)).foregroundStyle(Color.mtTextSub)
                Text("No Active Logbook Period").font(.system(size: 17, weight: .semibold))
                if jurisdiction.logbookRegime == .continuous {
                    Text("Record every business trip to calculate your business-use percentage. Keep ongoing records for compliance.").font(.system(size: 14)).foregroundStyle(Color.mtTextSub).multilineTextAlignment(.center)
                } else {
                    Text("Start a \(jurisdiction.logbookPeriodDays)-day logbook period.").font(.system(size: 14)).foregroundStyle(Color.mtTextSub).multilineTextAlignment(.center)
                }
                Button { startNewPeriod() } label: { Label("Start New Period", systemImage: "plus.circle.fill") }.buttonStyle(.borderedProminent).tint(Color.mtGreen)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }
    @ViewBuilder
    private func completedPeriodsSection() -> some View {
        Section("Completed Periods") {
            ForEach(completedPeriods) { period in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { if let pct = period.businessUsePercent { Text("\(Int(pct * 100))% business use").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.mtGreen) }; Spacer(); Text(period.status == .abandoned ? "Abandoned" : "Complete").font(.system(size: 12)).foregroundStyle(Color.mtTextSub) }
                    Text("\(period.startedAt.formatted(date: .abbreviated, time: .omitted)) - \(period.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")").font(.system(size: 13)).foregroundStyle(Color.mtTextSub)
                    if let v = period.validUntil { Text("Valid until \(v.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub) }
                }.padding(.vertical, 4)
            }
        }
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).font(.system(size: 13)).foregroundStyle(Color.mtTextSub).frame(width: 110, alignment: .leading); Text(value).font(.system(size: 13)).foregroundStyle(Color.mtTextPrimary); Spacer() }
    }
    private func completePeriod(_ period: LogbookPeriod) {
        let j = appState.profileRepo.jurisdiction; let end = period.endedAt ?? Date()
        let bt = appState.tripRepo.businessTrips.filter { $0.vehicleId == period.vehicleId && $0.startedAt >= period.startedAt && ($0.endedAt ?? $0.startedAt) <= end }
        appState.logbookPeriodRepo.completePeriod(period, jurisdiction: j, businessTrips: bt, calculator: appState.mileageCalculator)
    }
    private func startNewPeriod() {
        guard let vid = appState.profileRepo.defaultVehicle?.id else { return }
        appState.logbookPeriodRepo.createPeriod(vehicleId: vid, jurisdiction: appState.profileRepo.jurisdiction)
    }
}
