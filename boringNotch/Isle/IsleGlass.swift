//
//  IsleGlass.swift
//  boringNotch
//
//  Liquid Glass styling for the island (macOS 26+) with a black fallback,
//  plus the album glow and the blur/scale open transition.
//  Licensed under GPL-3.0 like the rest of the project.
//

import Defaults
import SwiftUI

enum IsleGlass {
    /// True when the running system and the toolchain both support Liquid Glass.
    static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Liquid Glass is in use (supported and enabled in settings).
    static var isActive: Bool {
        isSupported && Defaults[.isleLiquidGlass]
    }

    /// How far below the notch the black band fades out.
    static let bandFade: CGFloat = 34
}

// MARK: - Island background

/// Closed: solid black. Open: Liquid Glass tinted black with a black band at the top
/// (solid at notch height, fading out ~34 pt below) so the island grows out of the notch.
struct IsleIslandBackground<S: Shape>: ViewModifier {
    let isOpen: Bool
    let shape: S
    let notchHeight: CGFloat
    @Default(.isleLiquidGlass) private var liquidGlass
    @Default(.isleGlassTint) private var glassTint

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if liquidGlass {
                content
                    .background(alignment: .top) {
                        band.opacity(isOpen ? 1 : 0)
                    }
                    .background(Color.black.opacity(isOpen ? 0 : 1))
                    .glassEffect(
                        isOpen ? Glass.regular.tint(.black.opacity(max(0, min(1, glassTint)))) : Glass.identity,
                        in: shape
                    )
            } else {
                content.background(.black)
            }
        } else {
            content.background(.black)
        }
        #else
        content.background(.black)
        #endif
    }

    private var band: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: max(0, notchHeight))
            LinearGradient(
                colors: [.black, .black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: IsleGlass.bandFade)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass buttons

/// Capsule button background: interactive Liquid Glass on macOS 26+, a flat fill otherwise.
struct IsleGlassCapsule: ViewModifier {
    var fallback: Color = Color.white.opacity(0.1)
    @Default(.isleLiquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if liquidGlass {
                content
                    .contentShape(Capsule())
                    .glassEffect(Glass.regular.interactive(), in: Capsule())
            } else {
                content
                    .background(Capsule().fill(fallback))
                    .contentShape(Capsule())
            }
        } else {
            content
                .background(Capsule().fill(fallback))
                .contentShape(Capsule())
        }
        #else
        content
            .background(Capsule().fill(fallback))
            .contentShape(Capsule())
        #endif
    }
}

extension View {
    func isleIslandBackground<S: Shape>(isOpen: Bool, shape: S, notchHeight: CGFloat) -> some View {
        modifier(IsleIslandBackground(isOpen: isOpen, shape: shape, notchHeight: notchHeight))
    }

    func isleGlassCapsule(fallback: Color = Color.white.opacity(0.1)) -> some View {
        modifier(IsleGlassCapsule(fallback: fallback))
    }

    /// Soft glow below the open island, tinted by the album art.
    func isleAlbumGlow(color: NSColor, active: Bool) -> some View {
        shadow(
            color: active ? Color(nsColor: color).opacity(0.55) : .clear,
            radius: 18,
            x: 0,
            y: 6
        )
    }
}

// MARK: - Open transition

private struct IsleBlurScale: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 14 * amount)
            .scaleEffect(1 - 0.12 * amount, anchor: .top)
    }
}

extension AnyTransition {
    /// Blur + scale + fade used when the island opens.
    static var isleOpen: AnyTransition {
        .modifier(active: IsleBlurScale(amount: 1), identity: IsleBlurScale(amount: 0))
            .combined(with: .opacity)
            .animation(.smooth(duration: 0.38))
    }
}
