import ForwardCore

final class ThumbGestureTests {
    func testClickJitterAndIdle() {
        var gesture = ThumbGestureInterpreter()
        expectNil(gesture.up())
        expectNil(gesture.move(dx: 500, dy: 500))
        gesture.down()
        expectNil(gesture.move(dx: 4, dy: -5))
        expectEqual(gesture.up(), .missionControl)
        expectNil(gesture.up())
    }

    func testAllDirectionsSuppressTheReleaseClick() {
        let cases: [(Int16, Int16, ThumbGestureInterpreter.Action)] = [
            (-150, 10, .desktopLeft), (150, -10, .desktopRight),
            (10, -150, .missionControl), (-10, 150, .appExpose),
        ]
        for (dx, dy, action) in cases {
            var gesture = ThumbGestureInterpreter()
            gesture.down()
            expectEqual(gesture.move(dx: dx, dy: dy), action)
            expectNil(gesture.up())
        }
    }

    func testMovementAccumulatesUntilThreshold() {
        var gesture = ThumbGestureInterpreter()
        gesture.down()
        expectNil(gesture.move(dx: -50, dy: 5))
        expectNil(gesture.move(dx: -50, dy: 5))
        expectEqual(gesture.move(dx: -20, dy: 5), .desktopLeft)
    }

    func testSensitivityChangesRequiredDistance() {
        var gesture = ThumbGestureInterpreter()
        gesture.down(sensitivity: 2)
        expectNil(gesture.move(dx: 59, dy: 0))
        expectEqual(gesture.move(dx: 1, dy: 0), .desktopRight)
    }

    func testStaleFirstReportIsDiscarded() {
        var gesture = ThumbGestureInterpreter()
        gesture.down(discardFirstReport: true)
        expectNil(gesture.move(dx: .min, dy: .max))
        expectEqual(gesture.up(), .missionControl)
        gesture.down(discardFirstReport: true)
        expectNil(gesture.move(dx: .max, dy: .min))
        expectEqual(gesture.move(dx: 0, dy: 150), .appExpose)
    }

    func testDuplicateDownDoesNotResetMovement() {
        var gesture = ThumbGestureInterpreter()
        gesture.down()
        _ = gesture.move(dx: 100, dy: 0)
        gesture.down()
        expectEqual(gesture.move(dx: 20, dy: 0), .desktopRight)
    }

    func testOnlyOneActionPerPress() {
        var gesture = ThumbGestureInterpreter()
        gesture.down()
        expectEqual(gesture.move(dx: -200, dy: 0), .desktopLeft)
        expectNil(gesture.move(dx: 0, dy: -200))
        expectNil(gesture.up())
        gesture.down()
        expectEqual(gesture.move(dx: 0, dy: 200), .appExpose)
    }

    func testCancelSuppressesActionsAndClearsState() {
        var gesture = ThumbGestureInterpreter()
        gesture.down()
        gesture.cancel()
        expectNil(gesture.up())
        expectNil(gesture.move(dx: 200, dy: 0))
        gesture.down()
        expectEqual(gesture.up(), .missionControl)
    }
}
