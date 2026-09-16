import Foundation
import Testing
@testable import AjaniFieldOperations

/// Answers requests in-process, so the transport is exercised without a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Outcome: Sendable {
        var status: Int = 200
        var body: Data = Data()
        var error: Error?
        var delay: Double = 0
    }

    nonisolated(unsafe) static var outcome = Outcome()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset() {
        outcome = Outcome()
        requests = []
        bodies = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        // A body set through URLSession arrives on the stream, not on httpBody.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            Self.bodies.append(data)
        } else if let body = request.httpBody {
            Self.bodies.append(body)
        }

        let outcome = Self.outcome

        if outcome.delay > 0 {
            Thread.sleep(forTimeInterval: outcome.delay)
        }

        if let error = outcome.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: outcome.status,
            httpVersion: nil,
            headerFields: ["content-type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: outcome.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("The remote assistant provider", .serialized)
struct RemoteAssistantProviderTests {
    private func provider(timeout: TimeInterval = 12) -> RemoteAssistantProvider {
        RemoteAssistantProvider(
            endpoint: AssistantEndpoint(
                url: URL(string: "https://example.invalid/.netlify/functions/ajani-assistant")!,
                timeout: timeout
            ),
            session: StubURLProtocol.session()
        )
    }

    private func ask(_ provider: RemoteAssistantProvider) async -> String? {
        await provider.reply(
            to: "Who is my next visit?",
            history: [AssistantHistoryEntry(role: "user", text: "Hello")],
            snapshot: AssistantSnapshot(round: AssistantFixtures.round())
        )
    }

    @Test("A successful reply is returned")
    func returnsReply() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"Priya Raman is next.","source":"live"}"#.data(using: .utf8)!

        #expect(await ask(provider()) == "Priya Raman is next.")
    }

    @Test("A fallback reply is treated as no answer")
    func treatsFallbackAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"fallback":true}"#.data(using: .utf8)!

        #expect(await ask(provider()) == nil)
    }

    @Test("An empty reply is treated as no answer")
    func treatsEmptyReplyAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"   "}"#.data(using: .utf8)!

        #expect(await ask(provider()) == nil)
    }

    @Test("A non-success status is treated as no answer")
    func treatsErrorStatusAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.status = 500
        StubURLProtocol.outcome.body = #"{"reply":"should be ignored"}"#.data(using: .utf8)!

        #expect(await ask(provider()) == nil)
    }

    @Test("Malformed data is treated as no answer rather than crashing")
    func treatsMalformedDataAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = Data("not json at all".utf8)

        #expect(await ask(provider()) == nil)
    }

    @Test("A transport failure is treated as no answer")
    func treatsFailureAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.error = URLError(.notConnectedToInternet)

        #expect(await ask(provider()) == nil)
    }

    @Test("A timeout is treated as no answer")
    func treatsTimeoutAsNoAnswer() async {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.error = URLError(.timedOut)

        #expect(await ask(provider(timeout: 0.5)) == nil)
    }

    @Test("The request carries the contract the endpoint expects")
    func sendsTheAgreedContract() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        _ = await ask(provider())

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Exactly the three keys the endpoint reads, and nothing beside them.
        #expect(json.keys.sorted() == ["history", "message", "snapshot"])
        #expect(json["message"] as? String == "Who is my next visit?")

        let history = try #require(json["history"] as? [[String: Any]])
        #expect(history.count == 1)
        // The endpoint accepts these two roles and rejects the request otherwise.
        #expect(history.allSatisfy { ["user", "assistant"].contains($0["role"] as? String) })

        let snapshot = try #require(json["snapshot"] as? [String: Any])
        let visits = try #require(snapshot["visits"] as? [[String: Any]])
        #expect(visits.count == 7)
        #expect(snapshot["summary"] as? String == "2 of 7 visits complete · 5 remaining")

        // What the endpoint validates a snapshot on, before it will pass it to
        // a provider at all.
        #expect(visits.count <= 40)
        for visit in visits {
            let name = try #require(visit["name"] as? String)
            #expect(name.count <= 80)
            #expect(visit["status"] is String)
        }
        // The statuses are the contract's spelling, not the Swift case names.
        #expect(
            Set(visits.compactMap { $0["status"] as? String })
                .isSubset(of: ["planned", "en-route", "arrived", "completed", "cancelled"])
        )
    }

    @Test("Nothing beyond the round is sent")
    func sendsNothingBeyondTheRound() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        _ = await ask(provider())

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let snapshot = try #require(json["snapshot"] as? [String: Any])

        // Preferences and navigation never leave the device.
        #expect(snapshot.keys.sorted() == ["completionOrder", "summary", "visits"])

        let text = try #require(String(data: body, encoding: .utf8))
        #expect(!text.contains("showsCompletedVisitsOnToday"))
        #expect(!text.contains("confirmsVisitCompletion"))
    }

    @Test("A resolved selection travels as the endpoint expects it")
    func sendsSelectionContext() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        let round = AssistantFixtures.round()
        let visit = AssistantFixtures.visit("AJ-1042")
        let task = try #require(visit.tasks.first)

        _ = await provider().reply(
            to: "Which of those is not done?",
            history: [],
            snapshot: AssistantSnapshot(
                round: round,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    taskIDs: [task.id],
                    personID: visit.id
                )
            )
        )

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let snapshot = try #require(json["snapshot"] as? [String: Any])
        let context = try #require(snapshot["selectionContext"] as? [String: Any])

        // A person is a single-visit selection rather than a field of its own,
        // and a task travels paired with the visit it sits on.
        #expect(context["visitIds"] as? [String] == [visit.id.uuidString])
        #expect(context["taskIds"] as? [[String]] == [[visit.id.uuidString, task.id.uuidString]])
    }

    @Test("An empty selection is left out rather than sent hollow")
    func omitsEmptySelectionContext() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        _ = await provider().reply(
            to: "Who is next?",
            history: [],
            snapshot: AssistantSnapshot(round: AssistantFixtures.round(), selection: AssistantSelection())
        )

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let snapshot = try #require(json["snapshot"] as? [String: Any])
        #expect(snapshot["selectionContext"] == nil)
    }

    @Test("A long question and a long turn are cut to what the endpoint accepts")
    func capsLengthsToTheContract() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        _ = await provider().reply(
            to: String(repeating: "x", count: 900),
            history: [AssistantHistoryEntry(role: "assistant", text: String(repeating: "y", count: 900))],
            snapshot: AssistantSnapshot(round: AssistantFixtures.round())
        )

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Longer than this and the endpoint rejects the request outright.
        #expect((json["message"] as? String)?.count == 500)
        let history = try #require(json["history"] as? [[String: Any]])
        #expect((history.first?["text"] as? String)?.count == 500)
    }

    @Test("Only the agreed slice of the conversation is sent")
    func capsHistorySent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        let history = (0..<12).map { AssistantHistoryEntry(role: "user", text: "Question \($0)") }
        _ = await provider().reply(
            to: "Who is next?",
            history: history,
            snapshot: AssistantSnapshot(round: AssistantFixtures.round())
        )

        let body = try #require(StubURLProtocol.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sent = try #require(json["history"] as? [[String: Any]])

        #expect(sent.count == RemoteAssistantProvider.historySent)
        // The endpoint refuses more than ten turns; this sits inside that.
        #expect(sent.count <= 10)
        // The most recent turns, not the oldest.
        #expect(sent.last?["text"] as? String == "Question 11")
    }

    @Test("No credential is carried anywhere in the request")
    func carriesNoCredential() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.outcome.body = #"{"reply":"ok"}"#.data(using: .utf8)!

        _ = await ask(provider())

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "authorization") == nil)
        #expect(request.allHTTPHeaderFields?.keys.contains { $0.lowercased().contains("key") } != true)

        let body = try #require(StubURLProtocol.bodies.first)
        let text = try #require(String(data: body, encoding: .utf8)).lowercased()
        #expect(!text.contains("api_key"))
        #expect(!text.contains("bearer"))
        #expect(!text.contains("sk-"))
    }
}

@Suite("Endpoint configuration")
struct AssistantEndpointTests {
    private final class StubBundle: Bundle, @unchecked Sendable {
        var value: Any?
        override func object(forInfoDictionaryKey key: String) -> Any? {
            key == AssistantEndpoint.infoKey ? value : nil
        }
    }

    @Test("An unconfigured build has no endpoint, and runs on built-in guidance")
    func unconfiguredBuildHasNoEndpoint() {
        let bundle = StubBundle()
        bundle.value = nil

        #expect(AssistantEndpoint.configured(bundle: bundle) == nil)
    }

    @Test("A configured HTTPS endpoint is used")
    func acceptsHTTPSEndpoint() throws {
        let bundle = StubBundle()
        bundle.value = "https://example.test/.netlify/functions/ajani-assistant"

        let endpoint = try #require(AssistantEndpoint.configured(bundle: bundle))
        #expect(endpoint.url.absoluteString == "https://example.test/.netlify/functions/ajani-assistant")
        #expect(endpoint.timeout == 12)
    }

    @Test("A plaintext endpoint is refused")
    func refusesInsecureEndpoint() {
        let bundle = StubBundle()
        bundle.value = "http://example.test/assistant"

        #expect(AssistantEndpoint.configured(bundle: bundle) == nil)
    }

    @Test("A malformed endpoint value is refused")
    func refusesMalformedEndpoint() {
        let bundle = StubBundle()

        for value in ["", "   ", "not a url", "ftp://example.test/assistant"] {
            bundle.value = value
            #expect(AssistantEndpoint.configured(bundle: bundle) == nil)
        }

        bundle.value = 42
        #expect(AssistantEndpoint.configured(bundle: bundle) == nil)
    }

    @Test("This build carries the deployed endpoint as configuration")
    func shippedBuildCarriesTheDeployedEndpoint() throws {
        let endpoint = try #require(AssistantEndpoint.configured(bundle: .main))

        #expect(
            endpoint.url.absoluteString
                == "https://www.ajanihealthcare.com/.netlify/functions/ajani-assistant"
        )
        #expect(endpoint.timeout == 12)
    }

    @Test("The configured endpoint carries no credential of any kind")
    func configuredEndpointCarriesNoCredential() throws {
        let endpoint = try #require(AssistantEndpoint.configured(bundle: .main))
        let components = try #require(
            URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        )

        // A public function path and nothing else: no key, no token, no user.
        #expect(components.query == nil)
        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.fragment == nil)
    }

    @Test("An automated run is held to built-in guidance")
    func offlineArgumentSuppressesTheProvider() {
        let bundle = StubBundle()
        bundle.value = "https://example.test/.netlify/functions/ajani-assistant"

        #expect(
            AssistantEndpoint.configured(
                bundle: bundle,
                arguments: ["AjaniFieldOperations", AssistantEndpoint.offlineArgument]
            ) == nil
        )
        #expect(AssistantEndpoint.configured(bundle: bundle, arguments: []) != nil)
    }
}
