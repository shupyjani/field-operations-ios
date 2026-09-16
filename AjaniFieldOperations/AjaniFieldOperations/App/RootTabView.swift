import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") {
                TodayView()
            }
            Tab("Visits", systemImage: "list.bullet.rectangle") {
                VisitsView()
            }
            Tab("More", systemImage: "ellipsis.circle") {
                MoreView()
            }
        }
        .tint(AjaniTheme.Palette.primary)
        // Attached once, so a question raised on Today and the same question
        // raised inside a visit are presented by one owner rather than two.
        .visitWorkflowPrompts()
    }
}

#Preview {
    RootTabView()
        .environment(FieldOperationsStore())
}
