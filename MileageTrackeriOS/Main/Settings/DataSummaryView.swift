import SwiftUI

struct DataSummaryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                LabeledContent("Total trips", value: "\(appState.tripRepo.allTrips.count)")
                LabeledContent("Business trips", value: "\(appState.tripRepo.businessTrips.count)")
                LabeledContent("Needs review", value: "\(appState.tripRepo.uncategorisedTrips.count)")
            } header: {
                Text("Trip Data")
            }
        }
        .navigationTitle("Data")
    }
}
