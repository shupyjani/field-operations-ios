import SwiftUI

@main
struct AjaniFieldOperationsApp: App {
    @State private var store = FieldOperationsStore()
    /// The provider is used only when this build carries an endpoint. Without
    /// one the assistant answers from its built-in guidance, which is the
    /// ordinary case rather than a degraded one.
    @State private var conversation = AssistantConversation(
        provider: AssistantEndpoint.configured().map { RemoteAssistantProvider(endpoint: $0) }
    )

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(conversation)
        }
    }
}
