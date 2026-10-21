import AppKit
import MouseEngine
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
        case .wheelButton: return (CGPoint(x: 0.415, y: 0.087), .zero, 0, 0)
        case .wheel: return (CGPoint(x: 0.397, y: 0.063), CGSize(width: 0.115, height: 0.085), -32, 0.2)
        case .top: return (CGPoint(x: 0.479, y: 0.164), CGSize(width: 0.065, height: 0.04), -32, 0.2)
        case .thumbWheel: return (CGPoint(x: 0.203, y: 0.34), CGSize(width: 0.08, height: 0.155), -27, 0.3)
        case .forward: return (CGPoint(x: 0.164, y: 0.385), CGSize(width: 0.025, height: 0.065), -26, 0.4)
        case .back: return (CGPoint(x: 0.212, y: 0.466), CGSize(width: 0.025, height: 0.077), -29, 0.4)
        case .gesture: return (CGPoint(x: 0.076, y: 0.704), CGSize(width: 0.022, height: 0.049), -10, 0.5)
        }
    }

    fileprivate var labelOnLeft: Bool {
        switch self {
        case .wheel, .wheelButton, .top: return false
        case .thumbWheel, .forward, .back, .gesture: return true
        }
    }
}

/// An MX Master 3S with controls aligned to the bundled product image. Click a control or its label to select it.
struct MouseIllustration: View {
    @Binding var selection: MouseButton
    var summaries: [MouseButton: String]
    var enabled: [MouseButton: Bool]
    var pressed: Set<MouseButton>

    @StateObject private var hover = HoverState()
    private var hovered: MouseButton? { hover.button }

    private static let productImage = NSImage(
        contentsOf: Bundle.module.url(forResource: "mx-master-3s", withExtension: "png")!)!
    private static let stageSize = CGSize(width: 600, height: 500)
    private let mouseRect = CGRect(x: 172, y: 72, width: 280, height: 280 * 623 / 580)
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
            mouseBody
            leaders
            ForEach(MouseButton.allCases.filter { $0.drawnOn == $0 }) { button in hotspot(button) }
            ForEach(MouseButton.allCases) { button in label(button) }
        }
        .frame(width: Self.stageSize.width, height: Self.stageSize.height, alignment: .topLeading)
    }

    private var mouseBody: some View {
        Image(nsImage: Self.productImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: mouseRect.width, height: mouseRect.height)
            .shadow(color: .black.opacity(0.16), radius: 10, x: 2, y: 8)
            .offset(x: mouseRect.minX, y: mouseRect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        let active = selected || hovered?.drawnOn == button || isPressed
        let tint: Color = isPressed ? .green : .accentColor
        return Button {
            selection = button
        } label: {
            shape
                .fill(tint.opacity(active ? 0.22 : 0))
                .overlay(shape.stroke(tint.opacity(active ? 1 : 0), lineWidth: 1.5))
                .shadow(color: tint.opacity(active ? 0.35 : 0), radius: 5)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(spot.degrees))
                .contentShape(shape.inset(by: -6))
        }
        .buttonStyle(.plain)
        .position(point(spot.center))
        .onHover { hover.update(button, inside: $0) }
        .accessibilityLabel(button.title)
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
