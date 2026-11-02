import SwiftUI
import LumoCore

struct RootView: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        Group {
            if model.recoveryRequired {
                NavigationStack {
                    VStack(spacing: 24) {
                        ContentUnavailableView("Нужно восстановить копию", systemImage: "externaldrive.badge.exclamationmark", description: Text("Существующие файлы сохранены. Открой настройки и импортируй исправную JSON-копию."))
                        NavigationLink("Открыть данные") { SettingsView() }.buttonStyle(.borderedProminent)
                    }.padding().navigationTitle("lumo")
                }
            } else if model.snapshot != nil {
                TabView {
                    Tab("Обзор", systemImage: "house.fill") { WalletPage(title: "lumo") { OverviewView() } }
                    Tab("Счета", systemImage: "creditcard.fill") { WalletPage(title: "Счета") { AccountsView() } }
                    Tab("Конверты", systemImage: "square.stack.3d.up.fill") { WalletPage(title: "Конверты") { EnvelopesView() } }
                    Tab("Аналитика", systemImage: "chart.bar.xaxis") { WalletPage(title: "Аналитика") { AnalyticsView() } }
                    Tab("История", systemImage: "clock.fill") { WalletPage(title: "История") { HistoryView() } }
                }
            } else {
                ProgressView("Открываем lumo…")
            }
        }
        .alert("Не получилось", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct WalletPage<Content: View>: View {
    let title: String
    let content: Content
    @State private var adding = false
    @State private var settings = false
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        NavigationStack {
            content.navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .listSectionSpacing(16)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { settings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Настройки")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить операцию")
                    }
                }
                .sheet(isPresented: $adding) { NavigationStack { TransactionForm() } }
                .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
        }
    }
}
