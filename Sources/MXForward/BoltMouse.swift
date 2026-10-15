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
        let topZoomAvailable: Bool
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
    var claimed: Bool { !claims.isEmpty }
    var onStatus: (String) -> Void = { _ in }
    var onPress: (MouseControl, Bool) -> Void = { _, _ in }
    var onMovement: (Int16, Int16) -> Void = { _, _ in }
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
                    var foundForward = false
                    var topZoomAvailable = false
                    for position in 0..<min(Int(count.payload[0]), 64) {
                        let info = try await self.request(id, slot, index, 1, [UInt8(position)])
                        if info.payload.count >= 5, info.payload[0] == 0, info.payload[1] == 86 {
                            foundForward = info.payload[4] & 0x20 != 0
                        }
                        if info.payload.count >= 9, info.payload.starts(with: MouseControl.top.query) {
                            topZoomAvailable = info.payload[4] & 0x20 != 0 && info.payload[8] & 1 != 0
                        }
                    }
                    guard foundForward else {
                        throw MouseError.message("Forward button does not support software control.")
                    }
                    guard self.connection == nil else { return }
                    self.connection = Connection(
                        endpoint: id, slot: slot, feature: index,
                        discardFirstMovement: special.payload[2] >= 5, topZoomAvailable: topZoomAvailable)
                    self.onStatus("\(name) connected · Bolt slot \(slot)")
                    self.onLog(
                        "Forward detected; top-button movement: \(topZoomAvailable ? "available" : "unavailable")"
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
                self.onStatus("No awake MX Master 3S found. Move the mouse, then Discover again.")
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

    func claim(_ controls: Set<MouseControl>) async throws {
        guard let c = connection else { throw MouseError.message("Discover your mouse first.") }
        guard !claimed else { return }
        guard !controls.isEmpty else { throw MouseError.message("Choose a button to enable.") }
        if controls.contains(.top) && !c.topZoomAvailable {
            throw MouseError.message("This mouse did not report top-button movement support.")
        }
        do {
            for control in controls.sorted() {
                let settings = try await readReporting(control, c)
                guard connection == c else {
                    throw MouseError.message("Mouse connection changed. Discover again.")
                }
                // Keep cleanup state even if the write succeeds but its reply is lost.
                claims[control] = settings
                _ = try await request(c.endpoint, c.slot, c.feature, 3, settings.parameters(divert: true))
                let state = try await readReporting(control, c)
                guard state.temporarilyDiverted, state.remap == settings.remap,
                    state.rawMovement == (control == .top)
                else {
                    throw MouseError.message("The mouse did not confirm control of \(control.name).")
                }
                onLog("Claimed \(control.name)\(control == .top ? " with raw movement" : "")")
            }
        } catch {
            // Cleanup must still run when the caller was cancelled.
            try? await Task { try await self.release() }.value
            throw error
        }
    }

    func release() async throws {
        guard claimed, let c = connection else { return }
        var failure: Error?
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
                onLog("Restored \(control.name)")
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Sleep cleanup cannot wait for a reply on the main run loop.
    func releaseImmediately() -> Bool {
        guard let c = connection, let device = devices[c.endpoint] else { return !claimed }
        for control in claims.keys.sorted() {
            guard let settings = claims[control] else { continue }
            let bytes = HIDPacket.request(
                device: c.slot, feature: c.feature, function: 3,
                softwareID: 15, payload: settings.parameters(divert: false))
            let result = bytes.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(
                    device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
            }
            if result == kIOReturnSuccess { claims.removeValue(forKey: control) }
        }
        return !claimed
    }

    func verifyClaim() async throws -> Bool {
        guard claimed, let c = connection else { return false }
        for control in claims.keys.sorted() {
            guard let original = claims[control] else { return false }
            let state = try await readReporting(control, c)
            guard state.temporarilyDiverted, state.remap == original.remap,
                state.rawMovement == (control == .top)
            else { return false }
        }
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
            c.feature == packet.feature, packet.softwareID == 0
        else { return }
        if packet.function == 0 {
            for control in claims.keys.sorted() {
                onPress(control, packet.pressedControls.contains(control.rawValue))
            }
        } else if claims[.top] != nil, let movement = packet.movement {
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
