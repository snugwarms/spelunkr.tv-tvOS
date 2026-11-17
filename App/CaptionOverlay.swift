import SwiftUI

struct CaptionOverlay: View {
    @ObservedObject var captions: LiveCaptions
    @ObservedObject var community: CommunityPlayback
    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.35, min(1, geometry.size.width / 1440))
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let recentText = context.date.timeIntervalSince(captions.lastTextAt) < 6 ? captions.text : ""
                let value = !recentText.isEmpty ? recentText : captions.status ?? ""
                if captions.isEnabled, !value.isEmpty {
                    VStack {
                        Spacer()
                        Text(value)
                            .accessibilityIdentifier("captionText")
                            .font(.system(size: 29 * scale, weight: .semibold))
                            .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3)
                            .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
                            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7 * scale))
                            .frame(maxWidth: geometry.size.width * 0.82)
                            .padding(.bottom, (community.comments.isEmpty ? 50 : 230) * scale)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Automatic captions")
    }
}
