import ForwardCore

final class ThumbWheelTests {
    func testDirectionChangesIgnoreTouchAndProximity() {
        let state = ThumbWheelReporting([0, 6, 0])!
        expectEqual(state.inverted, false)
        expectEqual(state.parameters(inverted: true), [0, 1])
        expectEqual(state.parameters(inverted: false), [0, 0])
        expectEqual(state.bytes, [0, 0])
        expectEqual(state, ThumbWheelReporting([0, 0])!)
    }

    func testDirectionChangesPreserveDiversion() {
        let state = ThumbWheelReporting([0xA5, 0xFF])!
        expectEqual(state.inverted, true)
        expectEqual(state.parameters(inverted: false), [1, 0])
        expectEqual(state.parameters(inverted: true), [1, 1])
    }

    func testIncompleteSettingsAreRejected() {
        expectNil(ThumbWheelReporting([]))
        expectNil(ThumbWheelReporting([0]))
    }

    func testDiversionAndSignedRotation() {
        let state = ThumbWheelReporting([0xA4, 6])!
        expectEqual(state.parameters(inverted: true, diverted: true), [1, 1])
        expectEqual(ThumbWheelReporting([0xA5, 7])!.parameters(inverted: false, diverted: false), [0, 0])
        let packet = HIDPacket.parse([0x11, 2, 16, 0, 0xFF, 0xFE] + Array(repeating: 0, count: 14))!
        expectEqual(ThumbWheelScroll(packet)?.delta, -2)
        expectNil(ThumbWheelScroll(HIDPacket.parse([0x10, 2, 16, 0, 0, 1, 0])!))
    }

    func testResolutionAndDirection() {
        expectEqual(ThumbWheelResolution([0, 24, 1, 104, 1])?.stepsPerDelta, 24.0 / 360)
        expectEqual(ThumbWheelResolution([0, 24, 1, 104, 0x80])?.stepsPerDelta, -24.0 / 360)
        expectNil(ThumbWheelResolution([0, 24, 1, 104]))
        expectNil(ThumbWheelResolution([0, 0, 1, 104, 1]))
        expectNil(ThumbWheelResolution([0, 24, 0, 0, 1]))
    }

    func testLinearSpeedAndFractionalMovement() {
        var wheel = ThumbWheelInterpreter()
        var total: Int32 = 0
        for _ in 0..<120 {
            total += wheel.pixels(delta: 1, stepsPerDelta: 1.0 / 120, speed: 0.25, natural: true)
        }
        expectEqual(total, 10)
        wheel.cancel()
        for _ in 0..<20 {
            expectEqual(wheel.pixels(delta: 1, stepsPerDelta: 1, speed: 2, natural: true), 80)
        }
        expectEqual(wheel.pixels(delta: -1, stepsPerDelta: 1, speed: 2, natural: true), -80)
        expectEqual(wheel.pixels(delta: 1, stepsPerDelta: 1, speed: 2, natural: false), -80)
        expectEqual(wheel.pixels(delta: .max, stepsPerDelta: 65535, speed: 6, natural: true), .max)
    }
}
