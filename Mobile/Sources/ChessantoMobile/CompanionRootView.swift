import CompanionCloudKit
import SwiftUI

struct CompanionRootView: View {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                ReportsView()
            }
            .tabItem {
                Label("Reports", systemImage: "doc.text.magnifyingglass")
            }

            NavigationStack {
                GamesView()
            }
            .tabItem {
                Label("Games", systemImage: "checkerboard.rectangle")
            }

            NavigationStack {
                MacConnectionView()
            }
            .tabItem {
                Label("Mac", systemImage: "laptopcomputer.and.iphone")
            }
        }
        .companionBackground()
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                try? await model.synchronize(reason: .foreground)
            }
        }
    }
}
