import Foundation

// Runs without XCTest, which is not included with Command Line Tools.
private var failureCount = 0
func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T,
    file: StaticString = #filePath, line: UInt = #line
) {
    if actual != expected {
        failureCount += 1
        print("FAIL \(file):\(line): expected \(expected), got \(actual)")
    }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil {
        failureCount += 1
        print("FAIL \(file):\(line): expected nil, got \(String(describing: value))")
    }
}

@main
enum RunChecks {
    static func main() {
        let press = PressInterpreterTests()
        press.testPressedStateLastsUntilReleaseOrCancel()
        press.testShortPressOnlyForwardsOnRelease()
        press.testHoldFiresExactlyOnceWithoutForward()
        press.testLateTimerStillRecognizesHoldAtRelease()
        press.testExactBoundaryIsAHold()
        press.testDuplicateDownDoesNotResetDeadline()
        press.testPauseDisconnectOrSleepCancelsPendingPress()
        press.testConsecutiveClicksAndHoldsRemainIndependent()
        let packet = HIDPacketTests()
        packet.testShortFeatureDiscoveryPacket()
        packet.testLongForwardClaimOnlyUpdatesItsReportingFlags()
        packet.testTruncatedAndUnknownReportsRejected()
        packet.testBothErrorFormatsMatchOriginalRequest()
        packet.testSimultaneousControlsAndRelease()
        let reporting = ForwardReportingTests()
        reporting.testRejectsMissingRemapBytes()
        reporting.testRejectsAnotherControl()
        reporting.testPersistentDiversionIsNotOurTemporaryClaim()
        reporting.testClaimAndReleasePreserveFullRemapTarget()
        if failureCount != 0 {
            print("\(failureCount) failures")
            exit(1)
        }
        print("PASS: 17 core scenarios (click/hold timing, cancellation, packets, reporting state)")
    }
}
