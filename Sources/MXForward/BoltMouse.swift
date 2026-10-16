import ForwardCore
import Foundation
import IOKit.hid

enum MouseError: LocalizedError {
    case message(String)
    case timeout
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .timeout: return "Mouse response timed out"
        }
    }
}

/// Talks to the Bolt receiver on the main run loop.
@MainActor
final class BoltMouse {
    struct Connection: Equatable {
        let endpoint: UInt
        let slot: UInt8
        let feature: UInt8
        let discardFirstMovement: Bool
        let availableControls: Set<MouseControl>
        /// Buttons that can report movement while held.
        let movementControls: Set<MouseControl>
    }
    private struct Pending {
        let id: UUID
        let endpoint: UInt
        let device: UInt8
        let feature: UInt8
        let address: UInt8
        let continuation: CheckedContinuation<HIDPacket, Error>
    }
    private var manager: IOHIDManager?
    private var devices: [UInt: IOHIDDevice] = [:]
    private var pending: [UUID: Pending] = [:]
    private var probes: [UInt: Task<Void, Never>] = [:]
    private var probeGenerations: [UInt: UUID] = [:]
    private var nextSoftwareID: UInt8 = 8
    private(set) var connection: Connection?
    private var claims: [MouseControl: ControlReporting] = [:]
    private var movementClaims = Set<MouseControl>()
    private struct WheelClaim {
        let feature: UInt8
        let shiftFeature: UInt8
        let multiplier: UInt8
        let originalMode: UInt8
        let originalShift: [UInt8]
        let desiredMode: UInt8
        let desiredShift: [UInt8]?
    }
    private var wheelClaim: WheelClaim?
    private struct HorizontalClaim {
        let feature: UInt8
        let original: ThumbWheelReporting
        let inverted: Bool
    }
    private var horizontalClaim: HorizontalClaim?
    var claimed: Bool { !claims.isEmpty || wheelClaim != nil || horizontalClaim != nil }
    var onStatus: (String) -> Void = { _ in }
    var onPress: (MouseControl, Bool) -> Void = { _, _ in }
    var onMovement: (Int16, Int16) -> Void = { _, _ in }
    var onScroll: (WheelScroll, UInt8) -> Void = { _, _ in }
    var onDisconnect: () -> Void = {}
    var onLog: (String) -> Void = { _ in }

    func start() throws {
        if manager != nil {
            rescan()
            return
        }
        let value = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        manager = value
        IOHIDManagerSetDeviceMatching(
            value,
            [
                kIOHIDVendorIDKey: 0x046D,
                kIOHIDProductIDKey: 0xC548,
                kIOHIDPrimaryUsagePageKey: 0xFF00,
                kIOHIDPrimaryUsageKey: 1,
            ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            value,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<BoltMouse>.fromOpaque(context).takeUnretainedValue().matched(device)
                }
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            value,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<BoltMouse>.fromOpaque(context).takeUnretainedValue().removed(device)
                }
            }, context)
        IOHIDManagerRegisterInputReportCallback(
            value,
            { context, _, sender, _, reportID, bytes, length in
                guard let context, let sender, reportID == 0x10 || reportID == 0x11 else { return }
                var data = Array(UnsafeBufferPointer(start: bytes, count: length))
                if data.first != UInt8(reportID) { data.insert(UInt8(reportID), at: 0) }
                MainActor.assumeIsolated {
                    Unmanaged<BoltMouse>.fromOpaque(context).takeUnretainedValue()
                        .received(data, endpoint: UInt(bitPattern: sender))
                }
            }, context)
        IOHIDManagerScheduleWithRunLoop(value, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(value, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(value, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(value, 0)
            manager = nil
            throw MouseError.message(
                String(
                    format:
                        "Cannot open Bolt receiver (0x%08X). Check Input Monitoring, then restart MX Forward.",
                    result))
        }
        onStatus("Looking for your MX Master 3S…")
    }

    func rescan() {
        guard !claimed, connection == nil else { return }
        for key in devices.keys where probes[key] == nil { beginProbe(key) }
    }

    func forgetConnection() {
        guard !claimed else { return }
        for task in probes.values { task.cancel() }
        probes.removeAll()
        probeGenerations.removeAll()
        connection = nil
    }

    private func key(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func matched(_ device: IOHIDDevice) {
        let id = key(device)
        guard devices[id] == nil else { return }
        let result = IOHIDDeviceOpen(device, 0)
        guard result == kIOReturnSuccess else {
            onStatus(String(format: "Bolt receiver unavailable (0x%08X). Check Input Monitoring.", result))
            return
        }
        devices[id] = device
        onLog("Bolt receiver connected")
        beginProbe(id)
    }

    private func beginProbe(_ id: UInt) {
        let generation = UUID()
        probeGenerations[id] = generation
        probes[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.probeGenerations[id] == generation {
                    self.probes[id] = nil
                    self.probeGenerations[id] = nil
                }
            }
            for slot in UInt8(1)...6 {
                guard !Task.isCancelled, self.connection == nil, self.devices[id] != nil else { return }
                do {
                    let ping = try await self.request(id, slot, 0, 1, [0, 0, 0xA7])
                    guard ping.payload.count >= 3, ping.payload[0] >= 2, ping.payload[2] == 0xA7 else {
                        continue
                    }
                    let nameFeature = try await self.feature(0x0005, id, slot)
                    let size = try await self.request(id, slot, nameFeature, 0)
                    let length = min(Int(size.payload[0]), 80)
                    var bytes: [UInt8] = []
                    while bytes.count < length {
                        let chunk = try await self.request(id, slot, nameFeature, 1, [UInt8(bytes.count)])
                        bytes += chunk.payload.prefix(min(16, length - bytes.count))
                    }
                    let name = String(decoding: bytes, as: UTF8.self)
                    guard name.localizedCaseInsensitiveContains("MX Master 3S") else { continue }
                    let special = try await self.request(id, slot, 0, 0, [0x1B, 0x04])
                    let index = special.payload[0]
                    guard index != 0 else { throw MouseError.message("Missing button control feature") }
                    let count = try await self.request(id, slot, index, 0)
                    var availableControls = Set<MouseControl>()
                    var movementControls = Set<MouseControl>()
                    for position in 0..<min(Int(count.payload[0]), 64) {
                        let info = try await self.request(id, slot, index, 1, [UInt8(position)])
                        guard info.payload.count >= 5, info.payload[4] & 0x20 != 0,
                            let control = MouseControl(
                                rawValue: UInt16(info.payload[0]) << 8 | UInt16(info.payload[1]))
                        else { continue }
                        availableControls.insert(control)
                        if info.payload.count >= 9, info.payload[8] & 1 != 0 {
                            movementControls.insert(control)
                        }
                    }
                    guard availableControls.contains(.forward) else {
                        throw MouseError.message("Forward button does not support software control.")
                    }
                    guard self.connection == nil else { return }
                    self.connection = Connection(
                        endpoint: id, slot: slot, feature: index,
                        discardFirstMovement: special.payload[2] >= 5, availableControls: availableControls,
                        movementControls: movementControls)
                    self.onStatus("\(name) connected · Bolt slot \(slot)")
                    self.onLog(
                        "Available buttons: \(availableControls.sorted().map(\.name).joined(separator: ", "))"
                    )
                    self.onLog(
                        "Button feature version \(special.payload[2]); initial movement filter \(special.payload[2] >= 5 ? "on" : "off")"
                    )
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.onLog("Slot \(slot): \(error.localizedDescription)")
                }
            }
            if self.connection == nil {
                self.onStatus("Waiting for your MX Master 3S. Move the mouse to wake it.")
            }
        }
    }

    private func feature(_ number: UInt16, _ endpoint: UInt, _ slot: UInt8) async throws -> UInt8 {
        let response = try await request(endpoint, slot, 0, 0, [UInt8(number >> 8), UInt8(number & 255)])
        guard response.payload[0] != 0 else {
            throw MouseError.message(String(format: "Missing HID++ feature %04X", number))
        }
        return response.payload[0]
    }

    func claim(
        _ controls: Set<MouseControl>, movement: Set<MouseControl> = [], wheelMode: WheelMode? = nil,
        horizontalInverted: Bool? = nil
    ) async throws {
        guard let c = connection else { throw MouseError.message("Discover your mouse first.") }
        guard !claimed else { return }
        guard !controls.isEmpty || wheelMode != nil || horizontalInverted != nil else {
            throw MouseError.message("Choose a mouse control to enable.")
        }
        let unavailable = controls.subtracting(c.availableControls)
        if !unavailable.isEmpty {
            throw MouseError.message(
                "Mouse control unavailable: \(unavailable.sorted().map(\.name).joined(separator: ", ")).")
        }
        let movement = movement.intersection(controls)
        let stationary = movement.subtracting(c.movementControls)
        if !stationary.isEmpty {
            throw MouseError.message(
                "Dragging isn't supported on: \(stationary.sorted().map(\.name).joined(separator: ", ")).")
        }
        do {
            for control in controls.sorted() {
                let settings = try await readReporting(control, c)
                guard connection == c else {
                    throw MouseError.message("Mouse connection changed. Discover again.")
                }
                // Keep cleanup state even if the write succeeds but its reply is lost.
                let rawMovement = movement.contains(control)
                claims[control] = settings
                if rawMovement { movementClaims.insert(control) }
                _ = try await request(
                    c.endpoint, c.slot, c.feature, 3,
                    settings.parameters(divert: true, rawMovement: rawMovement))
                let state = try await readReporting(control, c)
                guard state.temporarilyDiverted, state.remap == settings.remap,
                    state.rawMovement == rawMovement
                else {
                    throw MouseError.message("The mouse did not confirm control of \(control.name).")
                }
                onLog("Claimed \(control.name)\(rawMovement ? " with raw movement" : "")")
            }
            if let wheelMode { try await claimWheel(wheelMode, c) }
            if let horizontalInverted { try await claimHorizontal(horizontalInverted, c) }
        } catch {
            // Cleanup must still run when the caller was cancelled.
            try? await Task { try await self.release() }.value
            throw error
        }
    }

    func release() async throws {
        guard claimed, let c = connection else { return }
        var failure: Error?
        if horizontalClaim != nil {
            do { try await releaseHorizontal(c) } catch { failure = error }
        }
        if wheelClaim != nil {
            do { try await releaseWheel(c) } catch { failure = failure ?? error }
        }
        for control in claims.keys.sorted() {
            do {
                let settings = try await readReporting(control, c)
                _ = try await request(c.endpoint, c.slot, c.feature, 3, settings.parameters(divert: false))
                let state = try await readReporting(control, c)
                guard !state.diverted, !state.persistent, state.remap == settings.remap,
                    !state.rawMovement
                else {
                    throw MouseError.message("Mouse did not confirm restoration of \(control.name).")
                }
                claims.removeValue(forKey: control)
                movementClaims.remove(control)
                onLog("Restored \(control.name)")
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Sleep cleanup cannot wait for a reply on the main run loop.
    func releaseImmediately() -> Bool {
        guard let c = connection, let device = devices[c.endpoint] else { return !claimed }
        if let horizontal = horizontalClaim,
            writeImmediately(
                device, c, feature: horizontal.feature, function: 2,
                payload: horizontal.original.bytes)
        {
            horizontalClaim = nil
        }
        if let wheel = wheelClaim {
            let shiftRestored =
                wheel.desiredShift == nil
                || writeImmediately(
                    device, c, feature: wheel.shiftFeature, function: 1, payload: wheel.originalShift)
            let modeRestored = writeImmediately(
                device, c, feature: wheel.feature, function: 2, payload: [wheel.originalMode])
            if shiftRestored && modeRestored { wheelClaim = nil }
        }
        for control in claims.keys.sorted() {
            guard let settings = claims[control] else { continue }
            if writeImmediately(
                device, c, feature: c.feature, function: 3, payload: settings.parameters(divert: false))
            {
                claims.removeValue(forKey: control)
                movementClaims.remove(control)
            }
        }
        return !claimed
    }

    func verifyClaim() async throws -> Bool {
        guard claimed, let c = connection else { return false }
        for control in claims.keys.sorted() {
            guard let original = claims[control] else { return false }
            let state = try await readReporting(control, c)
            guard state.temporarilyDiverted, state.remap == original.remap,
                state.rawMovement == movementClaims.contains(control)
            else { return false }
        }
        if let horizontal = horizontalClaim {
            let state = try await readHorizontal(c, feature: horizontal.feature)
            guard state.inverted == horizontal.inverted else { return false }
        }
        if wheelClaim != nil { return try await verifyWheel(c) }
        return true
    }

    private func readReporting(_ control: MouseControl, _ c: Connection) async throws -> ControlReporting {
        let response: HIDPacket
        do {
            response = try await request(c.endpoint, c.slot, c.feature, 2, control.query)
        } catch MouseError.timeout {
            // A missed receiver reply should not interrupt an otherwise healthy mapping.
            onLog("Retrying settings read for \(control.name)")
            response = try await request(c.endpoint, c.slot, c.feature, 2, control.query)
        }
        guard let state = ControlReporting(response.payload, control: control) else {
            throw MouseError.message("Unexpected settings response for \(control.name).")
        }
        return state
    }

    private func removed(_ device: IOHIDDevice) {
        let id = key(device)
        probes.removeValue(forKey: id)?.cancel()
        probeGenerations.removeValue(forKey: id)
        devices.removeValue(forKey: id)
        let failures = pending.values.filter { $0.endpoint == id }
        for p in failures {
            pending.removeValue(forKey: p.id)
            p.continuation.resume(throwing: MouseError.message("Receiver disconnected"))
        }
        if connection?.endpoint == id {
            connection = nil
            claims.removeAll()
            movementClaims.removeAll()
            wheelClaim = nil
            horizontalClaim = nil
            onDisconnect()
            onStatus("Bolt receiver disconnected")
        }
        IOHIDDeviceClose(device, 0)
    }

    private func received(_ bytes: [UInt8], endpoint: UInt) {
        guard let packet = HIDPacket.parse(bytes) else { return }
        let error = packet.error
        if let p = pending.values.first(where: {
            $0.endpoint == endpoint && $0.device == packet.device
                && $0.feature == (error?.feature ?? packet.feature)
                && $0.address == (error?.address ?? packet.address)
        }) {
            pending.removeValue(forKey: p.id)
            if let error {
                p.continuation.resume(
                    throwing: MouseError.message(String(format: "HID++ error 0x%02X", error.code)))
            } else {
                p.continuation.resume(returning: packet)
            }
            return
        }
        guard claimed, let c = connection, c.endpoint == endpoint, c.slot == packet.device,
            packet.softwareID == 0
        else { return }
        if let wheel = wheelClaim, packet.feature == wheel.feature {
            if let scroll = WheelScroll(packet) { onScroll(scroll, wheel.multiplier) }
            return
        }
        guard c.feature == packet.feature else { return }
        if packet.function == 0 {
            for control in claims.keys.sorted() {
                onPress(control, packet.pressedControls.contains(control.rawValue))
            }
        } else if !movementClaims.isEmpty, let movement = packet.movement {
            onMovement(movement.dx, movement.dy)
        }
    }

    private func request(
        _ endpoint: UInt, _ slot: UInt8, _ feature: UInt8,
        _ function: UInt8, _ payload: [UInt8] = []
    ) async throws -> HIDPacket {
        try Task.checkCancellation()
        guard let device = devices[endpoint] else { throw MouseError.message("Receiver unavailable") }
        let softwareID = nextSoftwareID
        nextSoftwareID = nextSoftwareID == 14 ? 8 : nextSoftwareID + 1
        let bytes = HIDPacket.request(
            device: slot, feature: feature, function: function,
            softwareID: softwareID, payload: payload)
        let id = UUID()
        let response: HIDPacket = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = Pending(
                    id: id, endpoint: endpoint, device: slot, feature: feature,
                    address: bytes[3], continuation: continuation)
                let result = bytes.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(
                        device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
                }
                if result != kIOReturnSuccess {
                    pending.removeValue(forKey: id)?.continuation.resume(
                        throwing: MouseError.message(String(format: "HID write failed: 0x%08X", result)))
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(850))
                    self?.pending.removeValue(forKey: id)?.continuation.resume(
                        throwing: MouseError.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.pending.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
        return response
    }
}

extension BoltMouse {
    private func claimWheel(_ mode: WheelMode, _ c: Connection) async throws {
        let wheel = try await feature(0x2121, c.endpoint, c.slot)
        let shift = try await feature(0x2110, c.endpoint, c.slot)
        let caps = try await request(c.endpoint, c.slot, wheel, 0)
        let currentMode = try await request(c.endpoint, c.slot, wheel, 1)
        let currentShift = try await request(c.endpoint, c.slot, shift, 0)
        guard caps.payload[0] > 0, connection == c else {
            throw MouseError.message("Main-wheel settings unavailable. Reconnect the mouse.")
        }
        let desiredShift: [UInt8]?
        switch mode {
        case .unchanged: desiredShift = nil
        case .ratchet: desiredShift = [2, 255]
        case .freeSpin: desiredShift = [1, currentShift.payload[1]]
        }
        let settings = WheelClaim(
            feature: wheel, shiftFeature: shift, multiplier: caps.payload[0],
            // Clear diversion on restoration, including after an interrupted earlier session.
            originalMode: currentMode.payload[0] & ~1,
            originalShift: Array(currentShift.payload.prefix(2)),
            desiredMode: (currentMode.payload[0] | 3) & ~4, desiredShift: desiredShift)
        wheelClaim = settings
        if let desiredShift {
            _ = try await request(c.endpoint, c.slot, shift, 1, desiredShift)
        }
        _ = try await request(c.endpoint, c.slot, wheel, 2, [settings.desiredMode])
        guard try await verifyWheel(c) else {
            throw MouseError.message("The mouse did not confirm main-wheel control.")
        }
        onLog("Claimed main wheel · \(mode.label)")
    }

    private func verifyWheel(_ c: Connection) async throws -> Bool {
        guard let wheel = wheelClaim else { return false }
        let mode = try await request(c.endpoint, c.slot, wheel.feature, 1)
        guard mode.payload[0] == wheel.desiredMode else { return false }
        if let desired = wheel.desiredShift {
            let shift = try await request(c.endpoint, c.slot, wheel.shiftFeature, 0)
            guard Array(shift.payload.prefix(2)) == desired else { return false }
        }
        return true
    }

    private func releaseWheel(_ c: Connection) async throws {
        guard let wheel = wheelClaim else { return }
        // Restore native scrolling even if the ratchet command fails.
        var failure: Error?
        if wheel.desiredShift != nil {
            do {
                _ = try await request(c.endpoint, c.slot, wheel.shiftFeature, 1, wheel.originalShift)
                let shift = try await request(c.endpoint, c.slot, wheel.shiftFeature, 0)
                guard Array(shift.payload.prefix(2)) == wheel.originalShift else {
                    throw MouseError.message("Mouse did not confirm the previous wheel mode.")
                }
            } catch { failure = error }
        }
        do {
            _ = try await request(c.endpoint, c.slot, wheel.feature, 2, [wheel.originalMode])
            let mode = try await request(c.endpoint, c.slot, wheel.feature, 1)
            guard mode.payload[0] == wheel.originalMode else {
                throw MouseError.message("Mouse did not confirm native scrolling.")
            }
        } catch { failure = failure ?? error }
        if let failure { throw failure }
        wheelClaim = nil
        onLog("Restored main wheel")
    }

    private func writeImmediately(
        _ device: IOHIDDevice, _ c: Connection, feature: UInt8, function: UInt8, payload: [UInt8]
    ) -> Bool {
        let bytes = HIDPacket.request(
            device: c.slot, feature: feature, function: function, softwareID: 15, payload: payload)
        return bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
                == kIOReturnSuccess
        }
    }
}

extension BoltMouse {
    private func readHorizontal(_ c: Connection, feature: UInt8) async throws -> ThumbWheelReporting {
        let response = try await request(c.endpoint, c.slot, feature, 1)
        guard let state = ThumbWheelReporting(response.payload) else {
            throw MouseError.message("Unexpected thumb-wheel settings response.")
        }
        return state
    }

    private func claimHorizontal(_ inverted: Bool, _ c: Connection) async throws {
        let index = try await feature(0x2150, c.endpoint, c.slot)
        let original = try await readHorizontal(c, feature: index)
        guard connection == c else { throw MouseError.message("Mouse connection changed. Reconnect.") }
        horizontalClaim = HorizontalClaim(feature: index, original: original, inverted: inverted)
        let desired = original.parameters(inverted: inverted)
        _ = try await request(c.endpoint, c.slot, index, 2, desired)
        let confirmed = try await readHorizontal(c, feature: index)
        guard confirmed.bytes == desired else {
            throw MouseError.message("Mouse did not confirm horizontal scroll direction.")
        }
        onLog("Horizontal direction · \(inverted ? "Reversed" : "Standard")")
    }

    private func releaseHorizontal(_ c: Connection) async throws {
        guard let horizontal = horizontalClaim else { return }
        let current = try await readHorizontal(c, feature: horizontal.feature)
        let desired = current.parameters(inverted: horizontal.original.inverted)
        _ = try await request(c.endpoint, c.slot, horizontal.feature, 2, desired)
        let confirmed = try await readHorizontal(c, feature: horizontal.feature)
        guard confirmed.bytes == desired else {
            throw MouseError.message("Mouse did not confirm restoration of horizontal scrolling.")
        }
        horizontalClaim = nil
        onLog("Restored horizontal scrolling")
    }
}
