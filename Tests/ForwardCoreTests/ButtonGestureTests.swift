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

    func testWithoutHoldALongPressStillClicks() {
        var gesture = pressed()
        expectNil(gesture.advance(to: 10))
        expectEqual(gesture.up(at: 10), [.action(.click)])
    }

    func testHoldFiresOnceWithoutAClick() {
        var gesture = pressed(.init(holdDelay: 0.4), at: 1)
        expectNil(gesture.advance(to: 1.39))
        expectEqual(gesture.advance(to: 1.4), .action(.hold))
        expectNil(gesture.advance(to: 2))
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
        expectNil(gesture.advance(to: 1))
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
        expectNil(gesture.advance(to: 1))
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

    func testCancelEndsAZoomWithoutAClick() {
        var gesture = pressed(.init(verticalZoom: true))
        _ = gesture.move(dx: 0, dy: -100)
        expectEqual(gesture.cancel(), [.zoom(.cancel)])
        expectEqual(gesture.up(at: 1), [])
    }
}
