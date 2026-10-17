import SwiftUI

/// Picks up exactly where the launch screen leaves off (same bell, same place), gives the
/// bell a ring, fades in the name, then hands over.
struct SplashView: View {
    let brand: Namespace.ID
    let onFinished: () -> Void

    @State private var ring = false
    @State private var showName = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BrandMark()
                .keyframeAnimator(initialValue: 0.0, trigger: ring) { mark, angle in
                    mark.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 0.3))
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(14, duration: 0.12)
                        CubicKeyframe(-12, duration: 0.14)
                        CubicKeyframe(8, duration: 0.12)
                        CubicKeyframe(-5, duration: 0.1)
                        CubicKeyframe(0, duration: 0.12)
                    }
                }
                .matchedGeometryEffect(id: "mark", in: brand)

            Text("Remder")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(showName ? 1 : 0)
                .offset(y: showName ? 66 : 78)
                .blur(radius: showName ? 0 : 6)
        }
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            ring = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.smooth(duration: 0.5).delay(0.25)) { showName = true }
            try? await Task.sleep(for: .milliseconds(1100))
            onFinished()
        }
    }
}

#Preview {
    @Previewable @Namespace var brand
    SplashView(brand: brand) {}
}
