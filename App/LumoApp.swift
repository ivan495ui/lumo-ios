import SwiftUI
import LumoCore

@main
struct LumoApp: App {
    @StateObject private var model = WalletModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppLockCover(lock: model.appLock) { appContent }
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(LumoTheme.accent)
                .onChange(of: scenePhase) { _, phase in
                    model.appLock.sceneChanged(phase)
                    if phase == .active {
                        model.automaticBackup.retry()
                        Task { await model.exchange.refresh(base: model.currency) }
                    }
                }
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
