// oardingView — NavigationStack-based 7-step onboarding coordinator

import SwiftUI

// MARK: - Steps Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome          = 0
    case jurisdiction     = 1
    case claimMethod      = 2
    case distanceUnit     = 3
    case addVehicle        = 4
    case trackingHours     = 5
    case locationPermission = 6
    case motionPermission  = 7
}

// MARK: - Shared ViewModel

@Observable
final class OnboardingViewModel {
    // Collected during onboarding
    var jurisdiction: Jurisdiction = {
        // Preselect based on device locale
        let region = Locale.current.region?.identifier ?? ""
        return region == "AU" ? .australia : .newZealand
    }()
    var claimMethod: ClaimMethod       = .standardRate
    var customRateTiers: [CustomRateTier] = [.initial]
    var distanceUnit: DistanceUnit     = .kilometres

    // Vehicle fields
    var vehicleName: String         = ""
    var vehicleRegistration: String = ""
    var fuelType: FuelType          = .petrol
    var trackingSchedule: [DayScheduleSnapshot] = DayScheduleSnapshot.defaults

    var currentStep: OnboardingStep = .welcome
    private(set) var goingForward: Bool = true

    /// Set to true when setup is done — OnboardingView observes this
    var isCompleted: Bool = false

    var isVehicleValid: Bool {
        !vehicleRegistration.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        goingForward = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { currentStep = next }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        goingForward = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { currentStep = prev }
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
                // Top bar: back button + progress
                HStack(spacing: MTSpacing.md) {
                    if vm.currentStep != .welcome {
                        Button {
                            vm.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.mtTextPrimary)
                                .frame(width: 36, height: 36)
                                .background(Color.mtSurface)
                                .clipShape(Circle())
                        }
                        .transition(.opacity)
                    } else {
                        Spacer().frame(width: 36)
                    }

                    ProgressBar(step: vm.currentStep)

                    Spacer().frame(width: 36)
                }
                .padding(.horizontal, MTSpacing.md)
                .padding(.top, MTSpacing.md)

                Spacer()
            }

            VStack {
                switch vm.currentStep {
                case .welcome:            WelcomeStep(vm: vm)
                case .jurisdiction:       JurisdictionStep(vm: vm)
                case .claimMethod:        ClaimMethodStep(vm: vm)
                case .distanceUnit:       DistanceUnitStep(vm: vm)
                case .addVehicle:         AddVehicleStep(vm: vm)
                case .trackingHours:      TrackingHoursStep(vm: vm)
                case .locationPermission: LocationPermissionStep(vm: vm)
                case .motionPermission:   MotionPermissionStep(vm: vm)
                }
            }
            .id(vm.currentStep)
            .transition(
                .asymmetric(
                    insertion: .move(edge: vm.goingForward ? .trailing : .leading).combined(with: .opacity),
                    removal:   .move(edge: vm.goingForward ? .leading  : .trailing).combined(with: .opacity)
                )
            )
            .padding(.top, 50)
        }
        // No broad .animation here — each transition is driven by withAnimation in advance()/goBack()
    }
}

// MARK: - Progress Bar

private struct ProgressBar: View {
    let step: OnboardingStep

    private var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.mtBorder).frame(height: 4)
                Capsule().fill(Color.mtGreen)
                    .frame(width: max(geo.size.width * progress, 0), height: 4)
                    .animation(.spring(response: 0.5), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Onboarding Step Shell

struct OnboardingStepShell<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MTSpacing.lg) {
                // Icon — animates independently with scale+fade
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                .padding(.top, MTSpacing.xxl + 10)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .id(icon) // triggers its own transition when icon changes between steps

                // Heading
                VStack(alignment: .leading, spacing: MTSpacing.sm) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mtTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()

                Spacer(minLength: MTSpacing.xxl)
            }
            .padding(.horizontal, MTSpacing.lg)
        }
    }
}
