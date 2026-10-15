import ForwardCore
import Foundation

final class HIDPacketTests {
    func testSignedRawMovementAndShortReports() {
        let bytes: [UInt8] = [0x11, 2, 9, 0x10, 0xFE, 0xD4, 1, 0xC2] + Array(repeating: 0, count: 12)
        let packet = HIDPacket.parse(bytes)!
        expectEqual(packet.movement?.dx, -300)
        expectEqual(packet.movement?.dy, 450)
        expectNil(HIDPacket.parse([0x10, 2, 9, 0x10, 0, 0, 0])?.movement)
    }
    func testShortFeatureDiscoveryPacket() {
        let bytes = HIDPacket.request(
            device: 2, feature: 0, function: 0,
            softwareID: 8, payload: [0x1B, 0x04])
        expectEqual(bytes, [0x10, 2, 0, 8, 0x1B, 4, 0])
        expectEqual(HIDPacket.parse(bytes)?.softwareID, 8)
    }
    func testLongForwardClaimOnlyUpdatesItsReportingFlags() {
        let bytes = HIDPacket.request(
            device: 1, feature: 12, function: 3,
            softwareID: 9, payload: [0, 86, 0x0B, 0, 86])
        expectEqual(bytes.count, 20)
        expectEqual(Array(bytes.prefix(9)), [0x11, 1, 12, 0x39, 0, 86, 11, 0, 86])
        expectEqual(HIDPacket.parse(bytes)?.function, 3)
    }
    func testTruncatedAndUnknownReportsRejected() {
        expectNil(HIDPacket.parse([]))
        expectNil(HIDPacket.parse([0x10, 1, 2, 0, 0, 86]))
        expectNil(HIDPacket.parse([0x11, 1, 2, 0, 0, 86, 0]))
        expectNil(HIDPacket.parse([0x99, 1, 2, 0, 0, 86, 0]))
    }
    func testBothErrorFormatsMatchOriginalRequest() {
        for report: UInt8 in [0x10, 0x11] {
            var bytes: [UInt8] = [report, 1, report == 0x10 ? 0x8F : 0xFF, 12, 0x39, 3, 0]
            if report == 0x11 { bytes += Array(repeating: 0, count: 13) }
            let packet = HIDPacket.parse(bytes)!
            expectEqual(packet.error?.feature, 12)
            expectEqual(packet.error?.address, 0x39)
            expectEqual(packet.error?.code, 3)
        }
    }
    func testSimultaneousControlsAndRelease() {
        var down: [UInt8] = [0x11, 1, 12, 0, 0, 86, 0, 195] + Array(repeating: 0, count: 12)
        expectEqual(HIDPacket.parse(down)?.pressedControls, [86, 195])
        down[5] = 0
        down[7] = 0
        expectEqual(HIDPacket.parse(down)?.pressedControls, [])
    }
}
