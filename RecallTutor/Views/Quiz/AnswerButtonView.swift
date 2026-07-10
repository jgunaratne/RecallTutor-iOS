import SwiftUI

/// One A/B/C/D answer row — port of components/AnswerButton.tsx.
struct AnswerButtonView: View {
    enum RevealState {
        case idle            // question phase, tappable
        case revealedCorrect // the right answer, highlighted green
        case revealedWrong   // the student's wrong pick, highlighted red
        case revealedDimmed  // other options, faded out
    }

    let text: String
    let index: Int
    let state: RevealState
    let action: () -> Void

    private static let labels = ["A", "B", "C", "D"]

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(Self.labels[min(index, 3)])
                    .font(.appBody(size: 17, weight: .medium))
                    .foregroundStyle(chipText)
                    .frame(width: 28, height: 28)
                    .background(chipFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(text)
                    .font(.appBody(size: 17, weight: state == .revealedCorrect || state == .revealedWrong ? .medium : .regular))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .modifier(AnswerSurface(state: state))
        }
        .disabled(state != .idle)
    }

    /// Idle answers float as interactive glass; revealed states keep the
    /// solid semantic fills so correct/wrong reads instantly.
    private struct AnswerSurface: ViewModifier {
        let state: RevealState

        func body(content: Content) -> some View {
            if state == .idle {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            } else {
                content
                    .background(fill)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(border, lineWidth: state == .revealedDimmed ? 0.5 : 1)
                    )
            }
        }

        private var fill: Color {
            switch state {
            case .idle: Theme.surface
            case .revealedCorrect: Theme.correctFill
            case .revealedWrong: Theme.wrongFill
            case .revealedDimmed: Theme.stateHover
            }
        }

        private var border: Color {
            switch state {
            case .idle: Theme.borderSubtle
            case .revealedCorrect: Theme.correctBorder
            case .revealedWrong: Theme.wrongBorder
            case .revealedDimmed: Theme.borderSoft
            }
        }
    }

    private var textColor: Color {
        switch state {
        case .idle: Theme.textPrimary
        case .revealedCorrect: Theme.correctText
        case .revealedWrong: Theme.wrongText
        case .revealedDimmed: Theme.textPrimary.opacity(0.35)
        }
    }

    private var chipFill: Color {
        switch state {
        case .idle, .revealedDimmed: Theme.statePill
        case .revealedCorrect: Theme.correctBorder
        case .revealedWrong: Theme.wrongBorder
        }
    }

    private var chipText: Color {
        switch state {
        case .idle: Theme.textSecondary
        case .revealedCorrect, .revealedWrong: .white
        case .revealedDimmed: Theme.textTertiary.opacity(0.5)
        }
    }
}
