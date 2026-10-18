import Foundation
import Darwin

/// Shared by the agent and standalone prototype; never run two hardware owners.
package final class ControllerLock {
    private let descriptor: Int32

    package init(directory: URL = ConfigJSON.defaultURL.deletingLastPathComponent()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        descriptor = open(directory.appendingPathComponent("controller.lock").path,
                          O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw NSError(domain: "MXForward", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Another mouse controller is running"])
        }
    }

    deinit { close(descriptor) }
}
