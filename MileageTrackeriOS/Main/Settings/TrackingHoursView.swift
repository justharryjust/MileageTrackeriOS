// TrackingHoursView — Settings screen for editing the per-day tracking schedule.

import SwiftUI

struct TrackingHoursView: View {
    @Environment(AppState.self) private var appState

    /// Mon…Sun weekday order
    private let dayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        List {
            Section {
                ForEach(sortedDays, id: \.weekday) { day in
                    CompactDayRowLive(day: day, repo: appState.profileRepo)
                }
            } footer: {
                Text("GPS and motion detection are paused outside your tracking hours to save battery.")
            }

            Section {
                Button("Reset to defaults") {
                    appState.profileRepo.applySchedule(DayScheduleSnapshot.defaults)
                }
                .foregroundStyle(Color.mtGreen)
            }
        }
        .navigationTitle("Tracking Hours")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedDays: [DaySchedule] {
        dayOrder.compactMap { wd in
            appState.profileRepo.trackingSchedule.first { $0.weekday == wd }
        }
    }
}

// MARK: - Compact Day Row (Live Realm)

private struct CompactDayRowLive: View {
    let day: DaySchedule
    let repo: UserProfileRepository

    @State private var isEnabled: Bool
    @State private var startHour: Int
    @State private var endHour: Int

    private let hours = Array(0..<24)

    init(day: DaySchedule, repo: UserProfileRepository) {
        self.day  = day
        self.repo = repo
        _isEnabled = State(initialValue: day.isEnabled)
        _startHour = State(initialValue: day.startHour)
        _endHour   = State(initialValue: day.endHour)
    }

    var body: some View {
        HStack(spacing: MTSpacing.sm) {
            Toggle(isOn: $isEnabled) {
                Text(day.weekdayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.mtTextPrimary : Color.mtTextSub)
            }
            .toggleStyle(.switch)
            .tint(Color.mtGreen)
            .frame(width: 130, alignment: .leading)
            .onChange(of: isEnabled) { _, new in
                repo.setScheduleEnabled(new, weekday: day.weekday)
            }

            if isEnabled {
                Picker("From", selection: $startHour) {
                    ForEach(hours, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                }
                .pickerStyle(.menu)
                .onChange(of: startHour) { _, new in
                    if endHour <= new { endHour = min(new + 1, 23) }
                    repo.setScheduleHours(start: new, end: endHour, weekday: day.weekday)
                }

                Text("to")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mtTextSub)

                Picker("To", selection: $endHour) {
                    ForEach(hours, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                }
                .pickerStyle(.menu)
                .onChange(of: endHour) { _, new in
                    if startHour >= new { startHour = max(new - 1, 0) }
                    repo.setScheduleHours(start: startHour, end: new, weekday: day.weekday)
                }
            } else {
                Spacer()
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: MTSpacing.md, bottom: 4, trailing: MTSpacing.md))
    }

    private func hourLabel(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm   = h < 12 ? "AM" : "PM"
        return "\(hour12):00 \(ampm)"
    }
}
