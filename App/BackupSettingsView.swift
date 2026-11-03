import SwiftUI
import UniformTypeIdentifiers
import UIKit
import LumoCore

struct BackupSettingsView: View {
    @EnvironmentObject var model: WalletModel
    @ObservedObject var service: AutomaticBackup
    var onRestore: ((String, String) -> Void)? = nil
    @State private var password = ""
    @State private var confirmation = ""
    @State private var choosingFolder = false
    @State private var choosingFile = false
    @State private var disconnecting = false
    @State private var busy = false
    @State private var message: String?
    @State private var restoreData: Data?
    @State private var restorePassword = ""
    @State private var candidateJSON: String?
    @State private var candidate: Snapshot?
    @State private var confirmingRestore = false
    @State private var actualCurrency = ""

    var body: some View {
        Form {
            Section {
                Text(service.status).font(LumoType.body)
                if service.configured { LabeledContent("Папка", value: service.folderName) }
                if let date = service.lastWrite {
                    LabeledContent("Последняя запись в папку", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if service.isWorking { ProgressView("Обновляем копию…") }
                if let error = service.lastError { Text(error).foregroundStyle(.red).font(LumoType.caption) }
                if service.configured {
                    Button("Повторить сейчас") {
                        if !model.recoveryRequired, let json = try? model.exportText() { service.record(json) }
                        else { service.retry() }
                    }.disabled(service.isWorking || busy)
                    Button("Отключить автоматическую копию", role: .destructive) { disconnecting = true }
                        .disabled(service.isWorking || busy)
                }
            } header: { Text("Автоматическая копия") }
            footer: {
                Text("После изменений приложение обновляет текущую и предыдущую зашифрованные копии в выбранной папке. При недоступной папке изменения остаются на iPhone, повтор выполняется при открытии приложения. Запись файла не гарантирует завершение его загрузки в облако.")
            }

            if !service.configured {
                Section {
                    SecureField("Пароль восстановления · от 10 символов", text: $password)
                        .textContentType(.newPassword).autocorrectionDisabled()
                    SecureField("Повтори пароль", text: $confirmation)
                        .textContentType(.newPassword).autocorrectionDisabled()
                    Button("Выбрать папку в Файлах") { choosingFolder = true }
                        .disabled(password.count < 10 || password != confirmation || busy || model.recoveryRequired)
                } header: { Text("Настроить один раз") }
                footer: {
                    Text("Выбери отдельную папку в iCloud Drive или другом доступном провайдере. Сохрани пароль отдельно от iPhone: после потери устройства он нужен для восстановления. Приложение хранит пароль в Связке ключей этого устройства; восстановить забытый пароль нельзя.")
                }
            }

            Section {
                Button("Открыть защищённую копию", systemImage: "lock.doc") { clearRestore(); choosingFile = true }
                    .disabled(busy || service.isWorking)
                if restoreData != nil {
                    SecureField("Пароль этой копии", text: $restorePassword)
                        .textContentType(.password).autocorrectionDisabled()
                    Button("Проверить перед восстановлением") { inspectRestore() }
                        .disabled(restorePassword.isEmpty || busy)
                    Button("Отменить выбор файла", role: .cancel) { clearRestore() }.disabled(busy)
                }
                if let candidate {
                    Text("Проверено: \(candidate.state.transactions.count) операций, \(candidate.state.accounts.count) счетов. Обозначение валюты в файле: \(candidate.state.settings.currency).")
                        .font(LumoType.body)
                    if candidate.state.settings.currency != "BYN" {
                        Picker("В какой валюте вводились суммы?", selection: $actualCurrency) {
                            Text("Выбери фактическую валюту").tag("")
                            Text("Белорусские рубли · BYN").tag("BYN")
                            Text("Доллары · USD").tag("USD")
                            Text("Российские рубли · RUB").tag("RUB")
                        }
                        Text("Старый переключатель мог менять только обозначение. Укажи единицы, в которых действительно вводились числа; приложение не будет угадывать их по подписи файла.")
                            .font(LumoType.caption).foregroundStyle(.secondary)
                    }
                    Button("Восстановить этот журнал", role: .destructive) { confirmingRestore = true }
                        .disabled(actualCurrency.isEmpty || busy || service.isWorking)
                }
                if busy { ProgressView("Проверяем файл…") }
                if let message { Text(message).font(LumoType.caption).foregroundStyle(.secondary) }
            } header: { Text("Восстановление") }
            footer: { Text("Открой текущий или предыдущий файл .lumobackup. Проверка пароля и целостности выполняется до замены журнала. Существующие внешние копии при отключении не удаляются.") }
        }
        .navigationTitle("Копия и восстановление").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosingFolder) {
            BackupFolderPicker { url in
                choosingFolder = false
                guard let url else { return }
                Task {
                    busy = true; message = nil
                    defer { busy = false }
                    do {
                        try await service.configure(folder: url, password: password, initialJSON: model.exportText())
                        password = ""; confirmation = ""
                        // Capture any local commit which occurred during folder authorization.
                        service.record(try model.exportText())
                    } catch { message = error.localizedDescription }
                }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
            Task {
                busy = true; message = nil
                defer { busy = false }
                do { restoreData = try await Self.readFile(result.get()); restorePassword = "" }
                catch { message = error.localizedDescription }
            }
        }
        .confirmationDialog("Отключить автоматическую копию?", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("Отключить", role: .destructive) { service.disconnect() }
        } message: { Text("Копии в папке останутся. Новые изменения не будут автоматически копироваться за пределы приложения.") }
        .alert("Восстановить данные из копии?", isPresented: $confirmingRestore) {
            Button("Отмена", role: .cancel) { candidateJSON = nil; candidate = nil }
            Button("Восстановить", role: .destructive) {
                guard let json = candidateJSON else { return }
                if let onRestore { onRestore(json, actualCurrency) }
                else if model.importText(json, actualCurrency: actualCurrency) {
                    message = "Данные восстановлены."
                    if let current = try? model.exportText() { service.record(current) }
                } else { message = model.error; model.error = nil }
                clearRestore()
            }
        } message: {
            Text("В копии \(candidate?.state.transactions.count ?? 0) операций и \(candidate?.state.accounts.count ?? 0) счетов. Фактическая валюта сумм: \(actualCurrency). Текущий журнал будет заменён после подтверждения. Предыдущие локальные данные сохранятся резервной копией.")
        }
    }

    private func inspectRestore() {
        guard let data = restoreData else { return }
        let enteredPassword = restorePassword
        Task {
            busy = true; message = nil
            defer { busy = false }
            do {
                let json = try await Task.detached(priority: .userInitiated) {
                    try ProtectedBackup.decrypt(data, password: enteredPassword)
                }.value
                candidate = try model.inspectImport(json)
                candidateJSON = json
                actualCurrency = candidate?.state.settings.currency == "BYN" ? "BYN" : ""
            } catch { message = error.localizedDescription }
        }
    }

    private func clearRestore() {
        restoreData = nil; restorePassword = ""; candidateJSON = nil; candidate = nil; actualCurrency = ""
    }

    private static func readFile(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            var coordinatorError: NSError?
            var result: Result<Data, Error> = .failure(BackupServiceError.message("Не удалось прочитать копию."))
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                result = Result {
                    let size = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= ProtectedBackup.maximumFileSizeBytes else { throw ProtectedBackup.Error.fileTooLarge }
                    return try Data(contentsOf: coordinatedURL)
                }
            }
            if let coordinatorError { throw coordinatorError }
            return try result.get()
        }.value
    }
}

private struct BackupFolderPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
