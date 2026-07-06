import CEC25USB
import Foundation

// EC25Helper — a thin USB/AT transport bridge for the Electron front-end.
//
// Protocol: one JSON object per line on stdin, one JSON object per line on stdout.
//   Request : {"id": <any>, "op": "open|send|close|description|ping", ...}
//   Response: {"id": <same>, "ok": true, ...} | {"id": <same>, "ok": false, "error": "..."}
//
// Ops:
//   open        {vid?, pid?}                         -> {ok, description}
//   send        {command, payload?, timeoutMs?}      -> {ok, lines: [...]}
//   description                                       -> {ok, description}
//   close                                             -> {ok}
//   ping                                              -> {ok}
//
// All USB work is blocking and runs on this dedicated process, so the Electron
// UI never stalls. Requests are handled strictly FIFO.

final class Helper {
    private var session: OpaquePointer?

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            handle(trimmed)
        }
        if let session {
            ec25_usb_close(session)
            self.session = nil
        }
    }

    private func handle(_ line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            respond(["id": NSNull(), "ok": false, "error": "invalid JSON request"])
            return
        }

        let id = object["id"] ?? NSNull()
        let op = object["op"] as? String ?? ""

        switch op {
        case "ping":
            respond(["id": id, "ok": true])
        case "open":
            openDevice(id: id, object: object)
        case "description":
            let description = session.map { String(cString: ec25_usb_description($0)) } ?? ""
            respond(["id": id, "ok": true, "description": description])
        case "send":
            sendCommand(id: id, object: object)
        case "close":
            if let session {
                ec25_usb_close(session)
                self.session = nil
            }
            respond(["id": id, "ok": true])
        default:
            respond(["id": id, "ok": false, "error": "unknown op: \(op)"])
        }
    }

    private func openDevice(id: Any, object: [String: Any]) {
        if let session {
            ec25_usb_close(session)
            self.session = nil
        }

        let vid = UInt16(truncatingIfNeeded: (object["vid"] as? Int) ?? 0x2c7c)
        let pid = UInt16(truncatingIfNeeded: (object["pid"] as? Int) ?? 0x0125)

        var opened: OpaquePointer?
        var error = [CChar](repeating: 0, count: 512)
        let rc = ec25_usb_open(vid, pid, &opened, &error, error.count)
        if rc == 0, let opened {
            session = opened
            let description = String(cString: ec25_usb_description(opened))
            respond(["id": id, "ok": true, "description": description])
        } else {
            respond(["id": id, "ok": false, "error": Self.cString(error)])
        }
    }

    private func sendCommand(id: Any, object: [String: Any]) {
        guard let session else {
            respond(["id": id, "ok": false, "error": "原生 USB AT 接口尚未打开"])
            return
        }
        guard let command = object["command"] as? String else {
            respond(["id": id, "ok": false, "error": "missing command"])
            return
        }

        let payload = object["payload"] as? String
        let timeoutMs = Int32(truncatingIfNeeded: (object["timeoutMs"] as? Int) ?? 4000)

        var responsePointer: UnsafeMutablePointer<CChar>?
        var error = [CChar](repeating: 0, count: 512)

        let rc: Int32 = command.withCString { commandCString in
            if let payload {
                return payload.withCString { payloadCString in
                    ec25_usb_send(session, commandCString, payloadCString, timeoutMs, &responsePointer, &error, error.count)
                }
            } else {
                return ec25_usb_send(session, commandCString, nil, timeoutMs, &responsePointer, &error, error.count)
            }
        }

        defer {
            if let responsePointer {
                ec25_usb_free(responsePointer)
            }
        }

        if rc == 0 {
            let text = responsePointer.map { String(cString: $0) } ?? ""
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            respond(["id": id, "ok": true, "lines": lines])
        } else {
            respond(["id": id, "ok": false, "error": Self.cString(error)])
        }
    }

    private static func cString(_ buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
    }

    private func respond(_ dictionary: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
            let json = String(data: data, encoding: .utf8)
        else { return }
        print(json)
        fflush(stdout)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
Helper().run()
