import SwiftUI
import AppKit

@main
struct ChessantoApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var engineService = EngineService()
    @StateObject private var coachService = CoachService()
    @StateObject private var companionManager = MacCompanionManager()

    init() {
        // Chessanto is white-forward by design (user decision, 2026-07-18) -
        // it does not follow the system's dark mode setting. Pinning
        // NSApp's appearance keeps native chrome (sidebar, titlebar,
        // controls) in lockstep with the light-only DesignColors tokens.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(engineService)
                .environmentObject(coachService)
                .environmentObject(companionManager)
                .environment(
                    \.moveNotation,
                    MoveNotationFormatter(style: library.moveNotationStyle)
                )
                .frame(
                    minWidth: 1200,
                    idealWidth: 1360,
                    minHeight: 680,
                    idealHeight: 720
                )
                .tint(DesignColors.accent)
                .preferredColorScheme(.light)
                .task {
                    await engineService.start()
                    await companionManager.start(
                        library: library,
                        engineService: engineService,
                        coachService: coachService
                    )
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

            CommandMenu("Game") {
                Button("Next Move") { post(.stepForwardRequested) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Move") { post(.stepBackwardRequested) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Next Key Moment") { post(.nextKeyMomentRequested) }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                Button("Previous Key Moment") { post(.previousKeyMomentRequested) }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                Divider()
                Button("Play or Pause Line") { post(.toggleLinePlaybackRequested) }
                    .keyboardShortcut(.space, modifiers: [.command])
                Button("Flip Board") { post(.flipBoardRequested) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Analyze Game") { post(.analyzeGameRequested) }
                    .keyboardShortcut("r", modifiers: [.command])
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

                CompanionSettingsView()
                    .environmentObject(companionManager)
                    .tabItem { Label("Companion", systemImage: "iphone") }
            }
        }
    }
}

extension Notification.Name {
    static let importPGNRequested = Notification.Name("importPGNRequested")
    /// Board and review commands, posted from the menu bar.
    ///
    /// The single-key shortcuts on the board only fire while the board has
    /// focus, which it loses the moment the sidebar is clicked. Menu items
    /// fire regardless of focus and are discoverable, so every board action
    /// has one - the key press is the shortcut, not the only way in.
    static let stepForwardRequested = Notification.Name("stepForwardRequested")
    static let stepBackwardRequested = Notification.Name("stepBackwardRequested")
    static let nextKeyMomentRequested = Notification.Name("nextKeyMomentRequested")
    static let previousKeyMomentRequested = Notification.Name("previousKeyMomentRequested")
    static let flipBoardRequested = Notification.Name("flipBoardRequested")
    static let analyzeGameRequested = Notification.Name("analyzeGameRequested")
    static let toggleLinePlaybackRequested = Notification.Name("toggleLinePlaybackRequested")
}
