import AppKit
import ForwardCore

final class ZoomTests {
    private func amount(_ actions: [ZoomAction]) -> Double {
        actions.reduce(0) { value, action in
            if case .magnify(let delta) = action { return value + delta }
            return value
        }
    }

    func testClickAndIdle() {
        var zoom = ZoomInterpreter()
        expectEqual(zoom.up(), [])
        expectEqual(zoom.move(dx: 0, dy: -100), [])
        zoom.down()
        expectEqual(zoom.up(), [.click])
        expectEqual(zoom.up(), [])
    }

    func testJitterStillClicks() {
        var zoom = ZoomInterpreter()
        zoom.down()
        expectEqual(zoom.move(dx: 2, dy: -3), [])
        expectEqual(zoom.up(), [.click])
    }

    func testVerticalGestureAndReversal() {
        var zoom = ZoomInterpreter()
        zoom.down()
        let first = zoom.move(dx: 0, dy: -100)
        expectEqual(first.first, .begin)
        expectEqual(abs(amount(first) - 0.15) < 0.000001, true)
        let reverse = zoom.move(dx: 0, dy: 100)
        expectEqual(reverse.count, 1)
        expectEqual(amount(reverse) < 0, true)
        expectEqual(zoom.up(), [.end])
        expectEqual(zoom.up(), [])
    }

    func testHorizontalMovementDoesNotRotateOrClick() {
        var zoom = ZoomInterpreter()
        zoom.down()
        expectEqual(zoom.move(dx: 150, dy: 0), [])
        expectEqual(zoom.up(), [])
    }

    func testStaleFirstReportDoesNotCauseZoom() {
        var zoom = ZoomInterpreter()
        zoom.down(discardFirstReport: true)
        expectEqual(zoom.move(dx: .max, dy: .min), [])
        expectEqual(zoom.up(), [.click])
        zoom.down(discardFirstReport: true)
        expectEqual(zoom.move(dx: 1000, dy: -1000), [])
        expectEqual(zoom.move(dx: 0, dy: -40).first, .begin)
        expectEqual(zoom.up(), [.end])
    }

    func testCancellationEndsGestureWithoutClick() {
        var zoom = ZoomInterpreter()
        zoom.down()
        _ = zoom.move(dx: 0, dy: -100)
        expectEqual(zoom.cancel(), [.cancel])
        expectEqual(zoom.up(), [])
        expectEqual(zoom.cancel(), [])
        zoom.down()
        expectEqual(zoom.up(), [.click])
    }

    func testSensitivityAndLargePacketLimit() {
        var zoom = ZoomInterpreter()
        zoom.down(sensitivity: 2)
        expectEqual(abs(amount(zoom.move(dx: 0, dy: -40)) - 0.12) < 0.000001, true)
        expectEqual(amount(zoom.move(dx: 0, dy: .min)), 0.25)
        expectEqual(amount(zoom.move(dx: 0, dy: .max)), -0.25)
    }

    func testDuplicateDownDoesNotRestartGesture() {
        var zoom = ZoomInterpreter()
        zoom.down()
        _ = zoom.move(dx: 0, dy: -100)
        zoom.down()
        expectEqual(zoom.move(dx: 0, dy: -30).count, 1)
        expectEqual(zoom.up(), [.end])
    }

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
