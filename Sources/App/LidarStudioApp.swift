import SwiftUI

@main
struct LidarStudioApp: App {
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
