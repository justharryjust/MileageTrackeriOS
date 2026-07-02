import SwiftUI

struct ReportingHubView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportExportView(startDate: Date().addingTimeInterval(-30 * 24 * 3600), endDate: Date())
                        .environment(appState)
                } label: {
                    Label("Mileage Report", systemImage: "doc.text.fill")
                }

                NavigationLink {
                    OdometerLogView()
                        .environment(appState)
                } label: {
                    Label("Odometer Log", systemImage: "speedometer")
                }

                NavigationLink {
                    MethodInfoView()
                        .environment(appState)
                } label: {
                    Label("Which method to choose?", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Reporting")
            }
        }
        .navigationTitle("Reporting")
    }
}
