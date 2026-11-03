import SwiftUI
import LocalAuthentication
import UIKit

@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var enabled: Bool { didSet { updateShield() } }
    @Published private(set) var isLocked: Bool { didSet { updateShield() } }
    @Published private(set) var isAuthenticating = false
    @Published private(set) var privacyCovered = false { didSet { updateShield() } }
    @Published private(set) var lastError: String?
    private let defaults: UserDefaults
    private let settingsKey: String
    private var context: LAContext?
    private var sceneIsActive = true
    private var backgroundGeneration = 0
    private var autoAttempted = false
    private var shieldWindow: UIWindow?

    init(defaults: UserDefaults = .standard, namespace: String = "lumo") {
        self.defaults = defaults
        settingsKey = namespace + ".appLock.enabled"
        let stored = defaults.bool(forKey: settingsKey)
        enabled = stored; isLocked = stored
    }

    func setEnabled(_ value: Bool) async {
        guard value != enabled, !isAuthenticating else { return }
        let generation = backgroundGeneration
        autoAttempted = true
        if await authenticate(reason: value ? "Включить защиту данных lumo" : "Отключить защиту данных lumo") {
            enabled = value; isLocked = value && generation != backgroundGeneration
            defaults.set(value, forKey: settingsKey)
        }
    }

    func unlock() async {
        guard enabled, isLocked, !isAuthenticating, sceneIsActive else { return }
        let generation = backgroundGeneration
        autoAttempted = true
        if await authenticate(reason: "Открыть финансовые данные lumo"), generation == backgroundGeneration { isLocked = false }
    }

    func sceneChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            sceneIsActive = true; privacyCovered = false
            if enabled && isLocked && !isAuthenticating && !autoAttempted {
                autoAttempted = true
                Task { await unlock() }
            }
        case .inactive:
            sceneIsActive = false; privacyCovered = true
            // LAContext also makes the scene inactive; do not relock for that transition.
        case .background:
            sceneIsActive = false; privacyCovered = true
            backgroundGeneration += 1; autoAttempted = false
            if enabled { isLocked = true }
            context?.invalidate()
        @unknown default:
            privacyCovered = true
        }
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        let request = LAContext()
        request.localizedCancelTitle = "Отмена"
        request.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard request.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = "Защита недоступна. Настрой код-пароль iPhone в системных настройках."
            return false
        }
        isAuthenticating = true; lastError = nil; context = request
        defer { isAuthenticating = false; context = nil }
        do { return try await request.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch {
            lastError = "Разблокировка не завершена. Можно повторить и использовать код-пароль iPhone."
            return false
        }
    }

    /// A root overlay alone sits below presented sheets; this non-key app window covers those too.
    private func updateShield() {
        guard privacyCovered || (enabled && isLocked) else {
            shieldWindow?.isHidden = true
            shieldWindow?.rootViewController = nil
            shieldWindow = nil
            return
        }
        guard shieldWindow == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        let controller = UIHostingController(rootView: AppLockShieldContents(lock: self).preferredColorScheme(.dark))
        controller.view.accessibilityViewIsModal = true
        window.rootViewController = controller
        window.isHidden = false
        shieldWindow = window
    }
}

private struct AppLockShieldContents: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            LumoTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(LumoTheme.accent)
                Text("lumo").font(LumoType.balance)
                if !lock.privacyCovered {
                    if lock.isAuthenticating { ProgressView("Разблокировка…") }
                    else {
                        Button("Разблокировать") { Task { await lock.unlock() } }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    if let error = lock.lastError {
                        Text(error).font(LumoType.body).multilineTextAlignment(.center)
                    }
                }
            }.padding(28).foregroundStyle(LumoTheme.text)
        }
    }
}

struct AppLockCover<Content: View>: View {
    @ObservedObject var lock: AppLock
    private let content: Content
    init(lock: AppLock, @ViewBuilder content: () -> Content) {
        self.lock = lock; self.content = content()
    }
    private var covered: Bool { lock.privacyCovered || (lock.enabled && lock.isLocked) }
    var body: some View {
        ZStack {
            content.allowsHitTesting(!covered).accessibilityHidden(covered)
            if covered {
                AppLockShieldContents(lock: lock)
            }
        }
        .task { await lock.unlock() }
    }
}

struct AppLockSettingsView: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        Form {
            Section {
                Toggle("Face ID или код-пароль", isOn: Binding(get: { lock.enabled }, set: { value in
                    Task { await lock.setEnabled(value) }
                })).disabled(lock.isAuthenticating)
                if lock.isAuthenticating { ProgressView("Подтверди изменение…") }
                if let error = lock.lastError { Text(error).foregroundStyle(.secondary) }
            } footer: {
                Text("При возвращении из фона приложение запрашивает системную проверку. Данные скрываются в переключателе приложений. Этот экран не устанавливает новый пароль и не меняет код-пароль iPhone.")
            }
        }.navigationTitle("Защита приложения").navigationBarTitleDisplayMode(.inline)
    }
}
