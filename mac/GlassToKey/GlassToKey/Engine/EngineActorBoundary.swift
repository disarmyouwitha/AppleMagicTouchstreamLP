import CoreGraphics
import Dispatch
import Foundation
import OpenMultitouchSupport
import os

struct RuntimeActiveDeviceRouting: Sendable, Equatable {
    var leftIndex: Int?
    var rightIndex: Int?
    var leftDeviceID: String?
    var rightDeviceID: String?
}

protocol RuntimeCoreBoundary: AnyObject, Sendable {
    var isCaptureActive: Bool { get }

    func ingest(
        _ frame: RuntimeRawFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool
    ) async -> RuntimeFrameProcessingResult
    func ingestLive(
        _ frame: OMSRawTouchFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool,
        renderSnapshotSink: (any RuntimeRenderSnapshotSink)?
    )
    func startCapture(
        configuration: AppKeymapProfile?,
        startUptimeNanoseconds: UInt64
    )
    func stopCapture() async -> ATPCaptureV3Codec.CaptureData?
    func activeDeviceRouting() async -> RuntimeActiveDeviceRouting
    func setListening(_ isListening: Bool) async
    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async
    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async
    func updateCustomButtons(_ buttons: [CustomButton]) async
    func updateKeyMappings(_ actions: LayeredKeyMappings) async
    func setPersistentLayer(_ layer: Int) async
    func updateHoldThreshold(_ seconds: TimeInterval) async
    func updateDragCancelDistance(_ distance: CGFloat) async
    func updateTypingGrace(_ milliseconds: Double) async
    func updateIntentMoveThreshold(_ millimeters: Double) async
    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async
    func updateAllowMouseTakeover(_ enabled: Bool) async
    func updateForceClickMin(_ grams: Double) async
    func updateForceClickCap(_ grams: Double) async
    func updateForceClickThreshold(_ grams: Double) async
    func updateHapticStrength(_ normalized: Double) async
    func updateSnapRadiusPercent(_ percent: Double) async
    func updateKeyboardModeEnabled(_ enabled: Bool) async
    func updateHoldRepeatEnabled(_ enabled: Bool) async
    func setKeymapEditingEnabled(_ enabled: Bool) async
    func updateTapClickCadence(_ milliseconds: Double) async
    func updateGestureActions(_ actions: GestureActionSet) async
    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) async
    func clearVisualCaches() async
    func reset(stopVoiceDictation: Bool) async
}

private struct RuntimeCaptureSessionState {
    let configuration: AppKeymapProfile?
    let startUptimeNanoseconds: UInt64
    var recordsBySequence: [UInt64: ProcessedFrameRecord] = [:]
    var orderedSequences: [UInt64] = []
    var pendingDispatchEventsBySequence: [UInt64: [ProcessedDispatchEvent]] = [:]
    var detachedDispatchEvents: [ProcessedDispatchEvent] = []

    mutating func store(_ record: ProcessedFrameRecord) -> ProcessedFrameRecord {
        let sequence = record.sequence
        var merged = record
        if let pendingDispatch = pendingDispatchEventsBySequence.removeValue(forKey: sequence) {
            merged.dispatchEvents.append(contentsOf: pendingDispatch)
        }
        if recordsBySequence[sequence] == nil {
            orderedSequences.append(sequence)
        }
        recordsBySequence[sequence] = merged
        return merged
    }

    mutating func appendDispatchEvent(_ event: RuntimeDispatchEvent) {
        let processed = ProcessedDispatchEvent(
            event: event,
            arrivalTicks: arrivalTicks(for: event.uptimeNanoseconds)
        )

        guard let sequence = event.sourceSequence else {
            detachedDispatchEvents.append(processed)
            return
        }

        if var record = recordsBySequence[sequence] {
            record.dispatchEvents.append(processed)
            recordsBySequence[sequence] = record
        } else {
            pendingDispatchEventsBySequence[sequence, default: []].append(processed)
        }
    }

    func arrivalTicks(for uptimeNanoseconds: UInt64) -> Int64 {
        let elapsed = uptimeNanoseconds >= startUptimeNanoseconds
            ? uptimeNanoseconds - startUptimeNanoseconds
            : 0
        return Int64(clamping: elapsed)
    }

    func snapshot() -> ATPCaptureV3Codec.CaptureData {
        let frameRecords = orderedSequences.compactMap { recordsBySequence[$0] }
        let detachedDispatchEvents = detachedDispatchEvents.map { dispatch in
            ATPCaptureV3Codec.DispatchSample(
                event: dispatch.event,
                arrivalTicks: dispatch.arrivalTicks
            )
        } + pendingDispatchEventsBySequence
            .sorted(by: { $0.key < $1.key })
            .flatMap { entry in
                entry.value.map { dispatch in
                    ATPCaptureV3Codec.DispatchSample(
                        event: dispatch.event,
                        arrivalTicks: dispatch.arrivalTicks
                    )
                }
            }

        return ATPCaptureV3Codec.CaptureData(
            configuration: configuration,
            frameRecords: frameRecords,
            detachedDispatchEvents: detachedDispatchEvents
        )
    }
}

final class RuntimeCore: RuntimeCoreBoundary, @unchecked Sendable {
    private static let queueSpecificValue: UInt8 = 1

    private let queue: DispatchQueue
    private let queueSpecificKey: DispatchSpecificKey<UInt8>
    private let dispatchService: DispatchService
    private var latestRender = RuntimeRenderSnapshot()
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private var leftDeviceID: String?
    private var rightDeviceID: String?
    private let processor: TouchProcessorEngine
    private let captureActiveLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private var captureSession: RuntimeCaptureSessionState?

    init(
        dispatchService: DispatchService = .shared,
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void = { _ in },
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void = { _ in },
        onDebugBindingDetected: @Sendable @escaping (ContentViewModel.KeyBinding) -> Void = { _ in },
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void = { _ in },
        onIntentStateChanged: @Sendable @escaping (SidePair<ContentViewModel.IntentDisplay>) -> Void = { _ in },
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void = { _ in }
    ) {
        let queue = DispatchQueue(
            label: "ink.ranna.glasstokey.engine.runtime",
            qos: .userInitiated
        )
        let queueSpecificKey = DispatchSpecificKey<UInt8>()
        queue.setSpecific(key: queueSpecificKey, value: Self.queueSpecificValue)

        self.queue = queue
        self.queueSpecificKey = queueSpecificKey
        self.dispatchService = dispatchService
        processor = TouchProcessorEngine(
            executionQueue: queue,
            dispatchService: dispatchService,
            onTypingEnabledChanged: onTypingEnabledChanged,
            onActiveLayerChanged: onActiveLayerChanged,
            onDebugBindingDetected: onDebugBindingDetected,
            onContactCountChanged: onContactCountChanged,
            onIntentStateChanged: onIntentStateChanged,
            onVoiceGestureChanged: onVoiceGestureChanged
        )

    }

    var isCaptureActive: Bool {
        captureActiveLock.withLockUnchecked { $0 }
    }

    func ingest(
        _ frame: RuntimeRawFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool
    ) async -> RuntimeFrameProcessingResult {
        await query {
            self.processIngest(
                frame,
                ingress: ingress,
                captureRenderSnapshot: captureRenderSnapshot
            )
        }
    }

    func ingestLive(
        _ frame: OMSRawTouchFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool,
        renderSnapshotSink: (any RuntimeRenderSnapshotSink)?
    ) {
        queue.async { [weak self] in
            guard let self else {
                frame.release()
                return
            }
            defer { frame.release() }

            let result = self.processIngest(
                frame,
                ingress: ingress,
                captureRenderSnapshot: captureRenderSnapshot
            )
            guard let renderSnapshot = result.renderSnapshot else { return }
            renderSnapshotSink?.submitRuntimeRenderSnapshot(renderSnapshot)
        }
    }

    func startCapture(
        configuration: AppKeymapProfile?,
        startUptimeNanoseconds: UInt64
    ) {
        runSync {
            self.captureSession = RuntimeCaptureSessionState(
                configuration: configuration,
                startUptimeNanoseconds: startUptimeNanoseconds
            )
            self.captureActiveLock.withLockUnchecked { $0 = true }
            self.dispatchService.setRecordedEventHandler { [weak self] event in
                self?.handleRecordedDispatchEvent(event)
            }
            self.processor.setCaptureFrameDiagnosticsEnabled(true)
        }
    }

    func stopCapture() async -> ATPCaptureV3Codec.CaptureData? {
        await query {
            let snapshot = self.captureSession?.snapshot()
            self.captureSession = nil
            self.captureActiveLock.withLockUnchecked { $0 = false }
            self.dispatchService.setRecordedEventHandler(nil)
            self.processor.setCaptureFrameDiagnosticsEnabled(false)
            return snapshot
        }
    }

    func activeDeviceRouting() async -> RuntimeActiveDeviceRouting {
        await query {
            RuntimeActiveDeviceRouting(
                leftIndex: self.leftDeviceIndex,
                rightIndex: self.rightDeviceIndex,
                leftDeviceID: self.leftDeviceID,
                rightDeviceID: self.rightDeviceID
            )
        }
    }

    func setListening(_ isListening: Bool) async {
        await run {
            self.processor.setListening(isListening)
        }
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async {
        await run {
            self.leftDeviceIndex = leftIndex
            self.rightDeviceIndex = rightIndex
            self.leftDeviceID = leftDeviceID
            self.rightDeviceID = rightDeviceID
            self.processor.updateActiveDevices(
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                leftDeviceID: leftDeviceID,
                rightDeviceID: rightDeviceID
            )
        }
    }

    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async {
        await run {
            self.processor.updateLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftLabels,
                rightLabels: rightLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: trackpadWidthMm
            )
        }
    }

    func updateCustomButtons(_ buttons: [CustomButton]) async {
        await run {
            self.processor.updateCustomButtons(buttons)
        }
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) async {
        await run {
            self.processor.updateKeyMappings(actions)
        }
    }

    func setPersistentLayer(_ layer: Int) async {
        await run {
            self.processor.setPersistentLayer(layer)
        }
    }

    func updateHoldThreshold(_ seconds: TimeInterval) async {
        await run {
            self.processor.updateHoldThreshold(seconds)
        }
    }

    func updateDragCancelDistance(_ distance: CGFloat) async {
        await run {
            self.processor.updateDragCancelDistance(distance)
        }
    }

    func updateTypingGrace(_ milliseconds: Double) async {
        await run {
            self.processor.updateTypingGrace(milliseconds)
        }
    }

    func updateIntentMoveThreshold(_ millimeters: Double) async {
        await run {
            self.processor.updateIntentMoveThreshold(millimeters)
        }
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async {
        await run {
            self.processor.updateIntentVelocityThreshold(millimetersPerSecond)
        }
    }

    func updateAllowMouseTakeover(_ enabled: Bool) async {
        await run {
            self.processor.updateAllowMouseTakeover(enabled)
        }
    }

    func updateForceClickMin(_ grams: Double) async {
        await run {
            self.processor.updateForceClickMin(grams)
        }
    }

    func updateForceClickCap(_ grams: Double) async {
        await run {
            self.processor.updateForceClickCap(grams)
        }
    }

    func updateForceClickThreshold(_ grams: Double) async {
        await run {
            self.processor.updateForceClickThreshold(grams)
        }
    }

    func updateHapticStrength(_ normalized: Double) async {
        await run {
            self.processor.updateHapticStrength(normalized)
        }
    }

    func updateSnapRadiusPercent(_ percent: Double) async {
        await run {
            self.processor.updateSnapRadiusPercent(percent)
        }
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) async {
        await run {
            self.processor.updateKeyboardModeEnabled(enabled)
        }
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) async {
        await run {
            self.processor.updateHoldRepeatEnabled(enabled)
        }
    }

    func setKeymapEditingEnabled(_ enabled: Bool) async {
        await run {
            self.processor.setKeymapEditingEnabled(enabled)
        }
    }

    func updateTapClickCadence(_ milliseconds: Double) async {
        await run {
            self.processor.updateTapClickCadence(milliseconds)
        }
    }

    func updateGestureActions(_ actions: GestureActionSet) async {
        await run {
            self.processor.updateGestureActions(actions)
        }
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) async {
        await run {
            self.processor.updateGestureRepeatCadenceMsById(cadenceById)
        }
    }

    func clearVisualCaches() async {
        await run {
            self.processor.clearVisualCaches()
        }
    }

    func reset(stopVoiceDictation: Bool) async {
        await run {
            self.processor.resetState(stopVoiceDictation: stopVoiceDictation)
            self.latestRender = RuntimeRenderSnapshot()
        }
    }

    private func runSync(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == Self.queueSpecificValue {
            work()
            return
        }
        queue.sync(execute: work)
    }

    private func run(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func query<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func handleRecordedDispatchEvent(_ event: RuntimeDispatchEvent) {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == Self.queueSpecificValue {
            recordDispatchEvent(event)
            return
        }
        queue.async { [weak self] in
            self?.recordDispatchEvent(event)
        }
    }

    private func recordDispatchEvent(_ event: RuntimeDispatchEvent) {
        guard var captureSession else { return }
        captureSession.appendDispatchEvent(event)
        self.captureSession = captureSession
    }

    private func processIngest(
        _ frame: RuntimeRawFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool
    ) -> RuntimeFrameProcessingResult {
        let diagnostic = processor.processRuntimeRawFrame(frame)
        let renderSnapshotForRecord = captureRenderSnapshot || captureSession != nil
            ? updatedRenderSnapshot(from: frame)
            : nil
        let renderedSnapshot = captureRenderSnapshot ? renderSnapshotForRecord : nil
        let processedRecord = makeProcessedRecord(
            frame: frame,
            ingress: ingress,
            diagnostic: diagnostic,
            renderSnapshot: renderSnapshotForRecord
        )
        return RuntimeFrameProcessingResult(
            renderSnapshot: renderedSnapshot,
            processedFrameRecord: processedRecord
        )
    }

    deinit {
        dispatchService.setRecordedEventHandler(nil)
    }

    private func processIngest(
        _ frame: OMSRawTouchFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        captureRenderSnapshot: Bool
    ) -> RuntimeFrameProcessingResult {
        let diagnostic = processor.processRawFrame(frame)
        let renderSnapshotForRecord = captureRenderSnapshot || captureSession != nil
            ? updatedRenderSnapshot(from: frame)
            : nil
        let renderedSnapshot = captureRenderSnapshot ? renderSnapshotForRecord : nil
        let processedRecord = makeProcessedRecord(
            frame: RuntimeRawFrame(sequence: frame.sequence, frame: frame),
            ingress: ingress,
            diagnostic: diagnostic,
            renderSnapshot: renderSnapshotForRecord
        )
        return RuntimeFrameProcessingResult(
            renderSnapshot: renderedSnapshot,
            processedFrameRecord: processedRecord
        )
    }

    private func makeProcessedRecord(
        frame: RuntimeRawFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        diagnostic: RuntimeFrameDiagnostic?,
        renderSnapshot: RuntimeRenderSnapshot?
    ) -> ProcessedFrameRecord? {
        guard var captureSession else { return nil }

        let uptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        var record = ProcessedFrameRecord(
            frame: frame,
            arrivalTicks: captureSession.arrivalTicks(for: uptimeNanoseconds),
            ingress: ingress,
            diagnostic: diagnostic.map { diagnostic in
                var updatedDiagnostic = diagnostic
                updatedDiagnostic.ingress = updatedDiagnostic.ingress ?? ingress
                return updatedDiagnostic
            },
            dispatchEvents: [],
            renderUpdate: renderSnapshot.map { snapshot in
                ProcessedRenderUpdate(
                    revision: snapshot.revision,
                    snapshot: snapshot
                )
            }
        )
        record = captureSession.store(record)
        self.captureSession = captureSession
        return record
    }

    private func updatedRenderSnapshot(from frame: OMSRawTouchFrame) -> RuntimeRenderSnapshot {
        updateRenderSnapshot(from: frame)
        return latestRender
    }

    private func updatedRenderSnapshot(from frame: RuntimeRawFrame) -> RuntimeRenderSnapshot {
        updateRenderSnapshot(from: frame)
        return latestRender
    }

    private func updateRenderSnapshot(from frame: OMSRawTouchFrame) {
        let deviceIndex = frame.deviceIndex
        let matchedLeft = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let matchedRight = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        guard matchedLeft || matchedRight else { return }

        let touches = Self.renderTouches(from: frame)
        if matchedLeft {
            latestRender.leftTouches = touches
        }
        if matchedRight {
            latestRender.rightTouches = touches
        }
        latestRender.hasTransitionState = Self.hasTransitionState(
            left: latestRender.leftTouches,
            right: latestRender.rightTouches
        )
        latestRender.revision &+= 1
    }

    private func updateRenderSnapshot(from frame: RuntimeRawFrame) {
        let deviceIndex = frame.deviceIndex
        let matchedLeft = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let matchedRight = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        guard matchedLeft || matchedRight else { return }

        let touches = Self.renderTouches(from: frame)
        if matchedLeft {
            latestRender.leftTouches = touches
        }
        if matchedRight {
            latestRender.rightTouches = touches
        }
        latestRender.hasTransitionState = Self.hasTransitionState(
            left: latestRender.leftTouches,
            right: latestRender.rightTouches
        )
        latestRender.revision &+= 1
    }

    private static func renderTouches(from frame: OMSRawTouchFrame) -> [OMSTouchData] {
        let touches = frame.touches
        guard !touches.isEmpty else { return [] }
        return touches.map { touch in
            OMSTouchData(
                deviceID: frame.deviceID,
                deviceIndex: frame.deviceIndex,
                id: touch.id,
                position: OMSPosition(x: touch.posX, y: touch.posY),
                total: touch.total,
                pressure: touch.pressure,
                axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                angle: touch.angle,
                density: touch.density,
                state: touch.state,
                timestamp: frame.timestamp
            )
        }
    }

    private static func renderTouches(from frame: RuntimeRawFrame) -> [OMSTouchData] {
        let touches = frame.rawTouches
        let deviceID = String(frame.deviceNumericID)
        if !touches.isEmpty {
            return touches.map { touch in
                OMSTouchData(
                    deviceID: deviceID,
                    deviceIndex: frame.deviceIndex,
                    id: touch.id,
                    position: OMSPosition(x: touch.posX, y: touch.posY),
                    total: touch.total,
                    pressure: touch.pressure,
                    axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                    angle: touch.angle,
                    density: touch.density,
                    state: touch.state,
                    timestamp: frame.timestamp
                )
            }
        }
        return frame.contacts.map { contact in
            OMSTouchData(
                deviceID: deviceID,
                deviceIndex: frame.deviceIndex,
                id: contact.id,
                position: OMSPosition(x: contact.posX, y: contact.posY),
                total: 0,
                pressure: contact.pressure,
                axis: OMSAxis(major: contact.majorAxis, minor: contact.minorAxis),
                angle: contact.angle,
                density: contact.density,
                state: contact.state,
                timestamp: frame.timestamp
            )
        }
    }

    private static func hasTransitionState(
        left: [OMSTouchData],
        right: [OMSTouchData]
    ) -> Bool {
        func containsTransition(_ touches: [OMSTouchData]) -> Bool {
            for touch in touches {
                switch touch.state {
                case .starting, .breaking, .leaving:
                    return true
                default:
                    break
                }
            }
            return false
        }
        return containsTransition(left) || containsTransition(right)
    }
}
