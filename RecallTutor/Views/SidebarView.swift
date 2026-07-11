import SwiftUI

/// Slide-in sidebar: new chat, recents with quiz scores + mastery, settings.
struct SidebarView: View {
    @Environment(ChatModel.self) private var model
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recall Tutor")
                    .font(.serifDisplay(size: 17))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close menu")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Button {
                model.newChat()
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                    Text("New lecture")
                        .font(.appBody(size: 17, weight: .medium))
                }
                .foregroundStyle(Theme.accentGradient)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.stateHover)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            if model.conversations.isEmpty {
                Text("No conversations yet")
                    .font(.appBody(size: 17))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                Spacer()
            } else {
                Text("Recents")
                    .font(.appBody(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.conversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isActive: conversation.id == model.activeId,
                                onSelect: {
                                    model.selectConversation(conversation)
                                    onClose()
                                },
                                onDelete: { model.deleteConversation(conversation.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()

            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22))
                    Spacer()
                    Text("Reading level: \(model.readingLevel.label)")
                        .font(.appBody(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .accessibilityLabel("Settings")
        }
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var mastery: TopicMastery { Mastery.compute(for: conversation) }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.appBody(size: 17))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    let m = mastery
                    Text(m.level.label)
                        .font(.appBody(size: 13, weight: .semibold))
                        .foregroundStyle(m.level.textColor)
                    if let last = conversation.quizzes.last {
                        Text("· \(last.score)/\(last.total)")
                            .font(.appBody(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isActive ? Theme.stateHover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
