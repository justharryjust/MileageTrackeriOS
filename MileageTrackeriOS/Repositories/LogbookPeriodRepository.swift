// LogbookPeriodRepository - CRUD for LogbookPeriod Realm objects.
import Foundation
import Realm
import RealmSwift
@Observable
final class LogbookPeriodRepository {
    private let realm: Realm
    private(set) var periods: [LogbookPeriod] = []
    private var token: NotificationToken?
    weak var notificationManager: NotificationManager?
    init(realm: Realm) { self.realm = realm; observe() }
    deinit { token?.invalidate() }
    private func observe() {
        let results = realm.objects(LogbookPeriod.self).sorted(byKeyPath: "startedAt", ascending: false)
        token = results.observe { [weak self] _ in self?.periods = Array(results) }
        periods = Array(results)
    }
    func activePeriod(for vehicleId: String) -> LogbookPeriod? { periods.first { $0.vehicleId == vehicleId && $0.status == .active } }
    func periods(for vehicleId: String) -> [LogbookPeriod] { periods.filter { $0.vehicleId == vehicleId } }
    func completedPeriods(for vehicleId: String) -> [LogbookPeriod] { periods.filter { $0.vehicleId == vehicleId && $0.status == .complete } }
    
    @discardableResult
    func createPeriod(vehicleId: String, jurisdiction: Jurisdiction) -> LogbookPeriod {
        let period = LogbookPeriod()
        period.vehicleId = vehicleId; period.startedAt = Date()
        period.endedAt = Calendar.current.date(byAdding: .day, value: jurisdiction.logbookPeriodDays, to: period.startedAt)
        period.status = .active
        if let reading = realm.objects(OdometerReading.self).where({ q in q.vehicleId == vehicleId }).sorted(byKeyPath: "recordedAt", ascending: false).first {
            period.odometerStartKm = reading.readingKm
        }
        write { self.realm.add(period) }
        if let end = period.endedAt {
            notificationManager?.scheduleLogbookEndSoonReminder(endDate: end, daysRemaining: period.daysRemaining)
            notificationManager?.scheduleLogbookEnded(endDate: end)
        }
        return period
    }
    
    func completePeriod(_ period: LogbookPeriod, jurisdiction: Jurisdiction, businessTrips: [Trip], calculator: MileageCalculator) {
        guard period.status == .active else { return }
        let completedAt = Date()
        let businessKm = businessTrips.reduce(0) { $0 + ($1.distanceMetres / 1000) }
        let percent: Double
        if let start = period.odometerStartKm,
           let end = realm.objects(OdometerReading.self).where({ q in q.vehicleId == period.vehicleId }).sorted(byKeyPath: "recordedAt", ascending: false).first?.readingKm,
           end > start {
            percent = calculator.businessUsePercent(businessTrips: businessTrips, odometerStart: start, odometerEnd: end)
            write { period.odometerEndKm = end; period.totalOdometerKm = end - start }
        } else {
            let s = period.startedAt; let e = period.endedAt ?? completedAt
            let all = realm.objects(Trip.self).where { $0.vehicleId == period.vehicleId }.filter { $0.startedAt >= s && ($0.endedAt ?? $0.startedAt) <= e }
            let total = all.reduce(0) { $0 + ($1.distanceMetres / 1000) }
            percent = total > 0 ? min(businessKm / total, 1.0) : 0
        }
        let validUntil = Calendar.current.date(byAdding: .year, value: jurisdiction.logbookValidityYears, to: completedAt)
        write { period.completedAt = completedAt; period.status = .complete; period.businessUsePercent = percent; period.validUntil = validUntil }
        notificationManager?.cancelLogbookNotifications()
        if let v = validUntil { notificationManager?.scheduleLogbookValidityExpiry(validUntil: v) }
    }
    
    func autoCompleteExpiredPeriods(jurisdiction: Jurisdiction, calculator: MileageCalculator) {
        let now = Date()
        for period in periods where period.status == .active && (period.endedAt ?? now) <= now {
            let end = period.endedAt ?? now
            let trips = realm.objects(Trip.self).where { $0.vehicleId == period.vehicleId }.filter { $0.startedAt >= period.startedAt && ($0.endedAt ?? $0.startedAt) <= end }
            completePeriod(period, jurisdiction: jurisdiction, businessTrips: Array(trips.filter { $0.category == .business }), calculator: calculator)
        }
    }
    
    func abandonPeriods(for vehicleId: String) {
        write { for p in periods where p.vehicleId == vehicleId && p.status == .active { p.status = .abandoned; p.completedAt = Date() } }
        notificationManager?.cancelLogbookNotifications()
    }
    private func write(_ block: () -> Void) { do { try realm.write(block) } catch { print("LogbookPeriod repo write error: \(error)") } }
}
