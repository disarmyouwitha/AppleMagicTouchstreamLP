/*
 OMSManager.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

@preconcurrency import OpenMultitouchSupportXCF
import os

public struct OMSDeviceInfo: Sendable, Hashable {
    public let deviceName: String
    public let deviceID: String
    public let deviceIDNumeric: UInt64
    public let isBuiltIn: Bool
    internal nonisolated(unsafe) let deviceInfo: OpenMTDeviceInfo
    
    internal init(_ deviceInfo: OpenMTDeviceInfo) {
        self.deviceInfo = deviceInfo
        self.deviceName = deviceInfo.deviceName
        self.deviceID = deviceInfo.deviceID
        self.deviceIDNumeric = UInt64(deviceInfo.deviceID) ?? 0
        self.isBuiltIn = deviceInfo.isBuiltIn
    }
}

public enum OMSHapticIntensity: Int32, CaseIterable, Sendable {
    case weak = 3
    case medium = 4
    case strong = 6
}

public enum OMSHapticPattern: Int32, CaseIterable, Sendable {
    case generic = 15
    case alignment = 16
    case level = 5  // Changed from 17 to 5 (valid ID)
}

public final class OMSManager: Sendable {
    public static let shared = OMSManager()

    private let protectedManager: OSAllocatedUnfairLock<OpenMTManager?>
    private let protectedRawListener = OSAllocatedUnfairLock<OpenMTListener?>(uncheckedState: nil)
    private let protectedTimestampEnabled = OSAllocatedUnfairLock<Bool>(uncheckedState: true)
    private let protectedDeviceIndexStore = OSAllocatedUnfairLock<DeviceIndexStore>(
        uncheckedState: DeviceIndexStore()
    )
    private let deviceIDStringCache = OSAllocatedUnfairLock<[UInt64: String]>(
        uncheckedState: [:]
    )
    private let touchContinuations = OSAllocatedUnfairLock<[UUID: AsyncStream<[OMSTouchData]>.Continuation]>(
        uncheckedState: [:]
    )
    private struct RawContinuationStore: Sendable {
        var byID: [UUID: AsyncStream<OMSRawTouchFrame>.Continuation] = [:]
        var list: [AsyncStream<OMSRawTouchFrame>.Continuation] = []
    }
    private let rawContinuationStore = OSAllocatedUnfairLock<RawContinuationStore>(
        uncheckedState: RawContinuationStore()
    )
    private let rawBufferPool = OSAllocatedUnfairLock<[RawTouchBuffer]>(uncheckedState: [])
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "OpenMT"
    )
#endif
    public var touchDataStream: AsyncStream<[OMSTouchData]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task.detached(priority: .userInitiated) { [rawTouchStream] in
                for await frame in rawTouchStream {
                    let data = Self.buildTouchData(from: frame)
                    continuation.yield(data)
                    frame.release()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public var rawTouchStream: AsyncStream<OMSRawTouchFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let id = UUID()
            rawContinuationStore.withLockUnchecked { store in
                store.byID[id] = continuation
                store.list = Array(store.byID.values)
            }
            continuation.onTermination = { [rawContinuationStore] _ in
                rawContinuationStore.withLockUnchecked { store in
                    store.byID.removeValue(forKey: id)
                    store.list = Array(store.byID.values)
                }
            }
        }
    }

    public func rawTouchStream(forDeviceIDs deviceIDs: Set<UInt64>) -> AsyncStream<OMSRawTouchFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task.detached(priority: .userInitiated) { [rawTouchStream] in
                for await frame in rawTouchStream {
                    if deviceIDs.contains(frame.deviceIDNumeric) {
                        continuation.yield(frame)
                    } else {
                        frame.release()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public var isListening: Bool {
        protectedRawListener.withLockUnchecked { $0 != nil }
    }

    public var isTimestampEnabled: Bool {
        get { protectedTimestampEnabled.withLockUnchecked(\.self) }
        set { protectedTimestampEnabled.withLockUnchecked { $0 = newValue } }
    }
    
    public var availableDevices: [OMSDeviceInfo] {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return [] }
        xcfManager.refreshAvailableDevices()
        return xcfManager.availableDevices().map { OMSDeviceInfo($0) }
    }
    
    public var activeDevices: [OMSDeviceInfo] {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return [] }
        return xcfManager.activeDevices().map { OMSDeviceInfo($0) }
    }

    private init() {
        protectedManager = .init(uncheckedState: OpenMTManager.shared())
    }

    @discardableResult
    public func startListening() -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self),
              protectedRawListener.withLockUnchecked({ $0 == nil }) else {
            return false
        }
        let listener = xcfManager.addRawListener(callback: { [weak self] touches, count, timestamp, frame, deviceID in
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
    public func stopListening() -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self),
              let listener = protectedRawListener.withLockUnchecked(\.self) else {
            return false
        }
        xcfManager.removeRawListener(listener)
        protectedRawListener.withLockUnchecked { $0 = nil }
        return true
    }
    
    @discardableResult
    public func setActiveDevices(_ devices: [OMSDeviceInfo]) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        let deviceInfos = devices.map { $0.deviceInfo }
        return xcfManager.setActiveDevices(deviceInfos)
    }
    
    public var isHapticEnabled: Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.isHapticEnabled()
    }
    
    @discardableResult
    public func setHapticEnabled(_ enabled: Bool) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.setHapticEnabled(enabled)
    }
    
    @discardableResult
    public func triggerRawHaptic(actuationID: Int32, unknown1: UInt32, unknown2: Float, unknown3: Float, deviceID: String? = nil) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.triggerRawHaptic(actuationID, unknown1: unknown1, unknown2: unknown2, unknown3: unknown3, deviceID: deviceID)
    }

    @discardableResult
    public func playHapticFeedback(strength: Double, deviceID: String? = nil) -> Bool {
        let clampedStrength = min(max(strength, 0.0), 1.0)
        guard clampedStrength > 0 else {
            return false
        }
        let actuationStep = Int(max(0, min(5, Int(round(clampedStrength * 5.0)))))
        let actuationID = Int32(1 + actuationStep) // falls in 1..6
        let sharpness = Float(10.0 + (clampedStrength * 20.0))
        return triggerRawHaptic(actuationID: actuationID, unknown1: 0, unknown2: sharpness, unknown3: 0, deviceID: deviceID)
    }

    public func deviceIndex(for deviceID: String) -> Int? {
        guard let parsedID = UInt64(deviceID) else { return nil }
        return resolveDeviceIndex(for: parsedID)
    }

    public func deviceIndex(for deviceIDNumeric: UInt64) -> Int? {
        guard deviceIDNumeric > 0 else { return nil }
        return resolveDeviceIndex(for: deviceIDNumeric)
    }

    @objc func listen(_ event: OpenMTEvent) {
#if DEBUG
        let signpostState = signposter.beginInterval("OpenMTEvent")
        defer { signposter.endInterval("OpenMTEvent", signpostState) }
#endif
        guard let touches = (event.touches as NSArray) as? [OpenMTTouch] else { return }
        let frameTimestamp = event.timestamp
        let deviceID = event.deviceID ?? "Unknown"
        let numericID = UInt64(deviceID) ?? 0
        let deviceIndex = resolveDeviceIndex(for: numericID)
        if touches.isEmpty {
            emitRawTouchFrame(
                OMSRawTouchFrame(
                    deviceID: deviceID,
                    deviceIDNumeric: numericID,
                    deviceIndex: deviceIndex,
                    timestamp: frameTimestamp,
                    buffer: nil,
                    releaseHandler: nil
                )
            )
            return
        }
        let buffer = takeBuffer(capacity: touches.count)
        buffer.touches.reserveCapacity(touches.count)
        for touch in touches {
            buffer.touches.append(OMSRawTouch(
                id: touch.identifier,
                posX: touch.posX,
                posY: touch.posY,
                total: touch.total,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: touch.state
            ))
        }
        let frame = OMSRawTouchFrame(
            deviceID: deviceID,
            deviceIDNumeric: numericID,
            deviceIndex: deviceIndex,
            timestamp: frameTimestamp,
            buffer: buffer,
            releaseHandler: { [rawBufferPool] buffer in
                rawBufferPool.withLockUnchecked { pool in
                    pool.append(buffer)
                    return ()
                }
            }
        )
        emitRawTouchFrame(frame)
    }

    private func handleRawFrame(
        touches: UnsafePointer<MTTouch>?,
        count: Int,
        timestamp: TimeInterval,
        frame: Int,
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
        guard let touches, count > 0 else {
            emitRawTouchFrame(
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
        buffer.touches.reserveCapacity(count)
        for index in 0..<count {
            let touch = touches[index]
            let state = OpenMTState(rawValue: UInt(touch.state)) ?? .notTouching
            buffer.touches.append(OMSRawTouch(
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
        let rawFrame = OMSRawTouchFrame(
            deviceID: deviceIDString,
            deviceIDNumeric: deviceID,
            deviceIndex: deviceIndex,
            timestamp: timestamp,
            buffer: buffer,
            releaseHandler: { [rawBufferPool] buffer in
                rawBufferPool.withLockUnchecked { pool in
                    pool.append(buffer)
                    return ()
                }
            }
        )
        emitRawTouchFrame(rawFrame)
    }

    private func emitTouchData(_ data: [OMSTouchData]) {
        let continuations = touchContinuations.withLockUnchecked { Array($0.values) }
        for continuation in continuations {
            _ = continuation.yield(data)
        }
    }

    private func emitRawTouchFrame(_ frame: OMSRawTouchFrame) {
        let continuations = rawContinuationStore.withLockUnchecked { $0.list }
        for continuation in continuations {
            _ = continuation.yield(frame)
        }
        if continuations.isEmpty {
            frame.release()
        }
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
            if let buffer = pool.popLast() {
                buffer.touches.removeAll(keepingCapacity: true)
                if buffer.touches.capacity < capacity {
                    buffer.touches.reserveCapacity(capacity)
                }
                return buffer
            }
            return RawTouchBuffer(capacity: max(8, capacity))
        }
    }

    public static func buildTouchData(into buffer: inout [OMSTouchData], from frame: OMSRawTouchFrame) {
        buffer.removeAll(keepingCapacity: true)
        let formattedTimestamp = shared.protectedTimestampEnabled.withLockUnchecked(\.self)
            ? String(format: "%.5f", frame.timestamp)
            : nil
        let deviceID = frame.deviceID
        let deviceIndex = frame.deviceIndex
        let touches = frame.touches
        guard !touches.isEmpty else { return }
        buffer.reserveCapacity(touches.count)
        for touch in touches {
            guard let state = OMSState(touch.state) else { continue }
            buffer.append(OMSTouchData(
                deviceID: deviceID,
                deviceIndex: deviceIndex,
                id: touch.id,
                position: OMSPosition(x: touch.posX, y: touch.posY),
                total: touch.total,
                pressure: touch.pressure,
                axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                angle: touch.angle,
                density: touch.density,
                state: state,
                timestamp: frame.timestamp,
                formattedTimestamp: formattedTimestamp
            ))
        }
    }

    public static func buildTouchData(from frame: OMSRawTouchFrame) -> [OMSTouchData] {
        var data: [OMSTouchData] = []
        buildTouchData(into: &data, from: frame)
        return data
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

public struct OMSRawTouch: Sendable {
    public let id: Int32
    public let posX: Float
    public let posY: Float
    public let total: Float
    public let pressure: Float
    public let majorAxis: Float
    public let minorAxis: Float
    public let angle: Float
    public let density: Float
    public let state: OpenMTState
}

public final class OMSRawTouchFrame: @unchecked Sendable {
    public let deviceID: String
    public let deviceIDNumeric: UInt64
    public let deviceIndex: Int
    public let timestamp: TimeInterval
    private var buffer: RawTouchBuffer?
    private let releaseHandler: ((RawTouchBuffer) -> Void)?

    public var touches: [OMSRawTouch] {
        buffer?.touches ?? []
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

    public func release() {
        guard let buffer else { return }
        self.buffer = nil
        releaseHandler?(buffer)
    }

    deinit {
        release()
    }
}

private final class RawTouchBuffer {
    var touches: [OMSRawTouch]

    init(capacity: Int) {
        touches = []
        touches.reserveCapacity(capacity)
    }
}
