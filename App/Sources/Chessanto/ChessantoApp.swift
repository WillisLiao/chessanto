import SwiftUI

@main
struct ChessantoApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import PGN…") {
                    NotificationCenter.default.post(name: .importPGNRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let importPGNRequested = Notification.Name("importPGNRequested")
}
