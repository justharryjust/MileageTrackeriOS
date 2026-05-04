import SwiftUI

struct TrackingHoursStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "clock.fill",
            iconColor: .mtGreen,
            title: "Tracking hours",
            subtitle: "Set the hours you're likely to be driving for work. The app won't use GPS or battery outside these hours."
        ) {
            VStack(spacing: MTSpacing.sm) {
                ForEach($vm.trackingSchedule) { day in
                    DayScheduleRow(snapshot: day)
                }
            }
            .padding(MTSpacing.sm)
            .mtCard()

            // Info callout
            HStack(alignment: .top, spacing: MTSpacing.sm) {
                Image(systemName: "battery.100.bolt")
                    .foregroundStyle(Color.mtGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery friendly")
                        .font(.system(size: 14, weight: .semibold))
                    Text("GPS and motion detection pause outside your tracking hours — your battery thanks you.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
            }
            .padding(MTSpacing.md)
            .background(Color.mtGreen.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))

            Spacer(minLength: MTSpacing.md)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
        }
    }
}

// MARK: - DayScheduleRow

struct DayScheduleRow: View {
    @Binding var snapshot: DayScheduleSnapshot

    var body: some View {
        VStack(spacing: 0) {
            // Day header + toggle
            HStack {
                Text(snapshot.weekdayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(snapshot.isEnabled ? Color.mtTextPrimary : Color.mtTextSub)
                Spacer()
                Toggle("", isOn: $snapshot.isEnabled)
                    .labelsHidden()
                    .tint(Color.mtGreen)
            }
            .padding(.horizontal, MTSpacing.md)
            .padding(.vertical, MTSpacing.sm)

            // Hour pickers — greyed out when disabled
            if snapshot.isEnabled {
                Divider().padding(.leading, MTSpacing.md)
                HStack {
                    HourPicker(label: "From", hour: $snapshot.startHour)
                        .onChange(of: snapshot.startHour) { _, new in
                            if snapshot.endHour <= new { snapshot.endHour = min(new + 1, 23) }
                        }
                    Divider().frame(height: 36)
                    HourPicker(label: "Until", hour: $snapshot.endHour)
                        .onChange(of: snapshot.endHour) { _, new in
                            if snapshot.startHour >= new { snapshot.startHour = max(new - 1, 0) }
                        }
                }
                .padding(.horizontal, MTSpacing.md)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.mtBackground)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
        .animation(.spring(response: 0.3), value: snapshot.isEnabled)
    }
}

// MARK: - HourPicker

struct HourPicker: View {
    let label: String
    @Binding var hour: Int

    private var displayTime: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(ampm)"
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.mtTextSub)
                .frame(width: 34, alignment: .leading)
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(hourLabel(h)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 80)
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }

    private func hourLabel(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm   = h < 12 ? "AM" : "PM"
        return "\(hour12):00 \(ampm)"
    }
}
