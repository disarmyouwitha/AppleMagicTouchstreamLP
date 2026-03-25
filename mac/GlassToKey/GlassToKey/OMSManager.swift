/*
 OMSManager.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

@preconcurrency import OpenMultitouchSupportXCF
import Foundation
import os

struct OMSDeviceInfo: Sendable, Hashable {
    let deviceName: String
    let deviceID: String
    let deviceIDNumeric: UInt64
    let isBuiltIn: Bool
    internal nonisolated(unsafe) let deviceInfo: OpenMTDeviceInfo

    internal init(_ deviceInfo: OpenMTDeviceInfo) {
        self.deviceInfo = deviceInfo
        self.deviceName = deviceInfo.deviceName
        self.deviceID = deviceInfo.deviceID
        self.deviceIDNumeric = UInt64(deviceInfo.deviceID) ?? 0
        self.isBuiltIn = deviceInfo.isBuiltIn
    }
}

enum OMSHapticIntensity: Int32, CaseIterable, Sendable {
    case weak = 3
    case medium = 4
    case strong = 6
}

enum OMSHapticPattern: Int32, CaseIterable, Sendable {
    case generic = 15
    case alignment = 16
    case level = 5
}

struct OMSRawTouch: Sendable {
    let id: Int32
    let posX: Float
    let posY: Float
    let total: Float
    let pressure: Float
    let majorAxis: Float
    let minorAxis: Float
    let angle: Float
    let density: Float
    let state: OMSState
}

struct OMSRawTouchBufferView: RandomAccessCollection, @unchecked Sendable {
    typealias Element = OMSRawTouch
    typealias Index = Int

    static let empty = OMSRawTouchBufferView(baseAddress: nil, count: 0)

    fileprivate let baseAddress: UnsafePointer<OMSRawTouch>?
    let count: Int

    var startIndex: Int { 0 }
    var endIndex: Int { count }

    subscript(position: Int) -> OMSRawTouch {
        precondition(position >= 0 && position < count)
        guard let baseAddress else {
            preconditionFailure("touch buffer released")
        }
        return baseAddress[position]
    }
}

final class OMSRawTouchFrame: @unchecked Sendable {
    let deviceID: String
    let deviceIDNumeric: UInt64
    let deviceIndex: Int
    let timestamp: TimeInterval
    private var buffer: RawTouchBuffer?
    private let releaseHandler: ((RawTouchBuffer) -> Void)?

    var touches: OMSRawTouchBufferView {
        buffer?.view ?? .empty
    }

    fileprivate init(
        deviceID: String,
        deviceIDNumeric: UInt64,
        deviceIndex: Int,
        timestamp: TimeInterval,
        buffer: RawTouchBuffer?,
        releaseHandler: ((RawTouchBuffer) -> Void)?
    ) {
        self.deviceID = deviceID
        self.deviceIDNumeric = deviceIDNumeric
        self.deviceIndex = deviceIndex
        self.timestamp = timestamp
        self.buffer = buffer
        self.releaseHandler = releaseHandler
    }

    func release() {
        guard let buffer else { return }
        self.buffer = nil
        releaseHandler?(buffer)
    }

    deinit {
        release()
    }
}

final class OMSManager: Sendable {
    static let shared = OMSManager()

    typealias RawTouchFrameHandler = @Sendable (OMSRawTouchFrame) -> Void

    private let protectedCaptureManager: OSAllocatedUnfairLock<OpenMTManagerV2?>
    private let protectedHapticManager: OSAllocatedUnfairLock<OpenMTManager?>
    private let protectedRawListener = OSAllocatedUnfairLock<OpenMTListener?>(uncheckedState: nil)
    private let protectedTimestampEnabled = OSAllocatedUnfairLock<Bool>(uncheckedState: true)
    private let protectedDeviceIndexStore = OSAllocatedUnfairLock<DeviceIndexStore>(
        uncheckedState: DeviceIndexStore()
    )
    private let deviceIDStringCache = OSAllocatedUnfairLock<[UInt64: String]>(
        uncheckedState: [:]
    )
    private let rawFrameHandler = OSAllocatedUnfairLock<RawTouchFrameHandler?>(
        uncheckedState: nil
    )
    private let rawBufferPool = OSAllocatedUnfairLock<[RawTouchBuffer]>(uncheckedState: [])
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "ink.ranna.GlassToKey",
        category: "OpenMT"
    )
#endif

    var isListening: Bool {
        protectedRawListener.withLockUnchecked { $0 != nil }
    }

    func setRawFrameHandler(_ handler: RawTouchFrameHandler?) {
        rawFrameHandler.withLockUnchecked { $0 = handler }
    }

    var isTimestampEnabled: Bool {
        get { protectedTimestampEnabled.withLockUnchecked(\.self) }
        set { protectedTimestampEnabled.withLockUnchecked { $0 = newValue } }
    }

    var availableDevices: [OMSDeviceInfo] {
        guard let manager = protectedCaptureManager.withLockUnchecked(\.self) else { return [] }
        manager.refreshAvailableDevices()
        return manager.availableDevices().map { OMSDeviceInfo($0) }
    }

    var activeDevices: [OMSDeviceInfo] {
        guard let manager = protectedCaptureManager.withLockUnchecked(\.self) else { return [] }
        return manager.activeDevices().map { OMSDeviceInfo($0) }
    }

    private init() {
        let hapticManager = OpenMTManager.shared()
        protectedHapticManager = .init(uncheckedState: hapticManager)
        protectedCaptureManager = .init(uncheckedState: Self.loadManagerV2())
    }

    private static func loadManagerV2() -> OpenMTManagerV2? {
        guard OpenMTManagerV2.systemSupportsMultitouch() else {
            return nil
        }
        return OpenMTManagerV2.sharedManager()
    }

    @discardableResult
    func startListening() -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self),
              protectedRawListener.withLockUnchecked({ $0 == nil }) else {
            return false
        }
        let listener = captureManager.addRawListener(callback: { [weak self] touches, count, timestamp, frame, deviceID in
            self?.handleRawFrame(
                touches: touches,
                count: Int(count),
                timestamp: timestamp,
                frame: Int(frame),
                deviceID: deviceID
            )
        })
        protectedRawListener.withLockUnchecked { $0 = listener }
        return true
    }

    @discardableResult
    func stopListening() -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self),
              let listener = protectedRawListener.withLockUnchecked(\.self) else {
            return false
        }
        captureManager.removeRawListener(listener)
        protectedRawListener.withLockUnchecked { $0 = nil }
        return true
    }

    @discardableResult
    func setActiveDevices(_ devices: [OMSDeviceInfo]) -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self) else { return false }
        let deviceInfos = devices.map { $0.deviceInfo }
        guard captureManager.setActiveDevices(deviceInfos) else {
            return false
        }
        _ = protectedHapticManager.withLockUnchecked { manager in
            manager?.setActiveDevices(deviceInfos) ?? false
        }
        return true
    }

    var isHapticEnabled: Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.isHapticEnabled()
    }

    @discardableResult
    func setHapticEnabled(_ enabled: Bool) -> Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.setHapticEnabled(enabled)
    }

    @discardableResult
    func triggerRawHaptic(
        actuationID: Int32,
        unknown1: UInt32,
        unknown2: Float,
        unknown3: Float,
        deviceID: String? = nil
    ) -> Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.triggerRawHaptic(
            actuationID,
            unknown1: unknown1,
            unknown2: unknown2,
            unknown3: unknown3,
            deviceID: deviceID
        )
    }

    @discardableResult
    func playHapticFeedback(strength: Double, deviceID: String? = nil) -> Bool {
        let clampedStrength = min(max(strength, 0.0), 1.0)
        guard clampedStrength > 0 else {
            return false
        }
        let actuationStep = Int(max(0, min(5, Int(round(clampedStrength * 5.0)))))
        let actuationID = Int32(1 + actuationStep)
        let sharpness = Float(10.0 + (clampedStrength * 20.0))
        return triggerRawHaptic(
            actuationID: actuationID,
            unknown1: 0,
            unknown2: sharpness,
            unknown3: 0,
            deviceID: deviceID
        )
    }

    func deviceIndex(for deviceID: String) -> Int? {
        guard let parsedID = UInt64(deviceID) else { return nil }
        return resolveDeviceIndex(for: parsedID)
    }

    func deviceIndex(for deviceIDNumeric: UInt64) -> Int? {
        guard deviceIDNumeric > 0 else { return nil }
        return resolveDeviceIndex(for: deviceIDNumeric)
    }

    private func handleRawFrame(
        touches: UnsafePointer<MTTouch>?,
        count: Int,
        timestamp: TimeInterval,
        frame _: Int,
        deviceID: UInt64
    ) {
#if DEBUG
        if Thread.isMainThread {
            assertionFailure("OpenMT raw callback is running on the main thread; avoid UI access and move UI work to the main actor.")
        }
        let signpostState = signposter.beginInterval("OpenMTRawFrame")
        defer { signposter.endInterval("OpenMTRawFrame", signpostState) }
#endif
        let deviceIndex = resolveDeviceIndex(for: deviceID)
        let deviceIDString = deviceIDString(for: deviceID)
        guard let handler = rawFrameHandler.withLockUnchecked({ $0 }) else {
            return
        }
        guard let touches, count > 0 else {
            handler(
                OMSRawTouchFrame(
                    deviceID: deviceIDString,
                    deviceIDNumeric: deviceID,
                    deviceIndex: deviceIndex,
                    timestamp: timestamp,
                    buffer: nil,
                    releaseHandler: nil
                )
            )
            return
        }
        let buffer = takeBuffer(capacity: count)
        buffer.write(from: touches, count: count)
        let rawFrame = OMSRawTouchFrame(
            deviceID: deviceIDString,
            deviceIDNumeric: deviceID,
            deviceIndex: deviceIndex,
            timestamp: timestamp,
            buffer: buffer,
            releaseHandler: { [rawBufferPool] buffer in
                buffer.reset()
                rawBufferPool.withLockUnchecked { pool in
                    pool.append(buffer)
                    return ()
                }
            }
        )
        handler(rawFrame)
    }

    private func resolveDeviceIndex(for deviceID: UInt64) -> Int {
        protectedDeviceIndexStore.withLockUnchecked { store in
            store.index(for: deviceID)
        }
    }

    private func deviceIDString(for deviceID: UInt64) -> String {
        guard deviceID > 0 else { return "Unknown" }
        return deviceIDStringCache.withLockUnchecked { cache in
            if let cached = cache[deviceID] {
                return cached
            }
            let value = String(deviceID)
            cache[deviceID] = value
            return value
        }
    }

    private func takeBuffer(capacity: Int) -> RawTouchBuffer {
        rawBufferPool.withLockUnchecked { pool in
            if let index = pool.lastIndex(where: { $0.capacity >= capacity }) {
                let buffer = pool.remove(at: index)
                buffer.reset()
                return buffer
            }
            return RawTouchBuffer(capacity: max(8, capacity))
        }
    }
}

private struct DeviceIndexStore: Sendable {
    private var id0: UInt64?
    private var id1: UInt64?
    private var last0: UInt64 = 0
    private var last1: UInt64 = 0
    private var counter: UInt64 = 0

    mutating func index(for deviceID: UInt64) -> Int {
        if id0 == deviceID {
            last0 = tick()
            return 0
        }
        if id1 == deviceID {
            last1 = tick()
            return 1
        }
        let current = tick()
        if id0 == nil {
            id0 = deviceID
            last0 = current
            return 0
        }
        if id1 == nil {
            id1 = deviceID
            last1 = current
            return 1
        }
        if last0 <= last1 {
            id0 = deviceID
            last0 = current
            return 0
        }
        id1 = deviceID
        last1 = current
        return 1
    }

    private mutating func tick() -> UInt64 {
        counter &+= 1
        return counter
    }
}

private final class RawTouchBuffer {
    let capacity: Int
    private let storage: UnsafeMutablePointer<OMSRawTouch>
    private(set) var count: Int = 0

    var view: OMSRawTouchBufferView {
        OMSRawTouchBufferView(baseAddress: UnsafePointer(storage), count: count)
    }

    init(capacity: Int) {
        self.capacity = capacity
        storage = UnsafeMutablePointer<OMSRawTouch>.allocate(capacity: capacity)
    }

    deinit {
        reset()
        storage.deallocate()
    }

    func reset() {
        guard count > 0 else { return }
        storage.deinitialize(count: count)
        count = 0
    }

    func write(from rawTouches: UnsafePointer<MTTouch>, count: Int) {
        precondition(count <= capacity)
        reset()
        for index in 0..<count {
            let touch = rawTouches[index]
            let state = OMSState(OpenMTState(rawValue: UInt(touch.state)) ?? .notTouching) ?? .notTouching
            storage.advanced(by: index).initialize(to: OMSRawTouch(
                id: Int32(touch.identifier),
                posX: touch.normalizedPosition.position.x,
                posY: touch.normalizedPosition.position.y,
                total: touch.total,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: state
            ))
        }
        self.count = count
    }
}
