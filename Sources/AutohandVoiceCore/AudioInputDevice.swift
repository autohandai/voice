import AudioToolbox
import CoreAudio
import Foundation

public struct AudioInputDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

public enum AudioInputHealth: String, Equatable, Sendable {
    case idle
    case listening
    case healthy
    case noSignal
    case clipping
    case disconnected

    public var label: String {
        switch self {
        case .idle: "Not listening"
        case .listening: "Checking signal…"
        case .healthy: "Signal is healthy"
        case .noSignal: "No microphone signal"
        case .clipping: "Input level is clipping"
        case .disconnected: "Selected microphone disconnected"
        }
    }
}

public struct AudioHealthMonitor: Sendable {
    public private(set) var state: AudioInputHealth = .idle

    private let noSignalDelay: TimeInterval
    private let audibleThreshold: Float
    private let clippingThreshold: Float
    private let clippingSampleCount: Int
    private var firstObservedAt: TimeInterval?
    private var lastAudibleAt: TimeInterval?
    private var consecutiveClippingSamples = 0

    public init(
        noSignalDelay: TimeInterval = 2,
        audibleThreshold: Float = 0.003,
        clippingThreshold: Float = 0.98,
        clippingSampleCount: Int = 3
    ) {
        self.noSignalDelay = noSignalDelay
        self.audibleThreshold = audibleThreshold
        self.clippingThreshold = clippingThreshold
        self.clippingSampleCount = max(1, clippingSampleCount)
    }

    @discardableResult
    public mutating func observe(
        level: Float,
        at timestamp: TimeInterval
    ) -> AudioInputHealth {
        if firstObservedAt == nil {
            firstObservedAt = timestamp
        }

        if level >= clippingThreshold {
            consecutiveClippingSamples += 1
            if consecutiveClippingSamples >= clippingSampleCount {
                state = .clipping
                return state
            }
        } else {
            consecutiveClippingSamples = 0
        }

        if level >= audibleThreshold {
            lastAudibleAt = timestamp
            state = .healthy
            return state
        }

        let silenceStartedAt = lastAudibleAt ?? firstObservedAt ?? timestamp
        state = timestamp - silenceStartedAt >= noSignalDelay
            ? .noSignal
            : .listening
        return state
    }

    public mutating func disconnect() {
        state = .disconnected
    }

    public mutating func reset() {
        self = AudioHealthMonitor(
            noSignalDelay: noSignalDelay,
            audibleThreshold: audibleThreshold,
            clippingThreshold: clippingThreshold,
            clippingSampleCount: clippingSampleCount
        )
    }
}

public enum AudioInputDeviceError: LocalizedError, Equatable {
    case coreAudio(OSStatus)
    case selectedDeviceUnavailable

    public var errorDescription: String? {
        switch self {
        case let .coreAudio(status):
            "Core Audio could not inspect microphones (error \(status))."
        case .selectedDeviceUnavailable:
            "The selected microphone is no longer available."
        }
    }
}

public enum AudioInputDevices {
    public static func available() throws -> [AudioInputDevice] {
        let deviceIDs = try allDeviceIDs()
        let defaultID = try? property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            as: AudioDeviceID.self
        )

        return try deviceIDs.compactMap { deviceID in
            guard try hasInputStreams(deviceID) else { return nil }
            return AudioInputDevice(
                id: try stringProperty(
                    deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                ),
                name: try stringProperty(
                    deviceID,
                    selector: kAudioObjectPropertyName
                ),
                isSystemDefault: deviceID == defaultID
            )
        }
        .sorted {
            if $0.isSystemDefault != $1.isSystemDefault {
                return $0.isSystemDefault
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func deviceID(forUID uid: String?) throws -> AudioDeviceID {
        if let uid {
            guard let match = try allDeviceIDs().first(where: {
                try stringProperty(
                    $0,
                    selector: kAudioDevicePropertyDeviceUID
                ) == uid
            }) else {
                throw AudioInputDeviceError.selectedDeviceUnavailable
            }
            return match
        }

        return try property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            as: AudioDeviceID.self
        )
    }

    private static func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount
            )
        )

        let count = Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        var values = [AudioDeviceID](repeating: 0, count: count)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount,
                &values
            )
        )
        return values
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &byteCount
            )
        )
        return byteCount >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        let value = try property(
            objectID: deviceID,
            selector: selector,
            scope: kAudioObjectPropertyScopeGlobal,
            as: CFString.self
        )
        return value as String
    }

    private static func property<Value>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        as _: Value.Type
    ) throws -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount = UInt32(MemoryLayout<Value>.size)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteCount),
            alignment: MemoryLayout<Value>.alignment
        )
        defer { pointer.deallocate() }
        try check(
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &byteCount,
                pointer
            )
        )
        return pointer.load(as: Value.self)
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioInputDeviceError.coreAudio(status)
        }
    }
}

public final class AudioInputDeviceMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "ai.autohand.voice.audio-device-monitor"
    )
    private let onChange: @Sendable () -> Void
    private var listener: AudioObjectPropertyListenerBlock?

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange()
        }
        listener = block

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            queue,
            block
        )

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            queue,
            block
        )
    }

    deinit {
        guard let listener else { return }
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            queue,
            listener
        )

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            queue,
            listener
        )
    }
}
