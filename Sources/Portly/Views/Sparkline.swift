import SwiftUI

struct Sparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(samples.max() ?? 0, 1)
            let step = samples.count > 1 ? geometry.size.width / CGFloat(samples.count - 1) : 0
            Path { path in
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geometry.size.height * (1 - CGFloat(sample / peak))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1)
        }
    }
}
