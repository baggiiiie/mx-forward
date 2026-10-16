import ForwardCore

final class ControlReportingTests {
    func testThumbClaimsAndRestoresRawMovement() {
        let settings = ControlReporting([0, 195, 0, 0, 195], control: .thumb)!
        expectEqual(settings.parameters(divert: true, rawMovement: true), [0, 195, 0x3B, 0, 195])
        expectEqual(settings.parameters(divert: true), [0, 195, 0x2B, 0, 195])
        expectEqual(settings.parameters(divert: false, rawMovement: true), [0, 195, 0x2A, 0, 195])
    }
    func testBackReportingPreservesRemapAndOptionalRawMovement() {
        let settings = ControlReporting([0, 83, 0x31, 0xAB, 0xCD], control: .back)!
        expectEqual(settings.parameters(divert: true), [0, 83, 0x2B, 0xAB, 0xCD])
        expectEqual(settings.parameters(divert: true, rawMovement: true), [0, 83, 0x3B, 0xAB, 0xCD])
        expectEqual(settings.parameters(divert: false), [0, 83, 0x2A, 0xAB, 0xCD])
        expectNil(ControlReporting([0, 86, 1, 0, 86], control: .back))
    }
    func testTopButtonClaimsAndClearsRawMovement() {
        let settings = ControlReporting([0, 196, 0x11, 0, 196], control: .top)!
        expectEqual(settings.rawMovement, true)
        expectEqual(settings.parameters(divert: true, rawMovement: true), [0, 196, 0x3B, 0, 196])
        expectEqual(settings.parameters(divert: false), [0, 196, 0x2A, 0, 196])
        expectNil(ControlReporting([0, 86, 1, 0, 86], control: .top))
    }
    func testRejectsMissingRemapBytes() {
        let payload: [UInt8] = [0, 86, 1, 0, 86]
        for length in 0..<5 {
            expectNil(ControlReporting(Array(payload.prefix(length)), control: .forward))
        }
    }

    func testRejectsAnotherControl() {
        expectNil(ControlReporting([0, 83, 1, 0, 83], control: .forward))
    }

    func testPersistentDiversionIsNotOurTemporaryClaim() {
        expectEqual(ControlReporting([0, 86, 1, 0, 86], control: .forward)?.temporarilyDiverted, true)
        expectEqual(ControlReporting([0, 86, 5, 0, 86], control: .forward)?.temporarilyDiverted, false)
        expectEqual(ControlReporting([0, 86, 0, 0, 86], control: .forward)?.temporarilyDiverted, false)
    }

    func testClaimAndReleasePreserveFullRemapTarget() {
        let settings = ControlReporting([0, 86, 0x31, 0xAB, 0xCD], control: .forward)!
        expectEqual(settings.remap, 0xABCD)
        expectEqual(settings.parameters(divert: true), [0, 86, 0x2B, 0xAB, 0xCD])
        expectEqual(settings.parameters(divert: false), [0, 86, 0x2A, 0xAB, 0xCD])
    }
}
