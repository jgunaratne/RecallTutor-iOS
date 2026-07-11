import SwiftUI

/// Empty-state home screen: greeting, topic chips, and the input card.
struct HomeView: View {
    @Environment(ChatModel.self) private var model
    @Binding var input: String
    var inputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 28)

                    VStack(spacing: 24) {
                        Text("Select a topic to learn more about it.")
                            .font(.appBody(size: 17))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        sectionDivider("Education")
                        topicGrid(model.visibleTopics, onLoadMore: { model.loadMoreTopics() })

                        sectionDivider("Jobs & Careers")
                        topicGrid(model.visibleProTopics, onLoadMore: { model.loadMoreProTopics() })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tap anywhere outside the input card to unfocus and close the
            // keyboard (buttons/chips still take precedence over this tap).
            .onTapGesture {
                inputFocused.wrappedValue = false
            }

            // Input pinned to the bottom of the home screen. Errors present
            // as an alert from ChatView, so nothing shifts the layout here.
            InputBar(input: $input, isStreaming: model.isStreaming, focused: inputFocused, onSend: onSend)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    private func sectionDivider(_ label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.borderSoft).frame(height: 1)
            Text(label)
                .font(.appBody(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Rectangle().fill(Theme.borderSoft).frame(height: 1)
        }
    }

    private func topicGrid(_ topics: [Topic], onLoadMore: @escaping () -> Void) -> some View {
        let status = model.topicStatus
        return GlassEffectContainer(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(topics, id: \.prompt) { topic in
                    TopicChip(topic: topic, status: status[topic.prompt]) {
                        model.sendMessage(topic.prompt)
                    }
                }
                Button(action: onLoadMore) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                        Text("More")
                            .font(.appBody(size: 17))
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive())
                }
            }
        }
    }
}

struct TopicChip: View {
    let topic: Topic
    let status: TopicStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if status == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.correctBorder)
                } else if status == .partial {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.amberBar)
                }
                Text(topic.label)
                    .font(.appBody(size: 17))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive())
        }
    }
}

/// Simple flow layout that wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
