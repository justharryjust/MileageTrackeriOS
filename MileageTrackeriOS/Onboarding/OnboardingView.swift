// OnboardingView — step-based onboarding coordinator with clean, lightweight transitions

import SwiftUI

// MARK: - Steps Enum

enum OnboardingStep: Int, CaseIterable {
    case intro          = 0
    case jurisdiction   = 1
    case vehicleAndUnit = 2
    case claimMethod    = 3
    case permissions    = 4
    case trackingHours  = 5
    case welcome        = 6
}

// MARK: - Shared ViewModel

@Observable
final class OnboardingViewModel {
    var regionCode: String = {
        Locale.current.region?.identifier ?? "NZ"
    }()

    var jurisdiction: Jurisdiction {
        switch regionCode {
        case "NZ": return .newZealand
        case "AU": return .australia
        default:   return .other
        }
    }
    var claimMethod: ClaimMethod       = .standardRate
    var customRateTiers: [CustomRateTier] = [.initial]
    var distanceUnit: DistanceUnit     = .kilometres

    // Vehicle fields
    var vehicleName: String         = ""
    var vehicleRegistration: String = ""
    var fuelType: FuelType          = .petrol
    var initialOdometerKm: String   = ""   // captured when claim method is .logbook
    var trackingSchedule: [DayScheduleSnapshot] = DayScheduleSnapshot.defaults

    var currentStep: OnboardingStep = .intro

    var isCompleted: Bool = false

    var isVehicleValid: Bool {
        !vehicleRegistration.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { currentStep = next }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { currentStep = prev }
    }

    func complete(using appState: AppState) {
        let repo = appState.profileRepo
        repo.jurisdiction  = jurisdiction
        repo.claimMethod   = claimMethod
        repo.distanceUnit  = distanceUnit
        if claimMethod == .customRate {
            repo.setCustomRateThresholds(customRateTiers)
        }
        repo.addVehicle(
            name         : vehicleName.trimmingCharacters(in: .whitespaces),
            registration : vehicleRegistration.trimmingCharacters(in: .whitespaces)
        )
        repo.applySchedule(trackingSchedule)
        repo.hasCompletedOnboarding = true

        // Save initial odometer reading if logbook method was chosen
        if claimMethod == .logbook, let km = Double(initialOdometerKm), km > 0,
           let vehicleId = repo.defaultVehicle?.id {
            appState.odometerRepo.recordReading(
                vehicleId: vehicleId,
                readingKm: km,
                source: .onboarding
            )
        }

        appState.startTracking()
        TripLogger.shared.log("Onboarding complete — \(jurisdiction.displayName), \(claimMethod.displayName)", category: .system)
        withAnimation { isCompleted = true }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — back button + progress dots
                topBar
                    .padding(.horizontal, MTSpacing.lg)
                    .padding(.top, MTSpacing.md)

                // Step content
                stepContent
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: MTSpacing.md) {
            // Back button — hidden on first step and completion screen
            if vm.currentStep != .intro && vm.currentStep != .welcome {
                Button { vm.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mtTextSub)
                }
            } else {
                Color.clear.frame(width: 24)
            }

            // Progress dots
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= vm.currentStep.rawValue ? Color.mtGreen : Color.mtBorder)
                        .frame(
                            width: step.rawValue == vm.currentStep.rawValue ? 24 : 8,
                            height: 8
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.currentStep)
                }
            }
            .frame(maxWidth: .infinity)

            // Spacer to balance the back button
            Color.clear.frame(width: 24)
        }
        .frame(height: 32)
    }

    // MARK: - Step Content

    private var stepContent: some View {
        Group {
            switch vm.currentStep {
            case .intro:          IntroStep(vm: vm)
            case .jurisdiction:   JurisdictionStep(vm: vm)
            case .vehicleAndUnit: VehicleAndUnitStep(vm: vm)
            case .claimMethod:    ClaimMethodStep(vm: vm)
            case .permissions:    PermissionsStep(vm: vm)
            case .trackingHours:  TrackingHoursStep(vm: vm)
            case .welcome:        WelcomeStep(vm: vm)
            }
        }
        .id(vm.currentStep)
        .transition(.opacity.combined(with: .offset(y: 12)))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.currentStep)
    }
}

// MARK: - Onboarding Step Shell

struct OnboardingStepShell<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    var contentScrolls: Bool = false

    var body: some View {
        Group {
            if contentScrolls {
                ScrollView {
                    innerContent
                }
            } else {
                innerContent
            }
        }
    }

    private var innerContent: some View {
        VStack(alignment: .leading, spacing: MTSpacing.lg) {
            // Icon — smaller, less padding
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .padding(.top, MTSpacing.lg)

            // Heading
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.mtTextPrimary)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()

            Spacer(minLength: MTSpacing.xl)
        }
        .padding(.horizontal, MTSpacing.lg)
    }
}
