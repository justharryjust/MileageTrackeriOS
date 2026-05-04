// TrackingHoursView — Settings screen for editing the per-day tracking schedule.
// Reuses DayScheduleRow and HourPicker from TrackingHoursStep.

import SwiftUI

struct TrackingHoursView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(appState.profileRepo.trackingSchedule, id: \.weekday) { day in
                    DayScheduleRowLive(day: day, repo: appState.profileRepo)
                }
            } footer: {
                Text("GPS and motion detection are paused outside your tracking hours to save battery. Changes take effect immediately.")
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
}

// MARK: - DayScheduleRowLive
// Reads/writes directly to Realm via the repo rather than using a local binding.

private struct DayScheduleRowLive: View {
    let day : DaySchedule
    let repo: UserProfileRepository

    @State private var isEnabled : Bool
    @State private var startHour : Int
    @State private var endHour   : Int

    init(day: DaySchedule, repo: UserProfileRepository) {
        self.day  = day
        self.repo = repo
        _isEnabled = State(initialValue: day.isEnabled)
        _startHour = State(initialValue: day.startHour)
        _endHour   = State(initialValue: day.endHour)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle row
            HStack {
                Text(day.weekdayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.mtTextPrimary : Color.mtTextSub)
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(Color.mtGreen)
                    .onChange(of: isEnabled) { _, new in
                        repo.setScheduleEnabled(new, weekday: day.weekday)
                    }
            }

            // Hour pickers
            if isEnabled {
                Divider()
                HStack {
                    HourPicker(label: "From", hour: $startHour)
                        .onChange(of: startHour) { _, new in
                            if endHour <= new { endHour = min(new + 1, 23) }
                            repo.setScheduleHours(start: new, end: endHour, weekday: day.weekday)
                        }
                    Divider().frame(height: 36)
                    HourPicker(label: "Until", hour: $endHour)
                        .onChange(of: endHour) { _, new in
                            if startHour >= new { startHour = max(new - 1, 0) }
                            repo.setScheduleHours(start: startHour, end: new, weekday: day.weekday)
                        }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3), value: isEnabled)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
