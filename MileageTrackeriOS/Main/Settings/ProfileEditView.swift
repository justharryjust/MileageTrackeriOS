// ProfileEditView — Edit jurisdiction, claim method, and distance unit after onboarding.
// Changes are written immediately through UserProfileRepository.

import SwiftUI

struct ProfileEditView: View {
    @Environment(AppState.self) private var appState

    @State private var jurisdiction: Jurisdiction
    @State private var claimMethod: ClaimMethod
    @State private var distanceUnit: DistanceUnit
    @State private var customRateTiers: [CustomRateTier]

    private var repo: UserProfileRepository { appState.profileRepo }

    init() {
        let repo = AppState.shared.profileRepo
        _jurisdiction  = State(initialValue: repo.jurisdiction)
        _claimMethod   = State(initialValue: repo.claimMethod)
        _distanceUnit  = State(initialValue: repo.distanceUnit)
        _customRateTiers = State(initialValue: Self.snapshotTiers(from: repo))
    }

    var body: some View {
        Form {
            // MARK: Jurisdiction
            Section("Jurisdiction") {
                Picker("Country", selection: $jurisdiction) {
                    ForEach(Jurisdiction.allCases, id: \.self) { j in
                        Text("\(j.flag) \(j.displayName)").tag(j)
                    }
                }
                .onChange(of: jurisdiction) { _, _ in save() }
            }

            // MARK: Distance Unit
            Section("Distance Unit") {
                Picker("Unit", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .onChange(of: distanceUnit) { _, _ in save() }
            }

            // MARK: Claim Method
            Section("Claim Method") {
                ForEach(ClaimMethod.allCases, id: \.self) { method in
                    Button {
                        claimMethod = method
                        save()
                    } label: {
                        HStack(alignment: .top, spacing: MTSpacing.md) {
                            ZStack {
                                Circle()
                                    .fill(claimMethod == method ? Color.mtGreen : Color.mtBorder.opacity(0.3))
                                    .frame(width: 36, height: 36)
                                Image(systemName: method.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(claimMethod == method ? .white : Color.mtTextSub)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text(method.claimDescription)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }

                            Spacer()

                            if claimMethod == method {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.mtGreen)
                            }
                        }
                    }
                }
            }

            // MARK: Custom Rate Editor
            if claimMethod == .customRate {
                Section("Custom Rate Tiers") {
                    ForEach(Array(customRateTiers.enumerated()), id: \.element.id) { idx, _ in
                        TierRow(
                            tier: $customRateTiers[idx],
                            index: idx,
                            unit: distanceUnit.shortName,
                            canDelete: customRateTiers.count > 1,
                            onDelete: { removeTier(at: idx) }
                        )
                    }

                    Button {
                        let last = customRateTiers[customRateTiers.count - 1]
                        customRateTiers.append(CustomRateTier(
                            lowerBound: last.upperBound,
                            upperBound: last.upperBound + 5000,
                            centsPerUnit: last.centsPerUnit
                        ))
                        save()
                    } label: {
                        Label("Add Tier", systemImage: "plus.circle.fill")
                    }
                }
            }

            // MARK: Logbook Note
            if claimMethod == .logbook {
                Section {
                    VStack(alignment: .leading, spacing: MTSpacing.sm) {
                        Label("Logbook Method", systemImage: "book.closed.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Record your odometer readings in the Odometer Log. The app calculates your business-use percentage from the difference between readings during the logbook period.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextSub)
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Save

    private func save() {
        repo.jurisdiction = jurisdiction
        repo.claimMethod  = claimMethod
        repo.distanceUnit = distanceUnit

        if claimMethod == .customRate {
            repo.setCustomRateThresholds(customRateTiers)
        }

        // Reschedule notifications based on updated claim method and vehicle
        let vehicleName = repo.defaultVehicle?.name ?? ""
        appState.notificationManager.reschedule(claimMethod: claimMethod, vehicleName: vehicleName)
    }

    private func removeTier(at idx: Int) {
        customRateTiers.remove(at: idx)
        for i in idx..<customRateTiers.count {
            customRateTiers[i].lowerBound = i == 0 ? 0 : customRateTiers[i - 1].upperBound
        }
        save()
    }

    private static func snapshotTiers(from repo: UserProfileRepository) -> [CustomRateTier] {
        repo.profile.customRateThresholds.map { t in
            CustomRateTier(lowerBound: t.lowerBound, upperBound: t.upperBound, centsPerUnit: t.centsPerUnit)
        }
    }
}

// MARK: - Tier Row (inlined from ClaimMethodStep to avoid private access)

private struct TierRow: View {
    @Binding var tier: CustomRateTier
    let index: Int
    let unit: String
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            HStack {
                Text("Tier \(index + 1)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mtTextSub)
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(.red)
                    }
                }
            }

            HStack {
                Text("\(tier.lowerBound)–\(tier.upperBound) \(unit)")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text(String(format: "%.0f¢/\(unit)", tier.centsPerUnit))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.mtGreen)
            }

            Slider(value: $tier.centsPerUnit, in: 1...200, step: 1)
                .tint(Color.mtGreen)
        }
    }
}
