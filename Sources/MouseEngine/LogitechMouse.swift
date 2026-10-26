import ForwardCore
import Foundation
import IOKit.hid

enum MouseError: LocalizedError {
    case message(String)
    case timeout
    case hidpp1(UInt8)
    case hidpp2(UInt8)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .timeout: return "Mouse response timed out"
        case .hidpp1(let code), .hidpp2(let code):
            return String(format: "HID++ error 0x%02X", code)
        }
    }
}

@MainActor
package final class LogitechMouse {
    struct Connection: Equatable {
        let endpoint: UInt
        let slot: UInt8
        let feature: UInt8
        let unitID: UInt32
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
    private let recoveryURL: URL?

    package init(recoveryURL: URL? = nil) { self.recoveryURL = recoveryURL }

    deinit {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        for device in devices.values { IOHIDDeviceClose(device, 0) }
    }

    private var discoveryEnabled = true
    private var manager: IOHIDManager?
    private var devices: [UInt: IOHIDDevice] = [:]
    private var pending: [UUID: Pending] = [:]
    private var probes: [UInt: Task<Void, Never>] = [:]
    private var probeGenerations: [UInt: UUID] = [:]
    private var nextSoftwareID: UInt8 = 8
    private(set) var connection: Connection?
    private(set) var recoveryPending = false
    var isDiscovering: Bool { !probes.isEmpty }
    private var claims: [MouseControl: ControlReporting] = [:]
    private var movementClaims = Set<MouseControl>()
    private struct WheelClaim: Codable {
        var feature: UInt8
        var shiftFeature: UInt8
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
        let stepsPerDelta: Double?
        var diverted: Bool { stepsPerDelta != nil }
    }
    private var horizontalClaim: HorizontalClaim?
    var claimed: Bool { !claims.isEmpty || wheelClaim != nil || horizontalClaim != nil }
    var onStatus: (String) -> Void = { _ in }
    var onPress: (MouseControl, Bool) -> Void = { _, _ in }
    var onMovement: (Int16, Int16) -> Void = { _, _ in }
    var onScroll: (WheelScroll, UInt8) -> Void = { _, _ in }
    var onHorizontalScroll: (ThumbWheelScroll, Double) -> Void = { _, _ in }
    var onDisconnect: () -> Void = {}
    var onLog: (String) -> Void = { _ in }

    func start() throws {
        discoveryEnabled = true
        if manager != nil {
            rescan()
            return
        }
        let value = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        manager = value
        IOHIDManagerSetDeviceMatchingMultiple(
            value,
            [
                [
                    kIOHIDVendorIDKey: 0x046D,
                    kIOHIDProductIDKey: 0xC548,
                    kIOHIDPrimaryUsagePageKey: 0xFF00,
                    kIOHIDPrimaryUsageKey: 1,
                ],
                [kIOHIDVendorIDKey: 0x046D, kIOHIDProductIDKey: 0xB034],
            ] as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            value,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<LogitechMouse>.fromOpaque(context).takeUnretainedValue().matched(device)
                }
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            value,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<LogitechMouse>.fromOpaque(context).takeUnretainedValue().removed(device)
                }
            }, context)
        IOHIDManagerRegisterInputReportCallback(
            value,
            { context, _, sender, _, reportID, bytes, length in
                guard let context, let sender, reportID == 0x10 || reportID == 0x11 else { return }
                var data = Array(UnsafeBufferPointer(start: bytes, count: length))
                if length == (reportID == 0x10 ? 6 : 19) { data.insert(UInt8(reportID), at: 0) }
                MainActor.assumeIsolated {
                    Unmanaged<LogitechMouse>.fromOpaque(context).takeUnretainedValue()
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
                        "Cannot open Logitech mouse devices (0x%08X). Check Input Monitoring, then restart MX Forward.",
                    result))
        }
        onStatus("Looking for your MX Master 3S…")
    }

    func rescan() {
        guard discoveryEnabled, !claimed, connection == nil else { return }
        for key in devices.keys where probes[key] == nil { beginProbe(key) }
    }

    func stopDiscovery() async {
        discoveryEnabled = false
        let tasks = Array(probes.values)
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
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
        let bluetooth = isBluetooth(device)
        if bluetooth {
            let elements = IOHIDDeviceCopyMatchingElements(
                device, [kIOHIDElementTypeKey: kIOHIDElementTypeOutput.rawValue] as CFDictionary, 0)
                as? [IOHIDElement] ?? []
            guard elements.contains(where: { IOHIDElementGetReportID($0) == 0x11 }) else { return }
        }
        let result = IOHIDDeviceOpen(device, 0)
        guard result == kIOReturnSuccess else {
            onStatus(
                String(format: "Logitech mouse device unavailable (0x%08X). Check Input Monitoring.", result))
            return
        }
        devices[id] = device
        onLog(bluetooth ? "Bluetooth mouse connected" : "Bolt receiver connected")
        beginProbe(id)
    }

    private func isBluetooth(_ device: IOHIDDevice) -> Bool {
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        return transport.hasPrefix("Bluetooth")
    }

    private func beginProbe(_ id: UInt) {
        guard discoveryEnabled, let device = devices[id] else { return }
        let bluetooth = isBluetooth(device)
        let slots: ClosedRange<UInt8> = bluetooth ? 0xFF...0xFF : 1...6
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
            for slot in slots {
                guard !Task.isCancelled, self.connection == nil, self.devices[id] != nil else { return }
                let transport = bluetooth ? "Bluetooth" : "Bolt slot \(slot)"
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
                    let information = try await self.feature(0x0003, id, slot)
                    let identity = try await self.request(id, slot, information, 0)
                    guard identity.payload.count >= 5 else {
                        throw MouseError.message("Incomplete mouse identity response")
                    }
                    let unitID = identity.payload[1...4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
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
                        endpoint: id, slot: slot, feature: index, unitID: unitID,
                        discardFirstMovement: special.payload[2] >= 5, availableControls: availableControls,
                        movementControls: movementControls)
                    do { try await self.recoverInterruptedSession() } catch {
                        self.onStatus(
                            "Recovery pending: \(error.localizedDescription). Retry Pause, or power-cycle the mouse."
                        )
                        return
                    }
                    self.onStatus("\(name) connected · \(transport)")
                    self.onLog("\(name) connected · \(transport)")
                    self.onLog(
                        "Available buttons: \(availableControls.sorted().map(\.name).joined(separator: ", "))"
                    )
                    self.onLog(
                        "Button feature version \(special.payload[2]); initial movement filter \(special.payload[2] >= 5 ? "on" : "off")"
                    )
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.onLog("\(transport): \(error.localizedDescription)")
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
        horizontalInverted: Bool? = nil, horizontalDiverted: Bool = false
    ) async throws {
        guard let c = connection else { throw MouseError.message("Discover your mouse first.") }
        guard !recoveryPending else { throw MouseError.message("Mouse recovery is still pending.") }
        guard !claimed else { return }
        guard !controls.isEmpty || wheelMode != nil || horizontalInverted != nil || horizontalDiverted else {
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
                try saveRecovery(c)
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
            if horizontalInverted != nil || horizontalDiverted {
                try await claimHorizontal(horizontalInverted, diverted: horizontalDiverted, c)
            }
        } catch {
            // Cleanup must still run when the caller was cancelled.
            try? await Task {
                try await self.release()
                await self.disconnectIfUnavailable(c)
            }.value
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
        try saveRecovery(c)
        if !claimed { recoveryPending = false }
        if let failure {
            await disconnectIfUnavailable(c)
            if connection == c { throw failure }
        }
    }

    /// Sleep cleanup cannot wait for a reply on the main run loop.
    func releaseImmediately() -> Bool {
        guard let c = connection, let device = devices[c.endpoint] else { return !claimed }
        if let horizontal = horizontalClaim,
            writeImmediately(
                device, c, feature: horizontal.feature, function: 2,
                payload: horizontal.original.parameters(
                    inverted: horizontal.original.inverted, diverted: false))
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
            guard state.inverted == horizontal.inverted, state.diverted == horizontal.diverted else {
                return false
            }
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
            p.continuation.resume(throwing: MouseError.message("Mouse device disconnected"))
        }
        if connection?.endpoint == id { disconnect() }
        IOHIDDeviceClose(device, 0)
    }

    private func disconnect() {
        connection = nil
        claims.removeAll()
        movementClaims.removeAll()
        wheelClaim = nil
        horizontalClaim = nil
        recoveryPending = recoveryURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        onDisconnect()
        onStatus("Mouse device disconnected; waiting for reconnection")
    }

    private func disconnectIfUnavailable(_ c: Connection) async {
        guard connection == c, !recoveryPending,
            !claimed || recoveryURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true
        else { return }
        do {
            _ = try await request(c.endpoint, c.slot, 0, 1, [0, 0, 0xA7])
        } catch MouseError.hidpp1(let code) where code == 0x04 || code == 0x09 {
            if connection == c { disconnect() }
        } catch {}
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
                let failure = packet.feature == 0x8F
                    ? MouseError.hidpp1(error.code) : MouseError.hidpp2(error.code)
                p.continuation.resume(throwing: failure)
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
        if let horizontal = horizontalClaim, let steps = horizontal.stepsPerDelta,
            packet.feature == horizontal.feature
        {
            if let scroll = ThumbWheelScroll(packet) { onHorizontalScroll(scroll, steps) }
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
        guard let device = devices[endpoint] else { throw MouseError.message("Mouse device unavailable") }
        let softwareID = nextSoftwareID
        nextSoftwareID = nextSoftwareID == 14 ? 8 : nextSoftwareID + 1
        let bytes = HIDPacket.request(
            device: slot, feature: feature, function: function,
            softwareID: softwareID, payload: payload, longReport: isBluetooth(device))
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

extension LogitechMouse {
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
        try saveRecovery(c)
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
            device: c.slot, feature: feature, function: function, softwareID: 15, payload: payload,
            longReport: isBluetooth(device))
        return bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
                == kIOReturnSuccess
        }
    }
}

extension LogitechMouse {
    private func readHorizontal(_ c: Connection, feature: UInt8) async throws -> ThumbWheelReporting {
        let response = try await request(c.endpoint, c.slot, feature, 1)
        guard let state = ThumbWheelReporting(response.payload) else {
            throw MouseError.message("Unexpected thumb-wheel settings response.")
        }
        return state
    }

    private func claimHorizontal(_ inverted: Bool?, diverted: Bool, _ c: Connection) async throws {
        let index = try await feature(0x2150, c.endpoint, c.slot)
        let original = try await readHorizontal(c, feature: index)
        let inverted = inverted ?? original.inverted
        var stepsPerDelta: Double?
        if diverted {
            let info = try await request(c.endpoint, c.slot, index, 0)
            guard let resolution = ThumbWheelResolution(info.payload) else {
                throw MouseError.message("Invalid thumb-wheel resolution.")
            }
            stepsPerDelta = resolution.stepsPerDelta
        }
        guard connection == c else { throw MouseError.message("Mouse connection changed. Reconnect.") }
        horizontalClaim = HorizontalClaim(
            feature: index, original: original, inverted: inverted, stepsPerDelta: stepsPerDelta)
        try saveRecovery(c)
        let desired = original.parameters(inverted: inverted, diverted: diverted)
        _ = try await request(c.endpoint, c.slot, index, 2, desired)
        let confirmed = try await readHorizontal(c, feature: index)
        guard confirmed.bytes == desired else {
            throw MouseError.message("Mouse did not confirm thumb-wheel settings.")
        }
        onLog("Horizontal direction · \(inverted ? "Reversed" : "Standard")")
        if diverted { onLog("Claimed thumb wheel with custom speed") }
    }

    private func releaseHorizontal(_ c: Connection) async throws {
        guard let horizontal = horizontalClaim else { return }
        let current = try await readHorizontal(c, feature: horizontal.feature)
        let desired = current.parameters(inverted: horizontal.original.inverted, diverted: false)
        _ = try await request(c.endpoint, c.slot, horizontal.feature, 2, desired)
        let confirmed = try await readHorizontal(c, feature: horizontal.feature)
        guard confirmed.bytes == desired else {
            throw MouseError.message("Mouse did not confirm restoration of horizontal scrolling.")
        }
        horizontalClaim = nil
        onLog("Restored horizontal scrolling")
    }
}

extension LogitechMouse {
    private struct Recovery: Codable {
        var slot: UInt8
        var unitID: UInt32?
        var controls: [UInt16]
        var wheel: WheelClaim?
        var horizontalOriginal: [UInt8]?
        var horizontalInverted: Bool?
    }

    // Save native settings before changing the mouse so a restart can restore them.
    private func saveRecovery(_ c: Connection) throws {
        guard let recoveryURL, connection == c else { return }
        if !claimed {
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                try FileManager.default.removeItem(at: recoveryURL)
            }
            return
        }
        let recovery = Recovery(
            slot: c.slot, unitID: c.unitID == 0 ? nil : c.unitID,
            controls: claims.keys.map(\.rawValue), wheel: wheelClaim,
            horizontalOriginal: horizontalClaim?.original.bytes,
            horizontalInverted: horizontalClaim?.inverted)
        try FileManager.default.createDirectory(
            at: recoveryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(recovery).write(to: recoveryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
    }

    private func recoverInterruptedSession() async throws {
        guard let recoveryURL, let c = connection,
            FileManager.default.fileExists(atPath: recoveryURL.path)
        else { return }
        recoveryPending = true
        let file = try FileHandle(forReadingFrom: recoveryURL)
        defer { try? file.close() }
        let data = try file.read(upToCount: 65536) ?? Data()
        guard data.count < 65536 else { throw MouseError.message("Hardware recovery file is too large") }
        let saved = try JSONDecoder().decode(Recovery.self, from: data)
        guard saved.controls.count <= MouseControl.allCases.count,
            Set(saved.controls).count == saved.controls.count
        else { throw MouseError.message("Invalid saved mouse controls") }
        let sameMouse = saved.unitID.map { $0 != 0 && $0 == c.unitID } ?? (saved.slot == c.slot)
        guard sameMouse else {
            throw MouseError.message("Interrupted session belongs to another mouse or connection")
        }
        var recoveredClaims: [MouseControl: ControlReporting] = [:]
        var recoveredWheel: WheelClaim?
        var recoveredHorizontal: HorizontalClaim?
        for id in saved.controls {
            guard let control = MouseControl(rawValue: id), c.availableControls.contains(control) else {
                throw MouseError.message("Saved mouse control is unavailable: \(id)")
            }
            recoveredClaims[control] = try await readReporting(control, c)
        }
        if var wheel = saved.wheel {
            guard wheel.originalMode & 1 == 0, wheel.originalShift.count == 2,
                wheel.desiredShift == nil || wheel.desiredShift?.count == 2
            else {
                throw MouseError.message("Invalid saved wheel settings")
            }
            wheel.feature = try await feature(0x2121, c.endpoint, c.slot)
            wheel.shiftFeature = try await feature(0x2110, c.endpoint, c.slot)
            recoveredWheel = wheel
        }
        if let bytes = saved.horizontalOriginal {
            guard let original = ThumbWheelReporting(bytes) else {
                throw MouseError.message("Invalid saved thumb-wheel settings")
            }
            let index = try await feature(0x2150, c.endpoint, c.slot)
            recoveredHorizontal = HorizontalClaim(
                feature: index, original: original,
                inverted: saved.horizontalInverted ?? original.inverted, stepsPerDelta: nil)
        }
        try Task.checkCancellation()
        guard connection == c else { throw MouseError.message("Mouse disconnected during recovery") }
        claims = recoveredClaims
        wheelClaim = recoveredWheel
        horizontalClaim = recoveredHorizontal
        try await release()
        // An empty journal is also removed by successful recovery.
        try saveRecovery(c)
        recoveryPending = false
        onLog("Recovered native controls from the interrupted agent session")
    }
}
