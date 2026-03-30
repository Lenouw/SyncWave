import SwiftUI

/// Draws a waveform from an array of peak amplitude values [0, 1].
struct WaveformView: View {
    let samples: [Float]
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = samples.count
            guard count > 0 else { return AnyView(EmptyView()) }
            let barWidth = w / CGFloat(count)

            return AnyView(
                Canvas { context, size in
                    for i in 0..<count {
                        let amplitude = CGFloat(samples[i])
                        let barHeight = max(1, amplitude * h)
                        let x = CGFloat(i) * barWidth
                        let y = (h - barHeight) / 2
                        let rect = CGRect(x: x, y: y, width: max(1, barWidth - 0.5), height: barHeight)
                        context.fill(Path(rect), with: .color(Color.white.opacity(0.75)))
                    }
                }
            )
        }
    }
}
