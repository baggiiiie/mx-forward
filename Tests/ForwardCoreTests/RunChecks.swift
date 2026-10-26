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
        let packet = HIDPacketTests()
        packet.testSignedRawMovementAndShortReports()
        packet.testShortFeatureDiscoveryPacket()
        packet.testLongForwardClaimOnlyUpdatesItsReportingFlags()
        packet.testTruncatedAndUnknownReportsRejected()
        packet.testBothErrorFormatsMatchOriginalRequest()
        packet.testSimultaneousControlsAndRelease()
        let reporting = ControlReportingTests()
        reporting.testThumbClaimsAndRestoresRawMovement()
        reporting.testBackReportingPreservesRemapAndOptionalRawMovement()
        reporting.testTopButtonClaimsAndClearsRawMovement()
        reporting.testRejectsMissingRemapBytes()
        reporting.testRejectsAnotherControl()
        reporting.testPersistentDiversionIsNotOurTemporaryClaim()
        reporting.testClaimAndReleasePreserveFullRemapTarget()
        let gesture = ButtonGestureTests()
        gesture.testClickJitterAndIdle()
        gesture.testDoubleClickSuppressesSinglesAndStartsANewPair()
        gesture.testDoubleClickDeadlineUsesPressTimeAndFlushesALateTimer()
        gesture.testDoubleClickKeepsHoldDragAndCancellationSeparate()
        gesture.testWithoutHoldALongPressStillClicks()
        gesture.testHoldFiresOnceWithoutAClick()
        gesture.testShortPressWithHoldEnabledClicks()
        gesture.testLateTimerStillRecognizesHoldAtRelease()
        gesture.testAllDirectionsSuppressTheReleaseClick()
        gesture.testMovementAccumulatesUntilTheDragDistance()
        gesture.testDragDistanceIsConfigurable()
        gesture.testDragBeforeHoldCancelsTheHold()
        gesture.testStaleFirstReportIsDiscarded()
        gesture.testDuplicateDownDoesNotRestartThePress()
        gesture.testCancelSuppressesActions()
        gesture.testVerticalZoomBeginsReversesAndEnds()
        gesture.testHorizontalDragStillWorksWithVerticalZoom()
        gesture.testZoomSpeedAndLargePacketLimit()
        gesture.testCancelEndsAZoomWithoutAClick()
        gesture.testDragScrollTracksBothAxesAndEnds()
        gesture.testDragScrollJitterStaleReportsAndCancel()
        gesture.testDragScrollSpeedRetainsFractionalPixels()
        gesture.testDragScrollPointerContinuesAfterHold()
        gesture.testDragScrollSpeedBoundsAndRestart()
        let zoom = ZoomTests()
        zoom.testMacOSDecodesNativePinchPhases()
        zoom.testMacOSDecodesSmartZoom()
        let wheel = WheelTests()
        wheel.testWheelNotificationsDecodeSignedLimits()
        wheel.testHighAndLowResolutionNotchesHaveTheSameDistance()
        wheel.testSpeedAndDirection()
        wheel.testSlowHighResolutionMovementKeepsFractionalPixels()
        wheel.testReversalAndCancellationClearRemainders()
        wheel.testMaximumPacketAndSpeedDoNotOverflow()
        wheel.testAccelerationRespondsToSpeedRatherThanNotchCount()
        wheel.testAccelerationCanBeDisabledOrAdjusted()
        wheel.testIdleReversalAndCancellationRestorePrecision()
        wheel.testAccelerationIsConsistentAcrossWheelResolutions()
        wheel.testSlowHighResolutionScrollingStaysPreciseWithAcceleration()
        wheel.testInvalidOrRepeatedTimesAndZeroPacketsDoNotCauseJumps()
        wheel.testTinyReportIntervalsRemainFinite()
        wheel.testMaximumAccelerationAndPacketSizeStayBounded()
        let horizontal = ThumbWheelTests()
        horizontal.testDirectionChangesIgnoreTouchAndProximity()
        horizontal.testDirectionChangesPreserveDiversion()
        horizontal.testIncompleteSettingsAreRejected()
        horizontal.testDiversionAndSignedRotation()
        horizontal.testResolutionAndDirection()
        horizontal.testLinearSpeedAndFractionalMovement()
        if failureCount != 0 {
            print("\(failureCount) failures")
            exit(1)
        }
        print(
            "PASS: 59 scenarios (click, double click, hold, and drag gestures, zoom, wheel, HID++ reporting, native macOS events)"
        )
    }
}
