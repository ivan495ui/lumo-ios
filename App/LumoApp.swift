import SwiftUI
import LumoCore

@main
struct LumoApp: App {
    @StateObject private var model = WalletModel()
    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(LumoTheme.accent)
        }
    }
    @ViewBuilder private var appContent: some View {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["LUMO_PREVIEW_LARGE_TEXT"] == "1" {
            RootView().dynamicTypeSize(.accessibility3)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
