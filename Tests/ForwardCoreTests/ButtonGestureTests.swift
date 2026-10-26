import ForwardCore
import Foundation

final class ButtonGestureTests {
    private func amount(_ events: [ButtonGesture.Event]) -> Double {
        events.reduce(0) { value, event in
            if case .zoom(.magnify(let delta)) = event { return value + delta }
            return value
        }
    }

    private func pressed(_ options: ButtonGesture.Options = .init(), at time: TimeInterval = 0)
        -> ButtonGesture
    {
        var gesture = ButtonGesture()
        gesture.down(at: time, options: options)
        return gesture
    }

    func testClickJitterAndIdle() {
        var gesture = ButtonGesture()
        expectEqual(gesture.up(at: 0), [])
        expectEqual(gesture.move(dx: 0, dy: -500), [])
        gesture = pressed()
        expectEqual(gesture.move(dx: 4, dy: -3), [])
        expectEqual(gesture.up(at: 0.1), [.action(.click)])
        expectEqual(gesture.isPressed, false)
        expectEqual(gesture.up(at: 0.2), [])
    }

    func testDoubleClickSuppressesSinglesAndStartsANewPair() {
        let options = ButtonGesture.Options(doubleClickInterval: 0.5)
        var gesture = pressed(options)
        expectEqual(gesture.up(at: 0.1), [])
        expectEqual(gesture.isPressed, false)
        expectEqual(gesture.nextDeadline, 0.5)
        expectEqual(gesture.advance(to: 0.49), [])
        expectEqual(gesture.down(at: 0.49, options: options), [])
        expectNil(gesture.nextDeadline)
        expectEqual(gesture.advance(to: 0.7), [])
        expectEqual(gesture.up(at: 0.8), [.action(.doubleClick)])
        expectEqual(gesture.isActive, false)
        gesture.down(at: 0.9, options: options)
        expectEqual(gesture.up(at: 1), [])
        expectEqual(gesture.advance(to: 1.4), [.action(.click)])
        expectEqual(gesture.advance(to: 2), [])
        expectEqual(gesture.isActive, false)
    }

    func testDoubleClickDeadlineUsesPressTimeAndFlushesALateTimer() {
        let options = ButtonGesture.Options(doubleClickInterval: 0.5)
        var gesture = pressed(options)
        expectEqual(gesture.up(at: 0.4), [])
        expectEqual(gesture.down(at: 0.5, options: options), [.action(.click)])
        expectEqual(gesture.up(at: 0.6), [])
        expectEqual(gesture.advance(to: 1), [.action(.click)])
        gesture.down(at: 2, options: options)
        expectEqual(gesture.up(at: 3), [.action(.click)])
        expectEqual(gesture.isActive, false)
        for interval in [0.2, 0.8] {
            var timed = pressed(.init(doubleClickInterval: interval))
            expectEqual(timed.up(at: 0.05), [])
            expectEqual(timed.advance(to: interval - 0.01), [])
            expectEqual(timed.advance(to: interval), [.action(.click)])
        }
    }

    func testDoubleClickKeepsHoldDragAndCancellationSeparate() {
        let options = ButtonGesture.Options(holdDelay: 0.4, doubleClickInterval: 0.5)
        var gesture = pressed(options)
        _ = gesture.up(at: 0.1)
        gesture.down(at: 0.2, options: options)
        expectEqual(gesture.advance(to: 0.7), [.action(.click), .action(.hold)])
        expectEqual(gesture.up(at: 0.8), [])
        gesture.down(at: 1, options: options)
        _ = gesture.up(at: 1.1)
        gesture.down(at: 1.2, options: options)
        expectEqual(gesture.move(dx: 130, dy: 0), [.action(.click), .action(.right)])
        expectEqual(gesture.up(at: 1.3), [])
        gesture.down(at: 2, options: options)
        _ = gesture.up(at: 2.1)
        expectEqual(gesture.cancel(), [])
        expectEqual(gesture.advance(to: 3), [])
        expectEqual(gesture.isActive, false)
        gesture.down(at: 4, options: options)
        expectEqual(gesture.up(at: 4.5), [.action(.hold)])
    }

    func testWithoutHoldALongPressStillClicks() {
        var gesture = pressed()
        expectEqual(gesture.advance(to: 10), [])
        expectEqual(gesture.up(at: 10), [.action(.click)])
    }

    func testHoldFiresOnceWithoutAClick() {
        var gesture = pressed(.init(holdDelay: 0.4), at: 1)
        expectEqual(gesture.advance(to: 1.39), [])
        expectEqual(gesture.advance(to: 1.4), [.action(.hold)])
        expectEqual(gesture.advance(to: 2), [])
        expectEqual(gesture.move(dx: 0, dy: -500), [])
        expectEqual(gesture.up(at: 2), [])
    }

    func testShortPressWithHoldEnabledClicks() {
        var gesture = pressed(.init(holdDelay: 0.4))
        expectEqual(gesture.up(at: 0.39), [.action(.click)])
    }

    func testLateTimerStillRecognizesHoldAtRelease() {
        var gesture = pressed(.init(holdDelay: 0.4))
        expectEqual(gesture.up(at: 0.4), [.action(.hold)])
    }

    func testAllDirectionsSuppressTheReleaseClick() {
        let moves: [(Int16, Int16, ButtonSlot)] = [
            (0, -130, .up), (0, 130, .down), (-130, 0, .left), (130, 0, .right),
        ]
        for (dx, dy, slot) in moves {
            var gesture = pressed()
            expectEqual(gesture.move(dx: dx, dy: dy), [.action(slot)])
            expectEqual(gesture.up(at: 0.1), [])
        }
    }

    func testMovementAccumulatesUntilTheDragDistance() {
        var gesture = pressed()
        expectEqual(gesture.move(dx: 0, dy: -60), [])
        expectEqual(gesture.move(dx: 0, dy: -59), [])
        expectEqual(gesture.move(dx: 0, dy: -1), [.action(.up)])
    }

    func testDragDistanceIsConfigurable() {
        var gesture = pressed(.init(dragDistance: 40))
        expectEqual(gesture.move(dx: 40, dy: 0), [.action(.right)])
    }

    func testDragBeforeHoldCancelsTheHold() {
        var gesture = pressed(.init(holdDelay: 0.4))
        expectEqual(gesture.move(dx: -130, dy: 0), [.action(.left)])
        expectEqual(gesture.advance(to: 1), [])
        expectEqual(gesture.up(at: 1), [])
    }

    func testStaleFirstReportIsDiscarded() {
        var gesture = pressed(.init(discardFirstReport: true))
        expectEqual(gesture.move(dx: .max, dy: .min), [])
        expectEqual(gesture.up(at: 0.1), [.action(.click)])
    }

    func testDuplicateDownDoesNotRestartThePress() {
        var gesture = pressed(.init(holdDelay: 0.4))
        _ = gesture.move(dx: 0, dy: -100)
        gesture.down(at: 5, options: .init(holdDelay: 0.4))
        expectEqual(gesture.move(dx: 0, dy: -20), [.action(.up)])
    }

    func testCancelSuppressesActions() {
        var gesture = pressed(.init(holdDelay: 0.4))
        expectEqual(gesture.cancel(), [])
        expectEqual(gesture.advance(to: 1), [])
        expectEqual(gesture.up(at: 1), [])
    }

    func testVerticalZoomBeginsReversesAndEnds() {
        var gesture = pressed(.init(verticalZoom: true))
        let first = gesture.move(dx: 0, dy: -100)
        expectEqual(first.first, .zoom(.begin))
        expectEqual(abs(amount(first) - 0.15) < 0.000001, true)
        let reverse = gesture.move(dx: 0, dy: 100)
        expectEqual(reverse.count, 1)
        expectEqual(amount(reverse) < 0, true)
        expectEqual(gesture.up(at: 1), [.zoom(.end)])
    }

    func testHorizontalDragStillWorksWithVerticalZoom() {
        var gesture = pressed(.init(verticalZoom: true))
        expectEqual(gesture.move(dx: 150, dy: 0), [.action(.right)])
        expectEqual(gesture.up(at: 1), [])
    }

    func testZoomSpeedAndLargePacketLimit() {
        var gesture = pressed(.init(verticalZoom: true, zoomSpeed: 2))
        expectEqual(abs(amount(gesture.move(dx: 0, dy: -40)) - 0.12) < 0.000001, true)
        expectEqual(amount(gesture.move(dx: 0, dy: .min)), 0.25)
        expectEqual(amount(gesture.move(dx: 0, dy: .max)), -0.25)
    }

    func testDragScrollTracksBothAxesAndEnds() {
        var gesture = pressed(.init(holdDelay: 0.4, dragScroll: true))
        expectEqual(gesture.move(dx: 4, dy: -3), [.pointer(dx: 4, dy: -3)])
        expectEqual(
            gesture.move(dx: 16, dy: -17),
            [.pointer(dx: 16, dy: -17), .scroll(.begin), .scroll(.move(x: 20, y: -20))])
        expectEqual(gesture.advance(to: 1), [])
        expectEqual(gesture.move(dx: -5, dy: 10), [.pointer(dx: -5, dy: 10), .scroll(.move(x: -5, y: 10))])
        expectEqual(gesture.up(at: 1), [.scroll(.end)])
        expectEqual(gesture.move(dx: 100, dy: 100), [])
    }

    func testDragScrollJitterStaleReportsAndCancel() {
        var gesture = pressed(.init(discardFirstReport: true, dragScroll: true))
        expectEqual(gesture.move(dx: .max, dy: .min), [])
        expectEqual(gesture.move(dx: 1, dy: 2), [.pointer(dx: 1, dy: 2)])
        expectEqual(gesture.up(at: 0.1), [.action(.click)])
        gesture = pressed(.init(dragScroll: true))
        _ = gesture.move(dx: 0, dy: 30)
        expectEqual(gesture.cancel(), [.scroll(.cancel)])
        expectEqual(gesture.up(at: 1), [])
    }

    func testDragScrollSpeedRetainsFractionalPixels() {
        var gesture = pressed(.init(dragScroll: true, scrollSpeed: 0.25))
        expectEqual(
            gesture.move(dx: 20, dy: 0),
            [.pointer(dx: 20, dy: 0), .scroll(.begin), .scroll(.move(x: 5, y: 0))])
        for _ in 0..<3 { expectEqual(gesture.move(dx: 1, dy: 0), [.pointer(dx: 1, dy: 0)]) }
        expectEqual(gesture.move(dx: 1, dy: 0), [.pointer(dx: 1, dy: 0), .scroll(.move(x: 1, y: 0))])
        expectEqual(
            gesture.move(dx: .min, dy: .max),
            [.pointer(dx: .min, dy: .max), .scroll(.move(x: -8192, y: 8191))])
    }

    func testDragScrollSpeedBoundsAndRestart() {
        for (speed, pixels) in [(Double.nan, Int32(20)), (.infinity, 20), (-1, 5), (100, 60)] {
            var options = ButtonGesture.Options(dragScroll: true)
            options.scrollSpeed = speed
            var gesture = pressed(options)
            expectEqual(
                gesture.move(dx: 20, dy: 0),
                [
                    .pointer(dx: 20, dy: 0), .scroll(.begin), .scroll(.move(x: pixels, y: 0)),
                ])
        }
        var gesture = pressed(.init(dragScroll: true, scrollSpeed: 0.25))
        _ = gesture.move(dx: 21, dy: 0)
        expectEqual(gesture.cancel(), [.scroll(.cancel)])
        gesture.down(at: 1, options: .init(dragScroll: true, scrollSpeed: 0.25))
        _ = gesture.move(dx: 20, dy: 0)
        expectEqual(gesture.move(dx: 3, dy: 0), [.pointer(dx: 3, dy: 0)])
    }

    func testDragScrollPointerContinuesAfterHold() {
        var gesture = pressed(.init(holdDelay: 0.4, dragScroll: true))
        expectEqual(gesture.advance(to: 1), [.action(.hold)])
        expectEqual(gesture.move(dx: 100, dy: 50), [.pointer(dx: 100, dy: 50)])
        expectEqual(gesture.move(dx: 0, dy: 0), [])
        expectEqual(gesture.up(at: 1), [])
        expectEqual(gesture.move(dx: 100, dy: 50), [])
    }

    func testCancelEndsAZoomWithoutAClick() {
        var gesture = pressed(.init(verticalZoom: true))
        _ = gesture.move(dx: 0, dy: -100)
        expectEqual(gesture.cancel(), [.zoom(.cancel)])
        expectEqual(gesture.up(at: 1), [])
    }
}
