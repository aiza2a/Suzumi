import SwiftUI

/// 液态光斑形状（从 GlassKit `MorphingBlob` 原样移植）。
///
/// 参数化 superellipse：圆周上均匀分布 `points` 个点，半径由 `phase` 驱动的
/// 三段正弦叠加扰动构成；路径用相邻点中点 + 二次贝塞尔生成平滑闭合曲线。
/// 不是物理准确，但作为模糊背景光斑读感自然。
struct MorphingBlob: Shape {
    var phase: Double
    var amplitude: Double = 0.10
    var points: Int = 12

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) * 0.42
        let n = max(6, points)

        var radii: [CGFloat] = []
        radii.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n) * (2 * Double.pi)
            let wobble =
                sin(phase + t * 1.0) * 0.55 +
                sin(phase * 0.7 + t * 2.0) * 0.30 +
                sin(phase * 1.3 + t * 3.0) * 0.15
            let r = base * (1 + CGFloat(amplitude * wobble))
            radii.append(r)
        }

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let angle = Double(i) / Double(n) * (2 * Double.pi)
            let r = radii[i]
            pts.append(
                CGPoint(
                    x: center.x + r * CGFloat(Darwin.cos(angle)),
                    y: center.y + r * CGFloat(Darwin.sin(angle))
                )
            )
        }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        }

        var path = Path()
        guard let first = pts.first else { return path }

        path.move(to: mid(first, pts[1 % n]))
        for i in 1..<n + 1 {
            let p0 = pts[(i - 1 + n) % n]
            let p1 = pts[i % n]
            let m = mid(p0, p1)
            path.addQuadCurve(to: m, control: p0)
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    MorphingBlob(phase: 1.2)
        .fill(
            .linearGradient(
                colors: [.brand600, .brand300],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: 240, height: 240)
}