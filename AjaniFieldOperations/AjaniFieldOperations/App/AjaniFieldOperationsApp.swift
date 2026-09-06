import SwiftUI

@main
struct AjaniFieldOperationsApp: App {
    @State private var store = FieldOperationsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
        }
    }
}
