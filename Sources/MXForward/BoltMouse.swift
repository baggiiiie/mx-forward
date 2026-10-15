import ForwardCore
import Foundation
import IOKit.hid

enum MouseError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
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
    private var originalReporting: ForwardReporting?
    var claimed: Bool { originalReporting != nil }
    var onStatus: (String) -> Void = { _ in }
    var onPress: (Bool) -> Void = { _ in }
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
                    let index = try await self.feature(0x1B04, id, slot)
                    let count = try await self.request(id, slot, index, 0)
                    var foundForward = false
                    for position in 0..<min(Int(count.payload[0]), 64) {
                        let info = try await self.request(id, slot, index, 1, [UInt8(position)])
                        if info.payload.count >= 5, info.payload[0] == 0, info.payload[1] == 86 {
                            foundForward = info.payload[4] & 0x20 != 0
                        }
                    }
                    guard foundForward else {
                        throw MouseError.message("Forward button does not support software control.")
                    }
                    guard self.connection == nil else { return }
                    self.connection = Connection(endpoint: id, slot: slot, feature: index)
                    self.onStatus("\(name) connected · Bolt slot \(slot)")
                    self.onLog("Identified Forward control 0x0056 (feature \(index))")
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

    func claim() async throws {
        guard let c = connection else { throw MouseError.message("Discover your mouse first.") }
        guard !claimed else { return }
        let settings = try await readReporting(c)
        guard connection == c else { throw MouseError.message("Mouse connection changed. Discover again.") }
        // Keep cleanup state even if the write succeeds but its reply is lost.
        originalReporting = settings
        do {
            _ = try await request(c.endpoint, c.slot, c.feature, 3, settings.parameters(divert: true))
            let state = try await readReporting(c)
            guard state.temporarilyDiverted, state.remap == settings.remap else {
                throw MouseError.message("The mouse did not confirm temporary Forward-button control.")
            }
        } catch {
            // Cleanup must still run when the caller was cancelled.
            try? await Task { try await self.release() }.value
            throw error
        }
    }

    func release() async throws {
        guard claimed, let c = connection else { return }
        let settings = try await readReporting(c)
        _ = try await request(c.endpoint, c.slot, c.feature, 3, settings.parameters(divert: false))
        let state = try await readReporting(c)
        guard !state.diverted, !state.persistent, state.remap == settings.remap else {
            throw MouseError.message("Mouse did not confirm restoration of native Forward.")
        }
        originalReporting = nil
    }

    /// Sleep cleanup cannot wait for a reply on the main run loop.
    func releaseImmediately() -> Bool {
        guard let settings = originalReporting, let c = connection,
            let device = devices[c.endpoint]
        else { return !claimed }
        let bytes = HIDPacket.request(
            device: c.slot, feature: c.feature, function: 3,
            softwareID: 15, payload: settings.parameters(divert: false))
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
        }
        if result == kIOReturnSuccess { originalReporting = nil }
        return result == kIOReturnSuccess
    }

    func verifyClaim() async throws -> Bool {
        guard let original = originalReporting, let c = connection else { return false }
        let state = try await readReporting(c)
        return state.temporarilyDiverted && state.remap == original.remap
    }

    private func readReporting(_ c: Connection) async throws -> ForwardReporting {
        let response = try await request(c.endpoint, c.slot, c.feature, 2, ForwardReporting.query)
        guard let state = ForwardReporting(response.payload) else {
            throw MouseError.message("Unexpected Forward-button settings response.")
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
            originalReporting = nil
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
            c.feature == packet.feature, packet.softwareID == 0, packet.function == 0
        else { return }
        onPress(packet.pressedControls.contains(ForwardReporting.controlID))
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
                        throwing: MouseError.message("Mouse response timed out"))
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
