import Foundation
import JavaScriptCore

public enum FinanceError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

/// One instance per thread. The app owns this engine on MainActor.
public final class FinanceEngine {
    private let context: JSContext
    private let bridge: JSValue

    public init() throws {
        guard let context = JSContext(),
              let url = Bundle.module.url(forResource: "finance-engine", withExtension: "js") else {
            throw FinanceError.message("Не удалось загрузить финансовое ядро")
        }
        let script = try String(contentsOf: url, encoding: .utf8)
        context.evaluateScript(script, withSourceURL: url)
        if let exception = context.exception { throw FinanceError.message(exception.toString() ?? "Ошибка ядра") }
        guard let bridge = context.objectForKeyedSubscript("LumoBridge"), !bridge.isUndefined else {
            throw FinanceError.message("Финансовое ядро не запустилось")
        }
        self.context = context
        self.bridge = bridge
    }

    private func response(_ operation: String, _ payload: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        context.exception = nil
        guard let result = bridge.invokeMethod("request", withArguments: [operation, text])?.toString(),
              let resultData = result.data(using: .utf8) else {
            throw FinanceError.message("Нет ответа от финансового ядра")
        }
        let object = try JSONSerialization.jsonObject(with: resultData) as? [String: Any]
        guard object?["ok"] as? Bool == true else {
            throw FinanceError.message(object?["error"] as? String ?? "Ошибка операции")
        }
        return resultData
    }

    private struct Response<T: Decodable>: Decodable { let value: T }

    public func value<T: Decodable>(_ operation: String, _ payload: [String: Any] = [:], as: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(Response<T>.self, from: response(operation, payload)).value
    }

    public func perform(_ operation: String, args: [Any] = []) throws {
        _ = try response(operation, ["args": args])
    }

    public func snapshot(month: String? = nil) throws -> Snapshot {
        try value("snapshot", month.map { ["month": $0] } ?? [:])
    }

    public func exportJSON() throws -> String { try value("export") }
    public func importJSON(_ text: String) throws { _ = try response("import", ["text": text]) }
    public func cents(_ text: String) throws -> Int { try value("parseAmount", ["text": text]) }
    public func preview() throws -> RebalancePreview { try value("previewRebalance") }
}
