import SwiftUI

struct TrackingHoursStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MTSpacing.lg) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.mtGreen.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "clock.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.mtGreen)
                    }
                    .padding(.top, MTSpacing.lg)

                    // Heading
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking hours")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.mtTextPrimary)
                        Text("Set the hours you're likely to be driving for work. GPS won't activate outside these times.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mtTextSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Day rows — compact
                    VStack(spacing: 2) {
                        ForEach(sortedSchedule, id: \.wrappedValue.weekday) { binding in
                            CompactDayRow(snapshot: binding)
                        }
                    }

                    // Battery callout
                    HStack(alignment: .top, spacing: MTSpacing.sm) {
                        Image(systemName: "battery.100.bolt")
                            .foregroundStyle(Color.mtGreen)
                        Text("GPS and motion detection pause outside your tracking hours to save battery.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextSub)
                    }
                    .padding(MTSpacing.md)
                    .background(Color.mtGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))

                    Spacer(minLength: MTSpacing.xl)
                }
                .padding(.horizontal, MTSpacing.lg)
            }
            .background(Color.mtBackground)

            // Pinned Continue button
            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
                .padding(.horizontal, MTSpacing.lg)
                .padding(.vertical, MTSpacing.md)
                .background(Color.mtBackground)
        }
        .background(Color.mtBackground)
    }

    private var sortedSchedule: [Binding<DayScheduleSnapshot>] {
        let order: [Int] = [2, 3, 4, 5, 6, 7, 1] // Mon…Sun
        return order.compactMap { wd in
            guard let idx = $vm.trackingSchedule.firstIndex(where: { $0.wrappedValue.weekday == wd })
            else { return nil }
            return $vm.trackingSchedule[idx]
        }
    }
}

// MARK: - Compact Day Row

private struct CompactDayRow: View {
    @Binding var snapshot: DayScheduleSnapshot

    private let hours = Array(0..<24)

    var body: some View {
        HStack(spacing: MTSpacing.xs) {
            // Day name + toggle
            Toggle(isOn: $snapshot.isEnabled) {
                Text(snapshot.shortName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(snapshot.isEnabled ? Color.mtTextPrimary : Color.mtTextSub)
            }
            .toggleStyle(.switch)
            .tint(Color.mtGreen)
            .frame(width: 100, alignment: .leading)

            if snapshot.isEnabled {
                Spacer()

                Picker("From", selection: $snapshot.startHour) {
                    ForEach(hours, id: \.self) { h in
                        Text(hourLabel(h)).tag(h).font(.system(size: 12))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 56)

                Text("to")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mtTextSub)
                    .frame(width: 12)

                Picker("To", selection: $snapshot.endHour) {
                    ForEach(hours, id: \.self) { h in
                        Text(hourLabel(h)).tag(h).font(.system(size: 12))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 56)
                .onChange(of: snapshot.endHour) { _, new in
                    if snapshot.startHour >= new { snapshot.startHour = max(new - 1, 0) }
                }
            }
        }
        .padding(.horizontal, MTSpacing.sm)
        .padding(.vertical, 6)
        .background(snapshot.isEnabled ? Color.mtSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
        .onChange(of: snapshot.startHour) { _, new in
            if snapshot.endHour <= new { snapshot.endHour = min(new + 1, 23) }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm   = h < 12 ? "AM" : "PM"
        return "\(hour12)\(ampm)"
    }
}
