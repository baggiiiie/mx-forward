import ForwardCore

final class WheelTests {
    private func scroll(_ delta: Int16, highResolution: Bool = false) -> WheelScroll {
        let bits = UInt16(bitPattern: delta)
        return WheelScroll(
            HIDPacket.parse([
                0x10, 2, 15, 0, highResolution ? 0x10 : 0,
                UInt8(bits >> 8), UInt8(bits & 255),
            ])!)!
    }

    func testWheelNotificationsDecodeSignedLimits() {
        expectEqual(scroll(.min).delta, .min)
        expectEqual(scroll(.max, highResolution: true).delta, .max)
        expectEqual(scroll(0, highResolution: true).highResolution, true)
        expectNil(WheelScroll(HIDPacket.parse([0x10, 2, 15, 0x10, 0, 0, 1])!))
        expectNil(WheelScroll(HIDPacket.parse([0x10, 2, 15, 0x08, 0, 0, 1])!))
    }

    func testHighAndLowResolutionNotchesHaveTheSameDistance() {
        var wheel = WheelInterpreter()
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 1, natural: false), 40)
        expectEqual(
            wheel.pixels(for: scroll(15, highResolution: true), multiplier: 15, speed: 1, natural: false), 40)
    }

    func testSpeedAndDirection() {
        var wheel = WheelInterpreter()
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 2, natural: false), 80)
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 0.25, natural: true), -10)
        expectEqual(wheel.pixels(for: scroll(-1), multiplier: 15, speed: 1, natural: true), 40)
        expectEqual(wheel.pixels(for: scroll(0), multiplier: 15, speed: 1, natural: true), 0)
    }

    func testSlowHighResolutionMovementKeepsFractionalPixels() {
        var wheel = WheelInterpreter()
        var total: Int32 = 0
        for _ in 0..<128 {
            total += wheel.pixels(
                for: scroll(1, highResolution: true), multiplier: 128, speed: 0.25, natural: false)
        }
        expectEqual(total, 10)
    }

    func testReversalAndCancellationClearRemainders() {
        var wheel = WheelInterpreter()
        expectEqual(
            wheel.pixels(for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false), 0
        )
        expectEqual(
            wheel.pixels(for: scroll(-1, highResolution: true), multiplier: 16, speed: 0.25, natural: false),
            0)
        _ = wheel.pixels(for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false)
        wheel.cancel()
        expectEqual(
            wheel.pixels(for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false), 0
        )
    }

    func testMaximumPacketAndSpeedDoNotOverflow() {
        var wheel = WheelInterpreter()
        expectEqual(wheel.pixels(for: scroll(.min), multiplier: 1, speed: 6, natural: true), 7_864_320)
        expectEqual(wheel.pixels(for: scroll(.max), multiplier: 1, speed: 6, natural: false), 7_864_080)
    }
}
