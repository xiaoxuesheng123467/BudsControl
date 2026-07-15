import SwiftUI

@main
struct BudsControlApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bridge = BudsBridgeClient()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(bridge)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        bridge.restartDiscovery()
                    }
                }
        }
    }
}
