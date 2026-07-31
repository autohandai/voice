import Foundation
import IOKit.hid

@MainActor
final class ExtraPointerDeviceMonitor {
    var onAvailabilityChange: ((Bool) -> Void)?

    private var manager: IOHIDManager?
    private var lastAvailability: Bool?

    func start() {
        guard manager == nil else {
            publishAvailability()
            return
        }
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String:
                kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(
            manager,
            matching as CFDictionary
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            extraPointerDeviceChanged,
            pointer
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            extraPointerDeviceChanged,
            pointer
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerOpen(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        self.manager = manager
        publishAvailability()
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        self.manager = nil
        lastAvailability = nil
    }

    fileprivate func publishAvailability() {
        guard let manager else { return }
        let devices =
            (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)
                ?? []
        let available = devices.contains(
            where: Self.hasExtraButton
        )
        guard available != lastAvailability else { return }
        lastAvailability = available
        onAvailabilityChange?(available)
    }

    private static func hasExtraButton(_ device: IOHIDDevice) -> Bool {
        let matching: [String: Any] = [
            kIOHIDElementUsagePageKey as String: kHIDPage_Button,
        ]
        guard
            let elements = IOHIDDeviceCopyMatchingElements(
                device,
                matching as CFDictionary,
                IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement]
        else { return false }
        return elements.contains {
            IOHIDElementGetUsagePage($0) == kHIDPage_Button
                && IOHIDElementGetUsage($0) > 2
        }
    }

    deinit {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(
                manager,
                IOOptionBits(kIOHIDOptionsTypeNone)
            )
        }
    }
}

private let extraPointerDeviceChanged: IOHIDDeviceCallback = {
    context,
    _,
    _,
    _
    in
    guard let context else { return }
    let monitor = Unmanaged<ExtraPointerDeviceMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
    Task { @MainActor in
        monitor.publishAvailability()
    }
}
