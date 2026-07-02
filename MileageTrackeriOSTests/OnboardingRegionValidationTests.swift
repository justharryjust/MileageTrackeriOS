import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Onboarding Region Validation")
@MainActor
struct OnboardingRegionValidationTests {

    @Test("isRegionValid is false when regionCode is empty")
    func emptyRegionIsInvalid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = ""
        #expect(vm.isRegionValid == false)
    }

    @Test("isRegionValid is true when regionCode is NZ")
    func nzRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NZ"
        #expect(vm.isRegionValid == true)
    }

    @Test("isRegionValid is true when regionCode is AU")
    func auRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "AU"
        #expect(vm.isRegionValid == true)
    }

    @Test("isRegionValid is true when regionCode is Other (--)")
    func otherRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "--"
        #expect(vm.isRegionValid == true)
    }

    @Test("jurisdiction is .newZealand when regionCode is NZ")
    func nzJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NZ"
        #expect(vm.jurisdiction == .newZealand)
    }

    @Test("jurisdiction is .australia when regionCode is AU")
    func auJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "AU"
        #expect(vm.jurisdiction == .australia)
    }

    @Test("jurisdiction is .other when regionCode is empty")
    func emptyJurisdictionIsOther() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = ""
        #expect(vm.jurisdiction == .other)
    }

    @Test("jurisdiction is .other when regionCode is -- (explicit Other)")
    func explicitOtherJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "--"
        #expect(vm.jurisdiction == .other)
    }
}

// MARK: - ═══════════════════════════════

// MARK:   Suite 12 — Trip Repository Deletion
// MARK: ═══════════════════════════════

