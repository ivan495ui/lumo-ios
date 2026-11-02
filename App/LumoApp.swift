import SwiftUI
import LumoCore

@main
struct LumoApp: App {
    @StateObject private var model = WalletModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(LumoTheme.accent)
        }
    }
}
