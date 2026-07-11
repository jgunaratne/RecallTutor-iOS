import Charts
import SwiftUI

// Native visualization blocks — the iOS equivalents of the web app's D3 and
// Mermaid blocks. The tutor emits fenced JSON specs (```chart / ```flow);
// these views render them with Swift Charts and a native step diagram.

// MARK: - Chart

struct ChartSpec: Decodable {
    struct Point: Decodable {
        var label: String
        var value: Double
    }

    var type: String
    var title: String?
    var xLabel: String?
    var yLabel: String?
    var data: [Point]
}

/// The web app's D3 color palette.
private let chartPalette: [Color] = [
    Color(red: 0.102, green: 0.212, blue: 0.365),  // #1A365D
    Color(red: 0.184, green: 0.522, blue: 0.353),  // #2F855A
    Color(red: 0.773, green: 0.188, blue: 0.188),  // #C53030
    Color(red: 0.839, green: 0.620, blue: 0.180),  // #D69E2E
    Color(red: 0.396, green: 0.451, blue: 0.533),  // #657388
    Color(red: 0.169, green: 0.298, blue: 0.494),  // #2B4C7E
]

struct ChartBlockView: View {
    let json: String

    var body: some View {
        if let data = json.data(using: .utf8),
           let spec = try? JSONDecoder().decode(ChartSpec.self, from: data),
           !spec.data.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let title = spec.title {
                    Text(title)
                        .font(.appBody(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                chart(spec)
                    .frame(height: chartHeight(spec))
            }
            .padding(14)
            .background(Theme.page.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.borderSoft)
            )
        }
    }

    /// Category labels collide when there are many of them or they're long.
    /// Bars flip horizontal and line charts rotate their labels in that case.
    private func labelsAreCrowded(_ spec: ChartSpec) -> Bool {
        let longest = spec.data.map(\.label.count).max() ?? 0
        let total = spec.data.reduce(0) { $0 + $1.label.count }
        return spec.data.count > 6 || longest > 8 || total > 32
    }

    private func chartHeight(_ spec: ChartSpec) -> CGFloat {
        switch spec.type {
        case "pie":
            // Extra room so a bigger wrapped legend never covers the plot.
            return spec.data.count > 4 ? 230 : 190
        case "line":
            // Rotated x labels need extra vertical space below the plot.
            if labelsAreCrowded(spec) {
                let longest = spec.data.map(\.label.count).max() ?? 0
                return 190 + min(CGFloat(longest) * 5, 80)
            }
            return 190
        default: // bar
            // Horizontal bars grow with the row count.
            return labelsAreCrowded(spec)
                ? CGFloat(spec.data.count) * 34 + 30
                : 190
        }
    }

    @ViewBuilder
    private func chart(_ spec: ChartSpec) -> some View {
        let points = Array(spec.data.enumerated())
        let crowded = labelsAreCrowded(spec)
        switch spec.type {
        case "pie":
            Chart(points, id: \.offset) { _, point in
                SectorMark(
                    angle: .value(spec.yLabel ?? "Value", point.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Label", point.label))
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    Text(point.value.formatted())
                        .font(.appBody(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .chartForegroundStyleScale(range: chartPalette)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        case "line":
            Chart(points, id: \.offset) { _, point in
                LineMark(
                    x: .value(spec.xLabel ?? "X", point.label),
                    y: .value(spec.yLabel ?? "Y", point.value)
                )
                .foregroundStyle(chartPalette[0])
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(
                    x: .value(spec.xLabel ?? "X", point.label),
                    y: .value(spec.yLabel ?? "Y", point.value)
                )
                .foregroundStyle(chartPalette[0])
                .annotation(position: .top) {
                    Text(point.value.formatted())
                        .font(.appBody(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    // Rotate labels upright-vertical when they'd collide.
                    AxisValueLabel(orientation: crowded ? .verticalReversed : .horizontal)
                        .font(.appBody(size: 13))
                }
            }
        default: // bar
            if crowded {
                // Horizontal bars: every category label gets its own row at
                // full width, so long labels stay readable instead of colliding.
                Chart(points, id: \.offset) { index, point in
                    BarMark(
                        x: .value(spec.yLabel ?? "Value", point.value),
                        y: .value(spec.xLabel ?? "Label", point.label)
                    )
                    .foregroundStyle(chartPalette[index % chartPalette.count])
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        Text(point.value.formatted())
                            .font(.appBody(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis { AxisMarks { AxisValueLabel().font(.appBody(size: 13)) } }
            } else {
                Chart(points, id: \.offset) { index, point in
                    BarMark(
                        x: .value(spec.xLabel ?? "X", point.label),
                        y: .value(spec.yLabel ?? "Y", point.value)
                    )
                    .foregroundStyle(chartPalette[index % chartPalette.count])
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        Text(point.value.formatted())
                            .font(.appBody(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartXAxis { AxisMarks { AxisValueLabel().font(.appBody(size: 13)) } }
            }
        }
    }
}

// MARK: - Flow diagram

struct FlowSpec: Decodable {
    var title: String?
    var steps: [String]
}

struct FlowBlockView: View {
    let json: String

    var body: some View {
        if let data = json.data(using: .utf8),
           let spec = try? JSONDecoder().decode(FlowSpec.self, from: data),
           !spec.steps.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if let title = spec.title {
                    Text(title)
                        .font(.appBody(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.bottom, 10)
                }
                ForEach(Array(spec.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        // System font: the serif face's metrics sit digits
                        // visibly off-center inside the circle badge.
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.accentGradient))
                        Text(step)
                            .font(.appBody(size: 17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    if index < spec.steps.count - 1 {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 22)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.page.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.borderSoft)
            )
        }
    }
}

// MARK: - AI-generated card illustration (Nano Banana Flash Lite)

/// Displays a Gemini-generated illustration for a lecture card.
/// Shows a shimmer placeholder while the image is being generated,
/// then cross-fades to the rendered result.
struct CardIllustrationView: View {
    let image: UIImage?
    let isGenerating: Bool

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        if isGenerating {
            shimmerPlaceholder
        } else if let image {
            generatedImage(image)
        }
    }

    // MARK: - Shimmer loading state

    private var shimmerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.page)
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .overlay(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Theme.accent.opacity(0.06), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: shimmerPhase * geo.size.width)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent.opacity(0.5))
                    Text("Generating illustration…")
                        .font(.appBody(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderSoft, lineWidth: 0.5)
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerPhase = 1.2
                }
            }
    }

    // MARK: - Rendered image

    private func generatedImage(_ uiImage: UIImage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.borderSubtle, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("AI illustration")
                    .font(.appBody(size: 11))
            }
            .foregroundStyle(Theme.textTertiary.opacity(0.6))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

