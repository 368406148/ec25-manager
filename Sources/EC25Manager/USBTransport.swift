import CEC25USB
import Foundation

enum USBError: LocalizedError {
    case openFailed(String)
    case commandFailed(String)
    case notOpen

    var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "打开 USB AT 接口失败：\(m)"
        case .commandFailed(let m): return "USB AT 命令失败：\(m)"
        case .notOpen: return "USB AT 接口尚未打开"
        }
    }
}

/// Thin wrapper around the CEC25USB libusb shim. All libusb work happens on a
/// dedicated serial queue so the UI never blocks; results are marshalled back
/// via continuations.
final class USBTransport {
    static let defaultVID: UInt16 = 0x2c7c
    static let defaultPID: UInt16 = 0x0125

    private var session: OpaquePointer?
    private let queue = DispatchQueue(label: "ec25.usb")

    var descriptionText: String {
        guard let session else { return "USB 2c7c:0125" }
        return String(cString: ec25_usb_description(session))
    }

    var isOpen: Bool { session != nil }

    /// Open + auto-scan for the AT-capable bulk interface. Runs off the main thread.
    func open(vid: UInt16 = USBTransport.defaultVID, pid: UInt16 = USBTransport.defaultPID) async throws {
        let opened: OpaquePointer = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Re-open replaces any stale session.
                if let s = self.session { ec25_usb_close(s); self.session = nil }
                var handle: OpaquePointer?
                var error = [CChar](repeating: 0, count: 512)
                let rc = ec25_usb_open(vid, pid, &handle, &error, error.count)
                if rc == 0, let handle {
                    self.session = handle
                    continuation.resume(returning: handle)
                } else {
                    continuation.resume(throwing: USBError.openFailed(Self.string(error)))
                }
            }
        }
        _ = opened
    }

    func send(_ command: String, payload: String? = nil, timeout: TimeInterval = 4) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let session = self.session else {
                    continuation.resume(throwing: USBError.notOpen)
                    return
                }
                var responsePointer: UnsafeMutablePointer<CChar>?
                var error = [CChar](repeating: 0, count: 512)
                let timeoutMs = Int32(max(500, Int(timeout * 1000)))
                let rc: Int32 = command.withCString { c in
                    if let payload {
                        return payload.withCString { p in
                            ec25_usb_send(session, c, p, timeoutMs, &responsePointer, &error, error.count)
                        }
                    } else {
                        return ec25_usb_send(session, c, nil, timeoutMs, &responsePointer, &error, error.count)
                    }
                }
                defer { if let responsePointer { ec25_usb_free(responsePointer) } }
                guard rc == 0 else {
                    continuation.resume(throwing: USBError.commandFailed(Self.string(error)))
                    return
                }
                let text = responsePointer.map { String(cString: $0) } ?? ""
                let lines = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines)
            }
        }
    }

    func close() {
        queue.async {
            if let s = self.session { ec25_usb_close(s); self.session = nil }
        }
    }

    private static func string(_ buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}
