import ForwardCore

final class SideButtonTests {
    func testPlainClicksNavigateOnceOnRelease() {
        var buttons = SideButtonInterpreter()
        for (button, action) in [
            (MouseControl.back, SideButtonInterpreter.Action.back), (.forward, .forward),
        ] {
            expectNil(buttons.update(button, down: false, at: 0))
            expectNil(buttons.update(button, down: true, at: 1))
            expectEqual(buttons.update(button, down: false, at: 1.1), action)
            expectNil(buttons.update(button, down: false, at: 1.2))
        }
    }

    func testPlainForwardHasNoHoldAction() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.forward, down: true, at: 0)
        expectNil(buttons.advance(to: 100))
        expectEqual(buttons.update(.forward, down: false, at: 101), .forward)
    }

    func testRepeatedReportsDoNotResetTheHold() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.forward, down: true, at: 0, holdThreshold: 0.4)
        expectNil(buttons.update(.forward, down: true, at: 0.3, holdThreshold: 0.4))
        expectEqual(buttons.advance(to: 0.4), .shortcut)
        expectNil(buttons.advance(to: 0.8))
        expectNil(buttons.update(.forward, down: false, at: 1))
    }

    func testShortForwardPressStillNavigatesWithHoldEnabled() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.forward, down: true, at: 0, holdThreshold: 0.4)
        expectNil(buttons.advance(to: 0.2))
        expectEqual(buttons.update(.forward, down: false, at: 0.3), .forward)
    }

    func testDelayedTimerDoesNotTurnAHoldIntoNavigation() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.forward, down: true, at: 0, holdThreshold: 0.4)
        expectEqual(buttons.update(.forward, down: false, at: 0.4), .shortcut)
        expectNil(buttons.advance(to: 1))
    }

    func testBackDoesNotInterruptAForwardHold() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.forward, down: true, at: 0, holdThreshold: 0.4)
        _ = buttons.update(.back, down: true, at: 0.1)
        expectEqual(buttons.update(.back, down: false, at: 0.2), .back)
        expectEqual(buttons.isPressed(.forward), true)
        expectEqual(buttons.advance(to: 0.4), .shortcut)
        expectNil(buttons.update(.forward, down: false, at: 0.5))
    }

    func testCancelClearsBothButtonsWithoutAnAction() {
        var buttons = SideButtonInterpreter()
        _ = buttons.update(.back, down: true, at: 0)
        _ = buttons.update(.forward, down: true, at: 0, holdThreshold: 0.4)
        buttons.cancel()
        expectEqual(buttons.isPressed(.back), false)
        expectEqual(buttons.isPressed(.forward), false)
        expectNil(buttons.advance(to: 1))
        expectNil(buttons.update(.back, down: false, at: 1))
        expectNil(buttons.update(.forward, down: false, at: 1))
        _ = buttons.update(.forward, down: true, at: 2)
        expectEqual(buttons.update(.forward, down: false, at: 2.1), .forward)
    }

    func testTopButtonIsIgnored() {
        var buttons = SideButtonInterpreter()
        expectNil(buttons.update(.top, down: true, at: 0, holdThreshold: 0.4))
        expectEqual(buttons.isPressed(.top), false)
        expectNil(buttons.advance(to: 1))
        expectNil(buttons.update(.top, down: false, at: 1))
    }
}
