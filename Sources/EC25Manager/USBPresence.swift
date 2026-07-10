import Foundation
import IOKit

/// Event-driven USB presence via IOKit matching notifications — no polling, so
/// idle CPU is essentially zero. Fires `onChange(present)` on the main queue the
/// instant the modem is plugged in or unplugged.
final class USBPresence {
    var onChange: ((Bool) -> Void)?
    private(set) var present = false

    private let vid: Int
    private let pid: Int
    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    init(vid: Int, pid: Int) { self.vid = vid; self.pid = pid }

    func start() {
        present = queryPresent()

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else { return }
        IONotificationPortSetDispatchQueue(notifyPort, DispatchQueue.main)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            let this = Unmanaged<USBPresence>.fromOpaque(refcon!).takeUnretainedValue()
            this.drain(iterator)
            this.update()
        }

        IOServiceAddMatchingNotification(notifyPort, kIOMatchedNotification, matchingDict(), callback, selfPtr, &addedIter)
        drain(addedIter)   // arm + consume existing matches

        IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchingDict(), callback, selfPtr, &removedIter)
        drain(removedIter)
    }

    private func matchingDict() -> CFMutableDictionary {
        let dict = IOServiceMatching("IOUSBDevice") as NSMutableDictionary
        dict["idVendor"] = vid
        dict["idProduct"] = pid
        return dict as CFMutableDictionary
    }

    private func queryPresent() -> Bool {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict(), &iter) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iter) }
        let obj = IOIteratorNext(iter)
        if obj != 0 { IOObjectRelease(obj); return true }
        return false
    }

    private func drain(_ iter: io_iterator_t) {
        var obj = IOIteratorNext(iter)
        while obj != 0 { IOObjectRelease(obj); obj = IOIteratorNext(iter) }
    }

    private func update() {
        let now = queryPresent()
        guard now != present else { return }
        present = now
        onChange?(now)
    }
}
