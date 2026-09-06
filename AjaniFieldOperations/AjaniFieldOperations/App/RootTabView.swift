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
    }
}

#Preview {
    RootTabView()
        .environment(FieldOperationsStore())
}
