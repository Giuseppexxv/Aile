import SwiftUI

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

extension View {
    /// Liquid Glass su iOS 26, materiale sfocato su versioni precedenti.
    @ViewBuilder
    func glass(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive),
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.35))
                    }
                }
            }
        }
    }
}

struct GlassButton: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

/// Sfondo colorato dietro al vetro, così l'effetto si nota.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.09)
            Circle().fill(Color.blue.opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -130, y: -260)
            Circle().fill(Color.purple.opacity(0.50))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 150, y: 40)
            Circle().fill(Color.teal.opacity(0.40))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -90, y: 330)
        }
        .ignoresSafeArea()
    }
}
