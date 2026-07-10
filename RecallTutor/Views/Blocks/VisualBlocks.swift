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
                    .frame(height: 190)
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

    @ViewBuilder
    private func chart(_ spec: ChartSpec) -> some View {
        let points = Array(spec.data.enumerated())
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
            }
            .chartForegroundStyleScale(range: chartPalette)
            .chartLegend(position: .bottom, spacing: 8)
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
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.appBody(size: 13)) } }
        default: // bar
            Chart(points, id: \.offset) { index, point in
                BarMark(
                    x: .value(spec.xLabel ?? "X", point.label),
                    y: .value(spec.yLabel ?? "Y", point.value)
                )
                .foregroundStyle(chartPalette[index % chartPalette.count])
                .cornerRadius(3)
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.appBody(size: 13)) } }
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
                        Text("\(index + 1)")
                            .font(.appBody(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.accent))
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
                            .foregroundStyle(Theme.accent)
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

