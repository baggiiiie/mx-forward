import ForwardCore

final class ForwardReportingTests {
    func testRejectsMissingRemapBytes() {
        let payload: [UInt8] = [0, 86, 1, 0, 86]
        for length in 0..<5 {
            expectNil(ForwardReporting(Array(payload.prefix(length))))
        }
    }

    func testRejectsAnotherControl() {
        expectNil(ForwardReporting([0, 83, 1, 0, 83]))
    }

    func testPersistentDiversionIsNotOurTemporaryClaim() {
        expectEqual(ForwardReporting([0, 86, 1, 0, 86])?.temporarilyDiverted, true)
        expectEqual(ForwardReporting([0, 86, 5, 0, 86])?.temporarilyDiverted, false)
        expectEqual(ForwardReporting([0, 86, 0, 0, 86])?.temporarilyDiverted, false)
    }

    func testClaimAndReleasePreserveFullRemapTarget() {
        let settings = ForwardReporting([0, 86, 0x31, 0xAB, 0xCD])!
        expectEqual(settings.remap, 0xABCD)
        expectEqual(settings.parameters(divert: true), [0, 86, 0x0B, 0xAB, 0xCD])
        expectEqual(settings.parameters(divert: false), [0, 86, 0x0A, 0xAB, 0xCD])
    }
}
