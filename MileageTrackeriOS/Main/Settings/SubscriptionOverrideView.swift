// SubscriptionOverrideView — Debug tool for overriding the active subscription state.
//
// Allows developers to force SubscriptionManager.subscriptionState to any
// MTSubscriptionStatus value, bypassing real StoreKit 2 transaction data.
// The override persists across launches in DEBUG builds via UserDefaults and
// is compiled out of release builds.
//
// Visible only via Settings → Diagnostics → Subscription Override.

import SwiftUI

struct SubscriptionOverrideView: View {
    @Environment(AppState.self) private var appState

    private var manager: SubscriptionManager { appState.subscriptionManager }

    var body: some View {
        List {
            Section {
                ForEach(MTSubscriptionStatus.allCases, id: \.self) { status in
                    Button {
                        manager.setOverride(status)
                    } label: {
                        HStack {
                            Image(systemName: status.icon)
                                .foregroundStyle(iconColor(status))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text(description(for: status))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                            Spacer()
                            if manager.subscriptionState.status == status {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.mtGreen)
                            }
                        }
                    }
                }
            } header: {
                Text("Override to")
            }

            Section {
                Button(role: .destructive) {
                    manager.clearOverride()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Use Real State")
                    }
                }
                .disabled(!manager.isOverrideActive)
            } header: {
                Text("Reset")
            } footer: {
                Text("When active, the subscription state is forced to the selected value regardless of actual StoreKit transactions. The override persists across app launches in debug builds. Select \"Use Real State\" to revert.")
            }
        }
        .navigationTitle("Subscription Override")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func description(for status: MTSubscriptionStatus) -> String {
        switch status {
        case .trial: return "Free trial period — full access"
        case .active: return "Active paid subscription — full access"
        case .gracePeriod: return "Grace period after trial end — full access"
        case .expired: return "Expired — trips are locked"
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
}
