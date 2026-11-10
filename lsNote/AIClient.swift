import Foundation
import Security

/// Streams AI action results from the Claude Messages API. There is no Swift SDK, so this is
/// plain HTTPS; see docs/adr/0005-ai-actions-via-the-claude-api.md.
enum AIClient {
    static let defaultModel = "claude-haiku-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2026-10-21"

    enum Failure: LocalizedError {
        case missingAPIKey
        case api(status: Int, message: String)
        case refused
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Anthropic API key is set. Add one in Settings → AI."
            case .api(let status, let message):
                switch status {
                case 401: return "The API key was rejected. Check it in Settings → AI."
                case 404: return "The model was not found. Check the model name in Settings → AI. (\(message))"
                case 429: return "Rate limited by the AI service. Try again in a moment."
                default: return "AI request failed (\(status)): \(message)"
                }
            case .refused:
                return "The model declined this request."
            case .stream(let message):
                return message
            }
        }
    }

    /// The key saved in Settings, or `ANTHROPIC_API_KEY` when the app was launched from a shell.
    static var apiKey: String? {
        if let saved = KeychainStore.read(), !saved.isEmpty { return saved }
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        return nil
    }

    /// Runs `instruction` against `text`, yielding the reply as it is generated. The stream ends
    /// with `truncated == true` in its final element only if the reply hit the output limit.
    static func run(instruction: String, text: String, model: String) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = apiKey else { throw Failure.missingAPIKey }
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    let body: [String: Any] = [
                        "model": model.isEmpty ? defaultModel : model,
                        "max_tokens": 64000,
                        "stream": true,
                        "system": AIPrompt.system,
                        "messages": [["role": "user",
                                      "content": AIPrompt.userMessage(instruction: instruction, text: text)]],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let message = object.flatMap(AIStreamEvent.errorMessage(in:))
                            ?? HTTPURLResponse.localizedString(forStatusCode: status)
                        throw Failure.api(status: status, message: message)
                    }

                    for try await line in bytes.lines {
                        switch AIStreamEvent.parse(line: line) {
                        case .text(let text):
                            continuation.yield(Chunk(text: text, truncated: false))
                        case .stop(let reason):
                            if reason == "refusal" { throw Failure.refused }
                            if reason == "max_tokens" { continuation.yield(Chunk(text: "", truncated: true)) }
                        case .error(let message):
                            throw Failure.stream(message)
                        case nil:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct Chunk {
        let text: String
        let truncated: Bool
    }
}

/// The Anthropic API key, kept in the login keychain rather than in UserDefaults.
enum KeychainStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.lsnote.ai",
        kSecAttrAccount as String: "anthropic-api-key",
    ]

    static func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `key`, or removes the stored key when it is empty. Returns false if the keychain refused.
    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return true }
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
