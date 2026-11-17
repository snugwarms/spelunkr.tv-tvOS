import SpelunkrCore
import SwiftUI

struct ChannelIcon: View {
    let channel: Channel
    var body: some View {
        Group {
            if let mark = channel.logomark, mark.type == "pixel", let rows = mark.rows,
               !rows.isEmpty, rows.count <= 64, rows.allSatisfy({ $0.count == rows.count }) {
                let colors = palette(channel.color)
                Canvas { context, size in
                    let step = min(size.width, size.height) / CGFloat(rows.count)
                    for (y, row) in rows.enumerated() {
                        for (x, token) in row.enumerated() where token != "." {
                            guard let color = colors[token] else { continue }
                            let rect = CGRect(x: CGFloat(x) * step, y: CGFloat(y) * step, width: step, height: step)
                            context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                        }
                    }
                }
            } else {
                Image(systemName: "tv").resizable().scaledToFit().foregroundStyle(.cyan)
            }
        }
        .accessibilityHidden(true)
    }

    private func palette(_ hex: String?) -> [Character: Color] {
        func color(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
        }
        let value = UInt32((hex ?? "#666666").replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x666666
        let red = Double((value >> 16) & 255) / 255, green = Double((value >> 8) & 255) / 255, blue = Double(value & 255) / 255
        let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
        let saturation = high > 0 ? delta / high : 0
        var hue: Double = 0
        if delta > 0 {
            if high == red { hue = 60 * ((green - blue) / delta + (green < blue ? 6 : 0)) }
            else if high == green { hue = 60 * ((blue - red) / delta + 2) }
            else { hue = 60 * ((red - green) / delta + 4) }
        }
        func movedHue(toward target: Double, by step: Double) -> Double {
            let difference = (target - hue + 540).truncatingRemainder(dividingBy: 360) - 180
            return (hue + (difference >= 0 ? 1 : -1) * min(step, abs(difference)) + 360).truncatingRemainder(dividingBy: 360) / 360
        }
        return [
            "k": color(0x0b0f26), "n": color(0x2a3580), "s": color(0x8899cc),
            "p": color(0xe8eaf0), "g": color(0xffd740), "o": color(0xd2500c), "c": color(value),
            "d": Color(hue: movedHue(toward: 255, by: 14), saturation: min(1, saturation * 1.1), brightness: high * 0.6),
            "l": Color(hue: movedHue(toward: 50, by: 10), saturation: saturation * 0.6, brightness: high + (1 - high) * 0.6)
        ]
    }
}
