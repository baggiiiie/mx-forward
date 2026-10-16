import AppKit
import ForwardCore

final class ZoomTests {
    func testMacOSDecodesNativePinchPhases() {
        let samples: [(ZoomAction, NSEvent.Phase)] = [
            (.begin, .began), (.magnify(0.125), .changed), (.end, .ended), (.cancel, .cancelled),
        ]
        for (action, phase) in samples {
            let cg = ZoomEvent.make(action, at: CGPoint(x: 100, y: 100))!
            let native = NSEvent(cgEvent: cg)!
            expectEqual(native.type, .magnify)
            expectEqual(native.phase, phase)
            if case .magnify(let value) = action {
                expectEqual(abs(native.magnification - value) < 0.000001, true)
            }
        }
    }

    func testMacOSDecodesSmartZoom() {
        let native = NSEvent(cgEvent: ZoomEvent.make(.click, at: .zero)!)!
        expectEqual(native.type, .smartMagnify)
    }
}
