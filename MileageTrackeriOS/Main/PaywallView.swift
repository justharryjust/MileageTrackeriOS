// PaywallView — Subscription purchase screen with monthly/annual plan options,
// trial status display, and restore purchases. Presented after onboarding or
// from the Settings "Upgrade to Pro" row.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var purchaseResult: String?

    private var subscriptionManager: SubscriptionManager { appState.subscriptionManager }
    private var state: MTSubscriptionState { subscriptionManager.subscriptionState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MTSpacing.xl) {
                    // MARK: Header
                    headerSection

                    // MARK: Plan Cards
                    planCardsSection

                    // MARK: Purchase Button
                    purchaseButton

                    // MARK: Restore / Terms
                    footerSection
                }
                .padding(.horizontal, MTSpacing.lg)
                .padding(.bottom, MTSpacing.xl)
            }
            .background(Color.mtBackground)
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.mtTextSub)
                }
            }
            .interactiveDismissDisabled(isPurchasing)
            .task {
                await subscriptionManager.fetchProducts()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: MTSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.mtGreen.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.mtGreen)
            }

            Text("Unlock Everything")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.mtTextPrimary)

            if state.status == .trial, let days = state.daysRemainingInTrial {
                Text("You have **\(days) day\(days == 1 ? "" : "s")** left in your free trial.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextSub)
                    .multilineTextAlignment(.center)
            } else if state.status == .gracePeriod, let days = state.daysRemainingInGrace {
                Text("Your trial ended. You have **\(days) day\(days == 1 ? "" : "s")** of grace remaining.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtWarning)
                    .multilineTextAlignment(.center)
            } else if state.status == .expired {
                Text("Your access has expired. Subscribe to regain access to your trips.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtWarning)
                    .multilineTextAlignment(.center)
            } else if state.status == .active {
                Text("You already have an active subscription. Enjoy all features!")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtGreen)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, MTSpacing.xl)
    }

    // MARK: - Plan Cards

    @State private var selectedPlan: MTSubscriptionPlan = .annual

    private var planCardsSection: some View {
        VStack(spacing: MTSpacing.md) {
            ForEach(subscriptionManager.products, id: \.id) { product in
                let plan: MTSubscriptionPlan = product.id == SubscriptionManager.monthlyProductID ? .monthly : .annual
                PlanCard(
                    product: product,
                    plan: plan,
                    isSelected: selectedPlan == plan,
                    onTap: { selectedPlan = plan }
                )
            }
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: MTSpacing.sm) {
            if let error = purchaseResult {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await purchase() }
            } label: {
                HStack(spacing: MTSpacing.sm) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(purchaseButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MTSpacing.sm + 2)
            }
            .buttonStyle(MTPrimaryButtonStyle())
            .disabled(isPurchasing || state.status == .active)
            .opacity(state.status == .active ? 0.5 : 1)
        }
    }

    private var purchaseButtonTitle: String {
        if state.status == .active { return "Already Subscribed" }
        if isPurchasing { return "Processing…" }
        guard let product = subscriptionManager.products.first(where: {
            selectedPlan == .monthly
                ? $0.id == SubscriptionManager.monthlyProductID
                : $0.id == SubscriptionManager.annualProductID
        }) else { return "Subscribe" }

        let frequency = selectedPlan == .monthly ? "month" : "year"
        return "Subscribe for \(product.displayPrice)/\(frequency)"
    }

    private func purchase() async {
        isPurchasing = true
        purchaseResult = nil

        guard let product = subscriptionManager.products.first(where: {
            selectedPlan == .monthly
                ? $0.id == SubscriptionManager.monthlyProductID
                : $0.id == SubscriptionManager.annualProductID
        }) else {
            purchaseResult = "Subscription product not available. Please try again."
            isPurchasing = false
            return
        }

        let success = await subscriptionManager.purchase(product)
        if success {
            dismiss()
        } else if let error = subscriptionManager.purchaseError {
            purchaseResult = error
        }
        isPurchasing = false
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: MTSpacing.md) {
            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restorePurchases()
                    if state.status == .active {
                        dismiss()
                    }
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.mtGreen)

            Text("Your subscription will automatically renew unless cancelled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions.")
                .font(.system(size: 11))
                .foregroundStyle(Color.mtTextSub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MTSpacing.xl)
        }
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let product: Product
    let plan: MTSubscriptionPlan
    let isSelected: Bool
    let onTap: () -> Void

    private var isAnnual: Bool { plan == .annual }
    private var monthlyPrice: String {
        if isAnnual {
            let monthly = product.price / 12
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = product.priceFormatStyle.currencyCode
            return "\(product.displayPrice)/yr (\(formatter.string(from: monthly as NSNumber) ?? "—")/mo)"
        }
        return product.displayPrice
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.mtGreen : Color.mtBorder, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.mtGreen)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(isAnnual ? "Annual" : "Monthly")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.mtTextPrimary)

                        if isAnnual {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mtGreen)
                                .clipShape(Capsule())
                        }
                    }

                    Text(monthlyPrice)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mtTextSub)
                }

                Spacer()
            }
            .padding(MTSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: MTRadius.md)
                    .fill(Color.mtSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: MTRadius.md)
                            .stroke(isSelected ? Color.mtGreen : Color.mtBorder, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
