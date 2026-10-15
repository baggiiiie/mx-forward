import ForwardCore

final class ThumbWheelTests {
    func testDirectionChangesPreserveNativeReportingAndTouchFlags() {
        let state = ThumbWheelReporting([0, 6, 0])!
        expectEqual(state.inverted, false)
        expectEqual(state.parameters(inverted: true), [0, 7])
        expectEqual(state.parameters(inverted: false), [0, 6])
        expectEqual(state.bytes, [0, 6])
    }

    func testReversingAnAlreadyInvertedWheelPreservesOtherBits() {
        let state = ThumbWheelReporting([0xA5, 0xFF])!
        expectEqual(state.inverted, true)
        expectEqual(state.parameters(inverted: false), [0xA5, 0xFE])
        expectEqual(state.parameters(inverted: true), [0xA5, 0xFF])
    }

    func testIncompleteSettingsAreRejected() {
        expectNil(ThumbWheelReporting([]))
        expectNil(ThumbWheelReporting([0]))
    }
}
