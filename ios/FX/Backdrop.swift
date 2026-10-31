import SwiftUI
import UIKit

// MARK: - Backdrop

/// "ambient" (default): the active currency's flag as a blurred light source. "system": flat.
struct Backdrop: View {
    var activeCode: String
    @AppStorage("bg") private var style = "ambient"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color.black : Color(white: 0.96))
            if style != "system", let f = Currency.flag(activeCode) {
                ZStack {
                    Text(f)
                        .font(.system(size: 640))
                        .blur(radius: 80)
                        .opacity(dark ? 0.85 : 0.8)
                        .offset(y: -300)
                    Text(f)
                        .font(.system(size: 640))
                        .scaleEffect(x: -1)
                        .blur(radius: 110)
                        .opacity(dark ? 0.5 : 0.55)
                        .offset(y: 420)
                }
                .saturation(1.35)
                .id(activeCode)
                .transition(.opacity)
                LinearGradient(colors: dark ? [.black.opacity(0.15), .black.opacity(0.45)]
                                            : [.white.opacity(0.0), .white.opacity(0.2)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: activeCode)
        .ignoresSafeArea()
    }
}
