import SwiftUI

struct LinePreviewControlsView: View {
    @Environment(\.moveNotation) private var moveNotation
    @ObservedObject var controller: LinePreviewController
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: DesignSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.label)
                        .font(.dsBody.weight(.semibold))
                        .foregroundStyle(DesignColors.textPrimary)
                    Text(stepDescription)
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                Spacer()
                Button("Done") {
                    controller.pause()
                    onDone()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: DesignSpacing.sm) {
                HStack(spacing: 1) {
                    iconButton("backward.end.fill", label: "Jump to line start") {
                        controller.jumpToStart()
                    }
                    .disabled(!controller.canStepBackward)

                    iconButton("chevron.left", label: "Previous line move") {
                        controller.stepBackward()
                    }
                    .disabled(!controller.canStepBackward)

                    if controller.isPlaying {
                        iconButton("pause.fill", label: "Pause line playback") {
                            controller.pause()
                        }
                    } else if controller.canStepForward {
                        iconButton("play.fill", label: "Play line automatically") {
                            controller.play()
                        }
                    } else {
                        iconButton("arrow.counterclockwise", label: "Replay line") {
                            controller.replay()
                        }
                    }

                    iconButton("chevron.right", label: "Next line move") {
                        controller.stepForward()
                    }
                    .disabled(!controller.canStepForward)

                    iconButton("forward.end.fill", label: "Jump to line end") {
                        controller.jumpToEnd()
                    }
                    .disabled(!controller.canStepForward)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, DesignSpacing.xs)
                .background(DesignColors.surface1)

                Spacer()

                Text("\(controller.stepIndex + 1) / \(controller.stepCount)")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.bottom, DesignSpacing.sm)
        .task(id: controller.isPlaying) {
            while controller.isPlaying {
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                controller.autoplayTick()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(controller.label), \(stepAccessibilityDescription)"
        )
    }

    private var stepDescription: String {
        if controller.stepIndex == 0 {
            return "Starting position"
        }
        return controller.current.san.map {
            "Move \(controller.stepIndex): \(moveNotation.move($0).visual)"
        }
            ?? "Move \(controller.stepIndex)"
    }

    private var stepAccessibilityDescription: String {
        if controller.stepIndex == 0 {
            return "Starting position"
        }
        return controller.current.san.map {
            "Move \(controller.stepIndex): \(moveNotation.move($0).spoken)"
        }
            ?? "Move \(controller.stepIndex)"
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(minWidth: 32, minHeight: 28)
        }
        .accessibilityLabel(label)
    }
}
