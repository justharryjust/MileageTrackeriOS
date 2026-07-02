import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Onboarding Navigation")
@MainActor
struct OnboardingNavigationTests {

    @Test("ViewModel starts at .intro by default")
    func startsAtIntro() {
        let vm = OnboardingViewModel()
        #expect(vm.currentStep == .intro)
    }

    @Test("advance increments currentStep forward")
    func advanceMovesForward() {
        let vm = OnboardingViewModel()
        vm.advance()
        #expect(vm.currentStep == .jurisdiction)
        vm.advance()
        #expect(vm.currentStep == .vehicleAndUnit)
    }

    @Test("goBack decrements currentStep")
    func goBackMovesBack() {
        let vm = OnboardingViewModel()
        vm.advance()  // .jurisdiction
        vm.advance()  // .vehicleAndUnit
        #expect(vm.currentStep == .vehicleAndUnit)

        vm.goBack()
        #expect(vm.currentStep == .jurisdiction)
    }

    @Test("goBack does not go past .intro")
    func goBackStopsAtIntro() {
        let vm = OnboardingViewModel()
        #expect(vm.currentStep == .intro)
        vm.goBack()
        #expect(vm.currentStep == .intro)
    }

    @Test("advance does not go past .welcome")
    func advanceStopsAtWelcome() {
        let vm = OnboardingViewModel()
        for _ in 0..<OnboardingStep.allCases.count {
            vm.advance()
        }
        #expect(vm.currentStep == .welcome)
        vm.advance()
        #expect(vm.currentStep == .welcome)
    }

    @Test("isVehicleValid is false when registration is empty")
    func vehicleInvalidWithoutRegistration() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = ""
        #expect(vm.isVehicleValid == false)
    }

    @Test("isVehicleValid is false when registration is whitespace only")
    func vehicleInvalidWithWhitespaceOnly() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = "   "
        #expect(vm.isVehicleValid == false)
    }

    @Test("isVehicleValid is true when registration is non-empty")
    func vehicleValidWithRegistration() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = "ABC123"
        #expect(vm.isVehicleValid == true)
    }

    @Test("Advancing from intro reaches vehicleAndUnit in exactly 2 steps")
    func pathFromIntroToVehicle() {
        let vm = OnboardingViewModel()
        vm.advance()
        vm.advance()
        #expect(vm.currentStep == .vehicleAndUnit)
    }

    @Test("goBack from vehicleAndUnit returns to jurisdiction (the previous step)")
    func backFromVehicleToJurisdiction() {
        let vm = OnboardingViewModel()
        vm.advance()  // .jurisdiction
        vm.advance()  // .vehicleAndUnit
        #expect(vm.currentStep == .vehicleAndUnit)

        vm.goBack()
        #expect(vm.currentStep == .jurisdiction)

}

}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 15 — Report Export
// MARK: ═══════════════════════════════════════════════

