// MileageTracker Design System
// Centralised colours, typography helpers, and spacing constants

import SwiftUI

// MARK: - Brand Colours

extension Color {
    // Primary brand green
    static let mtGreen       = Color(red: 0.18, green: 0.78, blue: 0.45)   // #2DC873
    static let mtGreenDark   = Color(red: 0.12, green: 0.60, blue: 0.33)   // #1F9955
    static let mtGreenLight  = Color(red: 0.72, green: 0.95, blue: 0.82)   // #B8F2D1

    // Semantic
    static let mtBackground  = Color(.systemBackground)
    static let mtSurface     = Color(.secondarySystemBackground)
    static let mtBorder      = Color(.separator)
    static let mtTextPrimary = Color(.label)
    static let mtTextSub     = Color(.secondaryLabel)

    // Status
    static let mtRecording   = Color(red: 1.0, green: 0.27, blue: 0.27)    // active trip red-ish
    static let mtWarning     = Color(red: 1.0, green: 0.75, blue: 0.0)
    static let mtSuccess     = Color.mtGreen
}

// MARK: - Spacing

enum MTSpacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 16
    static let lg:   CGFloat = 24
    static let xl:   CGFloat = 32
    static let xxl:  CGFloat = 48
}

// MARK: - Corner Radius

enum MTRadius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Reusable View Modifiers

struct MTCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.lg))
    }
}

extension View {
    func mtCard() -> some View {
        modifier(MTCardStyle())
    }
}

// MARK: - Primary Button Style

struct MTPrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MTSpacing.md)
            .background(
                (isDestructive ? Color.mtRecording : Color.mtGreen)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct MTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.mtGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MTSpacing.md)
            .background(Color.mtGreenLight.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
