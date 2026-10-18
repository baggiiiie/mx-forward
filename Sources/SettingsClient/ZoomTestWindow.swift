import AppKit
import ForwardCore
import MouseEngine

@MainActor
final class ZoomTestWindow: NSWindowController {
    private let canvas = ZoomTestCanvas()
    private let status = NSTextField(labelWithString: "100% · waiting for a native zoom event")
    private let onLog: (String) -> Void

    init(onLog: @escaping (String) -> Void) {
        self.onLog = onLog
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 450),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Zoom Verification"
        window.isReleasedWhenClosed = false
        window.center()
        let zoom = NSButton(title: "Send zoom in", target: self, action: #selector(testZoom))
        let smart = NSButton(title: "Send smart zoom", target: self, action: #selector(testSmartZoom))
        let buttons = NSStackView(views: [zoom, smart])
        buttons.spacing = 12
        let hint = NSTextField(
            labelWithString:
                "Point here, then hold the top button and move up/down. A click uses your chosen action.")
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        let stack = NSStackView(views: [buttons, status, hint, canvas])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
                canvas.widthAnchor.constraint(equalTo: stack.widthAnchor),
                canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            ])
        }
        canvas.onEvent = { [weak self] message in
            self?.status.stringValue = message
            self?.onLog(message)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func testZoom() { send([.begin, .magnify(0.2), .end]) }
    @objc private func testSmartZoom() { send([.click]) }

    private func send(_ actions: [ZoomAction]) {
        guard let window else { return }
        let center = canvas.convert(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        let screenPoint = window.convertPoint(toScreen: center)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let anchor = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)
        for action in actions {
            if !ZoomOutput.send(action, at: anchor) {
                status.stringValue = "Accessibility permission is needed to send zoom events."
                return
            }
        }
    }
}

final class ZoomTestCanvas: NSView {
    var onEvent: (String) -> Void = { _ in }
    private var scale = 1.0
    private var eventCount = 0
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let text = "Native zoom\n\(Int(scale * 100))%" as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(
            in: bounds.insetBy(dx: 16, dy: 60),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 28 * scale),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
    }

    override func magnify(with event: NSEvent) {
        scale = max(0.25, min(4, scale * (1 + event.magnification)))
        report("magnify", phase: "\(event.phase.rawValue)")
    }

    override func smartMagnify(with event: NSEvent) {
        scale = scale > 1.1 ? 1 : 2
        report("smart zoom", phase: "toggle")
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    private func report(_ kind: String, phase: String) {
        eventCount += 1
        onEvent("\(Int(scale * 100))% · received \(kind) · phase \(phase) · event \(eventCount)")
        needsDisplay = true
    }
}
