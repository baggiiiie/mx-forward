import ForwardCore
import SwiftUI

enum MouseButton: String, CaseIterable, Identifiable {
    case wheel, wheelButton, top, thumbWheel, forward, back, gesture

    var id: Self { self }

    var title: String {
        switch self {
        case .wheel: return "Main wheel"
        case .wheelButton: return "Wheel button"
        case .top: return "Top button"
        case .thumbWheel: return "Thumb wheel"
        case .forward: return "Forward"
        case .back: return "Back"
        case .gesture: return "Gesture button"
        }
    }

    var symbol: String {
        switch self {
        case .wheel: return "arrow.up.and.down"
        case .wheelButton: return "smallcircle.filled.circle"
        case .top: return "plus.magnifyingglass"
        case .thumbWheel: return "arrow.left.and.right"
        case .forward: return "arrow.right"
        case .back: return "arrow.left"
        case .gesture: return "hand.draw"
        }
    }

    var control: MouseControl? {
        switch self {
        case .wheelButton: return .middle
        case .top: return .top
        case .forward: return .forward
        case .back: return .back
        case .gesture: return .thumb
        case .wheel, .thumbWheel: return nil
        }
    }

    /// Pressing the wheel is drawn on the wheel itself.
    fileprivate var drawnOn: MouseButton { self == .wheelButton ? .wheel : self }

    /// Position and size relative to the mouse body (0–1), rotation, and corner roundness.
    fileprivate var hotspot: (center: CGPoint, size: CGSize, degrees: Double, roundness: CGFloat) {
        switch self {
        case .wheelButton: return (CGPoint(x: 0.575, y: 0.23), .zero, 0, 0)
        case .wheel: return (CGPoint(x: 0.575, y: 0.175), CGSize(width: 0.085, height: 0.16), 0, 0.5)
        case .top: return (CGPoint(x: 0.585, y: 0.315), CGSize(width: 0.075, height: 0.045), 0, 0.4)
        case .thumbWheel: return (CGPoint(x: 0.215, y: 0.33), CGSize(width: 0.06, height: 0.13), -18, 0.5)
        case .forward: return (CGPoint(x: 0.13, y: 0.46), CGSize(width: 0.06, height: 0.085), -10, 0.45)
        case .back: return (CGPoint(x: 0.105, y: 0.565), CGSize(width: 0.06, height: 0.085), -6, 0.45)
        case .gesture: return (CGPoint(x: 0.07, y: 0.685), CGSize(width: 0.05, height: 0.1), 8, 0.5)
        }
    }

    fileprivate var labelOnLeft: Bool {
        switch self {
        case .wheel, .wheelButton, .top: return false
        case .thumbWheel, .forward, .back, .gesture: return true
        }
    }
}

/// A top-down MX Master 3S. Click a control or its label to select it.
struct MouseIllustration: View {
    @Binding var selection: MouseButton
    var summaries: [MouseButton: String]
    var enabled: [MouseButton: Bool]
    var pressed: Set<MouseButton>

    @StateObject private var hover = HoverState()
    private var hovered: MouseButton? { hover.button }

    private static let stageSize = CGSize(width: 600, height: 500)
    private let mouseRect = CGRect(x: 190, y: 20, width: 232, height: 450)
    private let labelWidth: CGFloat = 160

    private func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: mouseRect.minX + unit.x * mouseRect.width, y: mouseRect.minY + unit.y * mouseRect.height)
    }

    private func labelCenter(_ button: MouseButton) -> CGPoint {
        if button.labelOnLeft {
            let index = CGFloat(MouseButton.allCases.filter(\.labelOnLeft).firstIndex(of: button) ?? 0)
            return CGPoint(x: 10 + labelWidth / 2, y: 140 + index * 80)
        }
        let y: CGFloat = button == .wheel ? 64 : button == .wheelButton ? 122 : 180
        return CGPoint(x: Self.stageSize.width - 10 - labelWidth / 2, y: y)
    }

    private func leaderStart(_ button: MouseButton) -> CGPoint {
        let center = labelCenter(button)
        return CGPoint(x: center.x + (button.labelOnLeft ? labelWidth / 2 : -labelWidth / 2), y: center.y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: mouseRect.width * 0.8, height: 34)
                .blur(radius: 22)
                .position(x: mouseRect.midX + 10, y: mouseRect.maxY - 8)
            mouseBody
            leaders
            ForEach(MouseButton.allCases.filter { $0.drawnOn == $0 }) { button in hotspot(button) }
            ForEach(MouseButton.allCases) { button in label(button) }
        }
        .frame(width: Self.stageSize.width, height: Self.stageSize.height, alignment: .topLeading)
    }

    private var mouseBody: some View {
        let shell = LinearGradient(
            colors: [Color(white: 0.30), Color(white: 0.17), Color(white: 0.12)],
            startPoint: .topTrailing, endPoint: .bottomLeading)
        let sheen = RadialGradient(
            colors: [Color.white.opacity(0.13), .clear], center: UnitPoint(x: 0.66, y: 0.5),
            startRadius: 0, endRadius: mouseRect.width * 0.55)
        return ZStack {
            MouseBodyShape().fill(shell)
            MouseBodyShape().fill(sheen)
            ThumbRestShape().fill(Color.black.opacity(0.28))
            ThumbRestShape().stroke(Color.white.opacity(0.06), lineWidth: 1)
            ButtonSeamsShape().stroke(Color.black.opacity(0.55), lineWidth: 1.5)
            ButtonSeamsShape().stroke(Color.white.opacity(0.07), lineWidth: 0.5).offset(x: 0.5, y: 0.8)
            Text("MX")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.10))
                .position(x: mouseRect.width * 0.6, y: mouseRect.height * 0.8)
        }
        .clipShape(MouseBodyShape())
        .overlay(MouseBodyShape().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .frame(width: mouseRect.width, height: mouseRect.height)
        .offset(x: mouseRect.minX, y: mouseRect.minY)
        .allowsHitTesting(false)
    }

    private var leaders: some View {
        Canvas { context, _ in
            for button in MouseButton.allCases {
                let start = leaderStart(button)
                let end = point(button.hotspot.center)
                var path = Path()
                path.move(to: start)
                let elbow = CGPoint(x: start.x + (button.labelOnLeft ? 14 : -14), y: start.y)
                path.addLine(to: elbow)
                path.addLine(to: end)
                let active = button == selection || button == hovered
                context.stroke(
                    path, with: .color(active ? Color.accentColor : Color.secondary.opacity(0.45)),
                    style: StrokeStyle(lineWidth: active ? 1.5 : 1, dash: active ? [] : [3, 3]))
                let dot = CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)
                context.fill(
                    Path(ellipseIn: dot), with: .color(active ? Color.accentColor : .white.opacity(0.7)))
            }
        }
        .frame(width: Self.stageSize.width, height: Self.stageSize.height)
        .allowsHitTesting(false)
    }

    private func hotspot(_ button: MouseButton) -> some View {
        let spot = button.hotspot
        let size = CGSize(
            width: spot.size.width * mouseRect.width, height: spot.size.height * mouseRect.height)
        let shape = RoundedRectangle(
            cornerRadius: min(size.width, size.height) * spot.roundness, style: .continuous)
        let selected = selection.drawnOn == button
        let isPressed = pressed.contains { $0.drawnOn == button }
        let fill: Color =
            isPressed
            ? .green
            : selected
                ? .accentColor
                : hovered?.drawnOn == button ? Color.accentColor.opacity(0.55) : Color(white: 0.38)
        return
            shape
            .fill(fill.gradient)
            .overlay(
                shape.stroke(Color.white.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 1.5 : 0.8)
            )
            .overlay {
                if button == .wheel || button == .thumbWheel {
                    WheelRidges().stroke(Color.black.opacity(0.35), lineWidth: 1)
                        .padding(3).clipShape(shape)
                }
            }
            .shadow(color: selected ? Color.accentColor.opacity(0.8) : .clear, radius: 8)
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(spot.degrees))
            .contentShape(shape.inset(by: -6))
            .position(point(spot.center))
            .onTapGesture { selection = button }
            .onHover { hover.update(button, inside: $0) }
            .accessibilityElement()
            .accessibilityLabel(button.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func label(_ button: MouseButton) -> some View {
        let selected = button == selection
        let isOn = enabled[button] ?? true
        return Button {
            selection = button
        } label: {
            HStack(spacing: 8) {
                if !button.labelOnLeft { Spacer(minLength: 0) }
                Image(systemName: button.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(selected ? Color.accentColor : Color.secondary.opacity(0.18))
                    )
                    .foregroundStyle(selected ? Color.white : Color.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(button.title).font(.callout.weight(.semibold))
                    Text(isOn ? (summaries[button] ?? "") : "Off")
                        .font(.caption)
                        .foregroundStyle(isOn ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if button.labelOnLeft { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: labelWidth)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor.opacity(0.14)
                            : Color.primary.opacity(button == hovered ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.update(button, inside: $0) }
        .position(labelCenter(button))
        .accessibilityLabel("\(button.title): \(isOn ? summaries[button] ?? "" : "Off")")
    }
}

private struct MouseBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.56, 0.012))
        path.addCurve(to: p(0.90, 0.10), control1: p(0.74, 0.005), control2: p(0.86, 0.04))
        path.addCurve(to: p(0.96, 0.46), control1: p(0.95, 0.18), control2: p(0.97, 0.32))
        path.addCurve(to: p(0.81, 0.93), control1: p(0.96, 0.66), control2: p(0.93, 0.84))
        path.addCurve(to: p(0.40, 0.995), control1: p(0.70, 1.0), control2: p(0.52, 1.0))
        path.addCurve(to: p(0.03, 0.74), control1: p(0.20, 0.985), control2: p(0.06, 0.88))
        path.addCurve(to: p(0.04, 0.47), control1: p(0.0, 0.64), control2: p(0.0, 0.54))
        path.addCurve(to: p(0.22, 0.09), control1: p(0.08, 0.32), control2: p(0.13, 0.16))
        path.addCurve(to: p(0.56, 0.012), control1: p(0.31, 0.03), control2: p(0.44, 0.015))
        path.closeSubpath()
        return path
    }
}

private struct ThumbRestShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.17, 0.15))
        path.addCurve(to: p(0.31, 0.56), control1: p(0.29, 0.25), control2: p(0.33, 0.42))
        path.addCurve(to: p(0.14, 0.90), control1: p(0.29, 0.70), control2: p(0.23, 0.83))
        path.addLine(to: p(-0.1, 0.9))
        path.addLine(to: p(-0.1, 0.15))
        path.closeSubpath()
        return path
    }
}

private struct ButtonSeamsShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.565, 0.02))
        path.addLine(to: p(0.57, 0.085))
        path.move(to: p(0.585, 0.35))
        path.addCurve(to: p(0.60, 0.43), control1: p(0.59, 0.38), control2: p(0.595, 0.41))
        path.move(to: p(0.30, 0.25))
        path.addCurve(to: p(0.94, 0.40), control1: p(0.48, 0.44), control2: p(0.76, 0.47))
        return path
    }
}

private struct WheelRidges: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = 9
        for index in 1..<count {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(count)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private final class HoverState: ObservableObject {
    @Published var button: MouseButton?
    func update(_ target: MouseButton, inside: Bool) {
        if inside {
            button = target
        } else if button == target {
            button = nil
        }
    }
}
