import SwiftUI

public struct Sparkline: View {
    public var values: [Double]
    public var color: Color
    public var maxValue: Double? = nil
    public var fillOpacity: Double = 0.16
    public var lineWidth: CGFloat = 1.5
    public var showsZeroBaseline = false

    public init(
        values: [Double],
        color: Color,
        maxValue: Double? = nil,
        fillOpacity: Double = 0.16,
        lineWidth: CGFloat = 1.5,
        showsZeroBaseline: Bool = false
    ) {
        self.values = values
        self.color = color
        self.maxValue = maxValue
        self.fillOpacity = fillOpacity
        self.lineWidth = lineWidth
        self.showsZeroBaseline = showsZeroBaseline
    }

    public var body: some View {
        GeometryReader { geometry in
            let halfLine = lineWidth / 2
            let baselineY = max(halfLine, geometry.size.height - halfLine)
            let pts = Self.calculatePoints(
                values: values,
                size: geometry.size,
                baselineY: baselineY,
                maxValue: maxValue,
                lineWidth: lineWidth
            )
            if pts.count >= 2 {
                ZStack {
                    if fillOpacity > 0 {
                        Path { path in
                            path.move(to: CGPoint(x: pts[0].x, y: baselineY))
                            pts.forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: baselineY))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(fillOpacity), color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }

                    Path { path in
                        path.move(to: pts[0])
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    public static func calculatePoints(
        values: [Double],
        size: CGSize,
        baselineY: CGFloat? = nil,
        maxValue: Double? = nil,
        lineWidth: CGFloat = 1.0
    ) -> [CGPoint] {
        guard size.width > 0, size.height > 0, values.count >= 2 else { return [] }
        let cleanValues = values.map { $0.isFinite ? max(0.0, $0) : 0.0 }
        let safeMaxValue = (maxValue?.isFinite == true) ? maxValue : nil
        let peak = max(safeMaxValue ?? (cleanValues.max() ?? 1.0), 0.0001)
        let halfLine = lineWidth / 2
        let topY: CGFloat = halfLine
        let effectiveBaselineY = baselineY ?? max(halfLine, size.height - halfLine)
        let plotHeight = max(1.0, effectiveBaselineY - topY)
        let lastIndex = cleanValues.count - 1
        return cleanValues.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1.0, max(0.0, value / peak))
            let y = effectiveBaselineY - plotHeight * CGFloat(normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
