import SwiftUI
import AppKit

@main
struct ChessantoApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var engineService = EngineService()
    @StateObject private var coachService = CoachService()

    init() {
        // Chessanto is white-forward by design (user decision, 2026-07-18) -
        // it does not follow the system's dark mode setting. Pinning
        // NSApp's appearance keeps native chrome (sidebar, titlebar,
        // controls) in lockstep with the light-only DesignColors tokens.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(engineService)
                .environmentObject(coachService)
                .frame(
                    minWidth: 1040,
                    idealWidth: 1120,
                    minHeight: 680,
                    idealHeight: 720
                )
                .tint(DesignColors.accent)
                .preferredColorScheme(.light)
                .task {
                    await engineService.start()
                }
        }
        .commands {
            // Keep the default "New Window" item (`.newItem`'s own content) -
            // replacing it removed the app's only in-app path back to a
            // window after quitting with the last window closed (M8 fact
            // 11). Import PGN gets its own item alongside it instead.
            CommandGroup(after: .newItem) {
                Button("Import PGN…") {
                    NotificationCenter.default.post(name: .importPGNRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            TabView {
                GeneralSettingsView()
                    .environmentObject(library)
                    .tabItem { Label("General", systemImage: "gearshape") }

                CoachSettingsView()
                    .environmentObject(library)
                    .environmentObject(coachService)
                    .tabItem { Label("Coach", systemImage: "person.fill.questionmark") }
            }
        }
    }
}

extension Notification.Name {
    static let importPGNRequested = Notification.Name("importPGNRequested")
}
