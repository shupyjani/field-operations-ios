import Foundation

/// Where the assistant endpoint lives.
///
/// Configuration only. No credential belongs here or anywhere else in the app:
/// the provider key is held by the server that fronts the model, and this app
/// only ever sees that endpoint's small JSON reply.
nonisolated struct AssistantEndpoint: Hashable, Sendable {
    let url: URL
    var timeout: TimeInterval = 12

    /// The Info.plist key holding the endpoint. Configuration, so it is set
    /// alongside the other bundle values rather than written into this file.
    static let infoKey = "AjaniAssistantEndpoint"

    /// Passed by an automated run to keep the app on built-in guidance, so a
    /// test never makes a real provider request.
    static let offlineArgument = "ajani-assistant-offline"

    /// The endpoint this build should use, or `nil` when none is configured.
    ///
    /// Read from the bundle rather than compiled in, so a build without the key
    /// set simply runs on built-in guidance.
    static func configured(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AssistantEndpoint? {
        guard !arguments.contains(offlineArgument),
              let value = bundle.object(forInfoDictionaryKey: infoKey) as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" else {
            return nil
        }
        return AssistantEndpoint(url: url)
    }
}

/// The assistant endpoint, spoken to over HTTPS.
///
/// Mirrors the browser's contract exactly: a POST carrying the question, a capped
/// slice of the conversation and the round snapshot, answered with `{ reply }` on
/// success or `{ fallback: true }` on anything else. Every failure — unconfigured,
/// unreachable, slow, refused, malformed — returns `nil` so the deterministic
/// answer is used instead.
nonisolated struct RemoteAssistantProvider: AssistantProviding {
    let endpoint: AssistantEndpoint
    let session: URLSession

    /// How much of the conversation is sent. The endpoint accepts more; this is
    /// what the browser sends.
    static let historySent = 6

    init(endpoint: AssistantEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private struct RequestBody: Encodable {
        let message: String
        let history: [AssistantHistoryEntry]
        let snapshot: AssistantSnapshot
    }

    private struct ResponseBody: Decodable {
        let reply: String?
        let fallback: Bool?
    }

    func reply(
        to question: String,
        history: [AssistantHistoryEntry],
        snapshot: AssistantSnapshot
    ) async -> String? {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = endpoint.timeout

        let body = RequestBody(
            message: String(question.prefix(AssistantCopy.messageLimit)),
            history: history.suffix(Self.historySent).map {
                AssistantHistoryEntry(role: $0.role, text: String($0.text.prefix(AssistantCopy.messageLimit)))
            },
            snapshot: snapshot
        )

        guard let encoded = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = encoded

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
                return nil
            }

            if decoded.fallback == true { return nil }

            let text = decoded.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        } catch {
            // Cancellation, timeout, transport failure and malformed data are all
            // the same to the caller: the built-in answer stands.
            return nil
        }
    }
}
