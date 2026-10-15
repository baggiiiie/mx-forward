import ForwardCore

final class MovementButtonTests {
    func testDuplicateEdgesAndSingleButtonRelease() {
        var buttons = MovementButtons()
        expectNil(buttons.update(.thumb, down: false))
        expectEqual(buttons.update(.thumb, down: true), .begin(.thumb))
        expectNil(buttons.update(.thumb, down: true))
        expectEqual(buttons.active, .thumb)
        expectEqual(buttons.update(.thumb, down: false), .finish(.thumb))
        expectNil(buttons.active)
    }

    func testOverlapCancelsUntilBothButtonsAreReleased() {
        for first in [MouseControl.top, .thumb] {
            let second: MouseControl = first == .top ? .thumb : .top
            for releaseFirst in [first, second] {
                var buttons = MovementButtons()
                _ = buttons.update(first, down: true)
                expectEqual(buttons.update(second, down: true), .cancel(first))
                expectNil(buttons.active)
                expectNil(buttons.update(releaseFirst, down: false))
                let remaining = releaseFirst == first ? second : first
                expectNil(buttons.update(remaining, down: false))
                expectEqual(buttons.update(first, down: true), .begin(first))
            }
        }
    }

    func testRepressingDuringOverlapDoesNotStartAnotherGesture() {
        var buttons = MovementButtons()
        _ = buttons.update(.top, down: true)
        _ = buttons.update(.thumb, down: true)
        _ = buttons.update(.top, down: false)
        expectNil(buttons.update(.top, down: true))
        expectNil(buttons.active)
    }

    func testCancelClearsOverlapAndSideButtonsAreIgnored() {
        var buttons = MovementButtons()
        expectNil(buttons.update(.forward, down: true))
        expectNil(buttons.update(.back, down: true))
        _ = buttons.update(.top, down: true)
        _ = buttons.update(.thumb, down: true)
        buttons.cancel()
        expectEqual(buttons.update(.thumb, down: true), .begin(.thumb))
    }
}
