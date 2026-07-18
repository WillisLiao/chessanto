import CoachKit
import Persistence
import SwiftUI

/// The Coach settings pane (`Settings` scene): wraps `CoachSetupView` (also
/// used by onboarding) and persists every change immediately, same pattern
/// as `GeneralSettingsView`.
struct CoachSettingsView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var coachService: CoachService

    @State private var coachEnabled = false
    @State private var ratingBand = "adaptive"
    @State private var coachModel = ""

    var body: some View {
        ScrollView {
            CoachSetupView(coachEnabled: $coachEnabled, ratingBand: $ratingBand, coachModel: $coachModel)
                .padding()
        }
        .background(DesignColors.surface0)
        .frame(minWidth: 460, minHeight: 360)
        .onAppear { load() }
        .onChange(of: coachEnabled) { _, newValue in save(coachEnabled: newValue) }
        .onChange(of: ratingBand) { _, newValue in save(ratingBand: newValue) }
        .onChange(of: coachModel) { _, newValue in save(coachModel: newValue) }
    }

    private func load() {
        guard let profile = try? library.store.userProfile() else { return }
        coachEnabled = profile.coachEnabled
        ratingBand = profile.ratingBand
        coachModel = profile.coachModel ?? ""
    }

    private func save(coachEnabled newValue: Bool) {
        updateProfile { $0.coachEnabled = newValue }
    }

    private func save(ratingBand newValue: String) {
        updateProfile { $0.ratingBand = newValue }
    }

    private func save(coachModel newValue: String) {
        updateProfile { $0.coachModel = newValue.isEmpty ? nil : newValue }
    }

    private func updateProfile(_ mutate: (inout UserProfileRecord) -> Void) {
        guard var profile = try? library.store.userProfile() else { return }
        mutate(&profile)
        _ = try? library.store.saveUserProfile(profile)
    }
}
