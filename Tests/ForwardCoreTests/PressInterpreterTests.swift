import ForwardCore
import Foundation

final class PressInterpreterTests {
    func testPressedStateLastsUntilReleaseOrCancel() {
        var machine = PressInterpreter()
        expectEqual(machine.isPressed, false)
        machine.down(at: 0, threshold: 0.4)
        expectEqual(machine.isPressed, true)
        expectEqual(machine.advance(to: 0.4), .shortcut)
        expectEqual(machine.isPressed, true)
        expectNil(machine.up(at: 0.5))
        expectEqual(machine.isPressed, false)
        machine.down(at: 1, threshold: 0.4)
        machine.cancel()
        expectEqual(machine.isPressed, false)
    }
    func testShortPressOnlyForwardsOnRelease() {
        var machine = PressInterpreter()
        machine.down(at: 10, threshold: 0.4)
        expectNil(machine.advance(to: 10.2))
        expectEqual(machine.up(at: 10.3), .forward)
        expectNil(machine.advance(to: 11))
    }
    func testHoldFiresExactlyOnceWithoutForward() {
        var machine = PressInterpreter()
        machine.down(at: 10, threshold: 0.4)
        expectEqual(machine.advance(to: 10.4), .shortcut)
        expectNil(machine.advance(to: 11))
        expectNil(machine.up(at: 12))
        expectNil(machine.up(at: 12.1))
    }
    func testLateTimerStillRecognizesHoldAtRelease() {
        var machine = PressInterpreter()
        machine.down(at: 0, threshold: 0.4)
        expectEqual(machine.up(at: 0.6), .shortcut)
        expectNil(machine.advance(to: 1))
    }
    func testExactBoundaryIsAHold() {
        var machine = PressInterpreter()
        machine.down(at: 0, threshold: 0.4)
        expectEqual(machine.up(at: 0.4), .shortcut)
    }
    func testDuplicateDownDoesNotResetDeadline() {
        var machine = PressInterpreter()
        machine.down(at: 0, threshold: 0.4)
        machine.down(at: 0.3, threshold: 0.4)
        expectEqual(machine.advance(to: 0.4), .shortcut)
    }
    func testPauseDisconnectOrSleepCancelsPendingPress() {
        var machine = PressInterpreter()
        machine.down(at: 0, threshold: 0.4)
        machine.cancel()
        expectNil(machine.advance(to: 1))
        expectNil(machine.up(at: 1))
        machine.down(at: 2, threshold: 0.4)
        expectEqual(machine.up(at: 2.1), .forward)
    }
    func testConsecutiveClicksAndHoldsRemainIndependent() {
        var machine = PressInterpreter()
        machine.down(at: 0, threshold: 0.4)
        expectEqual(machine.up(at: 0.1), .forward)
        machine.down(at: 0.2, threshold: 0.4)
        expectEqual(machine.up(at: 0.3), .forward)
        machine.down(at: 1, threshold: 0.4)
        expectEqual(machine.advance(to: 1.5), .shortcut)
        expectNil(machine.up(at: 2))
        machine.down(at: 3, threshold: 0.8)
        expectEqual(machine.up(at: 3.5), .forward)
    }
}
