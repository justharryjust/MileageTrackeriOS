import SwiftUI

struct SubscriptionDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    var body: some View {
        let state = appState.subscriptionManager.subscriptionState
        List {
            Section {
                HStack {
                    Image(systemName: state.status.icon)
                        .foregroundStyle(iconColor(state.status))
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mileage Tracker Pro")
                            .font(.headline)
                        Text(statusText(state))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.status == .active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    }
                }
                .padding(.vertical, 4)

                if state.status != .active {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Upgrade", systemImage: "crown.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mtGreen)
                }
            } header: {
                Text("Subscription")
            }

            Section("Details") {
                LabeledContent("Status", value: state.status.displayName)

                if let endDate = state.trialEndsAt, state.status == .trial {
                    LabeledContent("Trial ends", value: endDate.formatted(date: .abbreviated, time: .shortened))
                } else if let endDate = state.graceEndsAt, state.status == .gracePeriod {
                    LabeledContent("Grace ends", value: endDate.formatted(date: .abbreviated, time: .shortened))
                } else if !state.activePeriods.isEmpty, let last = state.activePeriods.last, let endedAt = last.endedAt {
                    LabeledContent("Expires", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(appState)
        }
    }

    private func iconColor(_ status: MTSubscriptionStatus) -> Color {
        switch status {
        case .trial: return .purple
        case .active: return .mtGreen
        case .gracePeriod: return .mtWarning
        case .expired: return .red
        }
    }

    private func statusText(_ state: MTSubscriptionState) -> String {
        switch state.status {
        case .trial:
            if let days = state.daysRemainingInTrial {
                return "Free trial \u{00B7} \(days) day\(days == 1 ? "" : "s") remaining"
            }
            return "Free trial"
        case .active:
            return "Active"
        case .gracePeriod:
            if let days = state.daysRemainingInGrace {
                return "Grace period \u{00B7} \(days) day\(days == 1 ? "" : "s") remaining"
            }
            return "Grace period"
        case .expired:
            return "Expired \u{00B7} Subscribe to regain access"
        }
    }
}
