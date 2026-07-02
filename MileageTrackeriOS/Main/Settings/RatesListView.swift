// RatesListView — Standalone wrapper for RateInfoView used in SettingsView.
// Reads the current jurisdiction from the environment and renders official rates.

import SwiftUI

struct RatesListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            RateInfoView(jurisdiction: appState.profileRepo.jurisdiction)
        }
        .navigationTitle("Mileage Rates")
    }
}
