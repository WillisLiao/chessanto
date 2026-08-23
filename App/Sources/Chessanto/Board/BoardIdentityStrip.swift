import SwiftUI

/// One side's identity, resolved to a screen position (top/bottom) rather
/// than a color, so a strip's content survives a board flip (DD5).
struct BoardIdentityStripInfo: Equatable {
    let name: String
    let rating: Int?
    let isUser: Bool
}

enum AccuracySummaryFormatter {
    /// Formats side name, accuracy percentage, and user marker.
    /// Example: "White (You) 93.8%" or "Black 90.8%"
    static func format(side: String, accuracy: Double, isUser: Bool) -> String {
        let percent = String(format: "%.1f%%", accuracy)
        if isUser {
            return "\(side) (You) \(percent)"
        }
        return "\(side) \(percent)"
    }
}

enum BoardIdentityStrip {
    static func isUser(name: String, username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && name.caseInsensitiveCompare(trimmed) == .orderedSame
    }

    /// Decides what the top and bottom strips say, given both players and
    /// which side is drawn at the bottom of the board right now.
    ///
    /// `flipped` mirrors `BoardView`'s own orientation rule: not flipped
    /// draws White at the bottom, flipped draws Black at the bottom - so the
    /// strips must swap with it rather than track color.
    static func strips(
        whiteName: String,
        blackName: String,
        whiteRating: Int?,
        blackRating: Int?,
        flipped: Bool,
        username: String
    ) -> (top: BoardIdentityStripInfo, bottom: BoardIdentityStripInfo) {
        let white = BoardIdentityStripInfo(name: whiteName, rating: whiteRating, isUser: isUser(name: whiteName, username: username))
        let black = BoardIdentityStripInfo(name: blackName, rating: blackRating, isUser: isUser(name: blackName, username: username))
        return flipped ? (top: white, bottom: black) : (top: black, bottom: white)
    }
}

struct BoardIdentityStripView: View {
    let info: BoardIdentityStripInfo

    var body: some View {
        HStack(spacing: DesignSpacing.xs) {
            Text(info.name)
                .font(.dsSecondary.weight(info.isUser ? .semibold : .regular))
                .foregroundStyle(info.isUser ? DesignColors.textPrimary : DesignColors.textSecondary)
            if let rating = info.rating {
                Text("(\(rating))")
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            if info.isUser {
                Text("· You")
                    .font(.dsSecondary.weight(.semibold))
                    .foregroundStyle(DesignColors.accentText)
            }
        }
    }
}
