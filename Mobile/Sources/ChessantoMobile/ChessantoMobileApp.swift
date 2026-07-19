import SwiftUI

@main
struct ChessantoMobileApp: App {
    @StateObject private var model = MobileAppModel()

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .task {
                    await model.start()
                }
        }
    }
}
