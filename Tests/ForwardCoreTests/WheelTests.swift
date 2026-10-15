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
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 1, natural: false, at: 0), 40)
        expectEqual(
            wheel.pixels(
                for: scroll(15, highResolution: true), multiplier: 15, speed: 1, natural: false, at: 0), 40)
    }

    func testSpeedAndDirection() {
        var wheel = WheelInterpreter()
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 2, natural: false, at: 0), 80)
        expectEqual(wheel.pixels(for: scroll(1), multiplier: 15, speed: 0.25, natural: true, at: 0), -10)
        expectEqual(wheel.pixels(for: scroll(-1), multiplier: 15, speed: 1, natural: true, at: 0), 40)
        expectEqual(wheel.pixels(for: scroll(0), multiplier: 15, speed: 1, natural: true, at: 0), 0)
    }

    func testSlowHighResolutionMovementKeepsFractionalPixels() {
        var wheel = WheelInterpreter()
        var total: Int32 = 0
        for _ in 0..<128 {
            total += wheel.pixels(
                for: scroll(1, highResolution: true), multiplier: 128, speed: 0.25, natural: false, at: 0)
        }
        expectEqual(total, 10)
    }

    func testReversalAndCancellationClearRemainders() {
        var wheel = WheelInterpreter()
        expectEqual(
            wheel.pixels(
                for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false, at: 0), 0
        )
        expectEqual(
            wheel.pixels(
                for: scroll(-1, highResolution: true), multiplier: 16, speed: 0.25, natural: false, at: 0),
            0)
        _ = wheel.pixels(
            for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false, at: 0)
        wheel.cancel()
        expectEqual(
            wheel.pixels(
                for: scroll(1, highResolution: true), multiplier: 16, speed: 0.25, natural: false, at: 0), 0
        )
    }

    func testMaximumPacketAndSpeedDoNotOverflow() {
        var wheel = WheelInterpreter()
        expectEqual(wheel.pixels(for: scroll(.min), multiplier: 1, speed: 6, natural: true, at: 0), 7_864_320)
        expectEqual(
            wheel.pixels(for: scroll(.max), multiplier: 1, speed: 6, natural: false, at: 0), 7_864_080)
    }

    private func distance(interval: Double, strength: Double, highResolution: Bool = false) -> Int32 {
        var wheel = WheelInterpreter()
        let packets = highResolution ? 1500 : 100
        var total: Int32 = 0
        for index in 0..<packets {
            total += wheel.pixels(
                for: scroll(1, highResolution: highResolution), multiplier: 15, speed: 1,
                natural: false, acceleration: strength,
                at: Double(index) * interval / (highResolution ? 15 : 1))
        }
        return total
    }

    func testAccelerationRespondsToSpeedRatherThanNotchCount() {
        let slow = distance(interval: 0.2, strength: 1)
        let medium = distance(interval: 0.05, strength: 1)
        let fast = distance(interval: 0.01, strength: 1)
        expectEqual(slow, 4000)
        expectEqual(medium > slow && fast > medium, true)
        expectEqual(fast <= 20_000, true)
    }

    func testAccelerationCanBeDisabledOrAdjusted() {
        let off = distance(interval: 0.01, strength: 0)
        let weak = distance(interval: 0.01, strength: 0.5)
        let normal = distance(interval: 0.01, strength: 1)
        let strong = distance(interval: 0.01, strength: 2)
        expectEqual(off, 4000)
        expectEqual(off < weak && weak < normal && normal < strong, true)
        expectEqual(strong <= 36_000, true)
    }

    func testIdleReversalAndCancellationRestorePrecision() {
        var wheel = WheelInterpreter()
        var last: Int32 = 0
        for index in 0...20 {
            last = wheel.pixels(
                for: scroll(1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: Double(index) * 0.01)
        }
        expectEqual(last > 40, true)
        expectEqual(
            wheel.pixels(
                for: scroll(-1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: 0.21), -40)
        for index in 22...40 {
            _ = wheel.pixels(
                for: scroll(-1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: Double(index) * 0.01)
        }
        expectEqual(
            wheel.pixels(
                for: scroll(-1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: 0.8), -40)
        wheel.cancel()
        expectEqual(
            wheel.pixels(
                for: scroll(-1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: 0.81), -40)
    }

    func testAccelerationIsConsistentAcrossWheelResolutions() {
        for interval in [0.02, 0.05, 0.2] {
            let low = distance(interval: interval, strength: 1)
            let high = distance(interval: interval, strength: 1, highResolution: true)
            expectEqual(abs(Double(high - low)) / Double(low) < 0.03, true)
        }
    }

    func testSlowHighResolutionScrollingStaysPreciseWithAcceleration() {
        var wheel = WheelInterpreter()
        var total: Int32 = 0
        for index in 0..<128 {
            total += wheel.pixels(
                for: scroll(1, highResolution: true), multiplier: 128, speed: 0.25,
                natural: false, acceleration: 1, at: Double(index) / 640)
        }
        expectEqual(total, 10)
    }

    func testInvalidOrRepeatedTimesAndZeroPacketsDoNotCauseJumps() {
        var wheel = WheelInterpreter()
        for time: Double in [1, 0.9, .nan, .infinity, 2, 2, 2.1] {
            expectEqual(
                wheel.pixels(
                    for: scroll(1), multiplier: 15, speed: 1,
                    natural: false, acceleration: 1, at: time), 40)
        }
        expectEqual(
            wheel.pixels(
                for: scroll(0), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: 2.199), 0)
        expectEqual(
            wheel.pixels(
                for: scroll(1), multiplier: 15, speed: 1,
                natural: false, acceleration: 1, at: 2.2), 40)
    }

    func testTinyReportIntervalsRemainFinite() {
        var wheel = WheelInterpreter()
        _ = wheel.pixels(
            for: scroll(1), multiplier: 15, speed: 1,
            natural: false, acceleration: 2, at: 0)
        let pixels = wheel.pixels(
            for: scroll(1), multiplier: 15, speed: 1,
            natural: false, acceleration: 2, at: .leastNonzeroMagnitude)
        expectEqual((40...360).contains(pixels), true)
    }

    func testMaximumAccelerationAndPacketSizeStayBounded() {
        var wheel = WheelInterpreter()
        _ = wheel.pixels(
            for: scroll(.min), multiplier: 1, speed: 6,
            natural: true, acceleration: 2, at: 0)
        expectEqual(
            wheel.pixels(
                for: scroll(.min), multiplier: 1, speed: 6,
                natural: true, acceleration: 2, at: 0.01), 70_778_880)
        expectEqual(
            wheel.pixels(
                for: scroll(.max), multiplier: 1, speed: 6,
                natural: false, acceleration: 2, at: 0.02), 7_864_080)
        expectEqual(
            wheel.pixels(
                for: scroll(.max), multiplier: 1, speed: 6,
                natural: false, acceleration: 2, at: 0.03), 70_776_720)
    }

}
