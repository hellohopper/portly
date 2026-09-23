import SwiftUI

struct Sparkline: View {
    let samples: [Double]
    var color: Color = .accentColor
    /// `.fromZero` suits rates (throughput); `.range` suits levels like memory, where
    /// the interesting part is the change, not the distance from zero -- scaled from
    /// zero, 300MB -> 320MB is a flat line pinned to the top of the frame.
    var scaling: Scaling = .fromZero

    enum Scaling {
        case fromZero
        case range
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = verticalBounds()
            let step = samples.count > 1 ? geometry.size.width / CGFloat(samples.count - 1) : 0
            Path { path in
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * step
                    let fraction = (sample - bounds.lower) / (bounds.upper - bounds.lower)
                    let y = geometry.size.height * (1 - CGFloat(fraction))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1)
        }
    }

    private func verticalBounds() -> (lower: Double, upper: Double) {
        let peak = samples.max() ?? 0
        switch scaling {
        case .fromZero:
            return (0, max(peak, 1))
        case .range:
            let low = samples.min() ?? 0
            // At least 10% of the level, so jitter doesn't read as a cliff; a flat
            // series sits in the middle of the frame.
            let span = max(peak - low, peak * 0.1, 1)
            let middle = (peak + low) / 2
            return (middle - span / 2, middle + span / 2)
        }
    }
}
