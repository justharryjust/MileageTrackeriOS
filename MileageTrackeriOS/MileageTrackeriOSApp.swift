//
//  MileageTrackeriOSApp.swift
//  Entry point — routes to onboarding or main tab view
//

import SwiftUI

@main
struct MileageTrackeriOSApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

// MARK: - Root Router

struct RootView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasSeenPaywall") private var hasSeenPaywall = false
    @State private var showPaywall = false

    var body: some View {
        // Access profileRepo directly so @Observable tracking picks up
        // hasCompletedOnboarding changes from within the onboarding flow.
        @Bindable var repo = appState.profileRepo
        if repo.hasCompletedOnboarding {
            MainTabView()
                .fullScreenCover(isPresented: $showPaywall) {
                    PaywallView()
                        .environment(appState)
                        .onDisappear {
                            hasSeenPaywall = true
                        }
                }
                .onAppear {
                    let status = appState.subscriptionManager.subscriptionState.status
                    if !hasSeenPaywall || status == .expired || status == .gracePeriod {
                        if status != .active {
                            showPaywall = true
                        }
                    }
                }
        } else {
            OnboardingView()
        }
    }
}
 
