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
            Self.upsertDispatchEvent(processed, into: &detachedDispatchEvents)
            return
        }

        if var record = recordsBySequence[sequence] {
            Self.upsertDispatchEvent(processed, into: &record.dispatchEvents)
            recordsBySequence[sequence] = record
        } else {
            var pending = pendingDispatchEventsBySequence[sequence, default: []]
            Self.upsertDispatchEvent(processed, into: &pending)
            pendingDispatchEventsBySequence[sequence] = pending
        }
    }

    private static func upsertDispatchEvent(
        _ processed: ProcessedDispatchEvent,
        into events: inout [ProcessedDispatchEvent]
    ) {
        if let index = events.firstIndex(where: { $0.event.commandID == processed.event.commandID }) {
            events[index] = processed
        } else {
            events.append(processed)
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
        let renderedSnapshot = captureRenderSnapshot
            ? updatedRenderSnapshot(from: frame)
            : nil
        let processedRecord = makeProcessedRecord(
            frame: frame,
            ingress: ingress,
            diagnostic: diagnostic
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
        let renderedSnapshot = captureRenderSnapshot
            ? updatedRenderSnapshot(from: frame)
            : nil
        let processedRecord = makeProcessedRecord(
            frame: RuntimeRawFrame(sequence: frame.sequence, frame: frame),
            ingress: ingress,
            diagnostic: diagnostic
        )
        return RuntimeFrameProcessingResult(
            renderSnapshot: renderedSnapshot,
            processedFrameRecord: processedRecord
        )
    }

    private func makeProcessedRecord(
        frame: RuntimeRawFrame,
        ingress: RuntimeCaptureIngressSnapshot?,
        diagnostic: RuntimeFrameDiagnostic?
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
            dispatchEvents: []
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
                timestamp: frame.timestamp,
                telemetry: touch.telemetry
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
                    timestamp: frame.timestamp,
                    telemetry: touch.telemetry
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
                timestamp: frame.timestamp,
                telemetry: contact.telemetry
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

#if SWIFT_PACKAGE
import ReplayFixtureKit

/// Runs the same recognizer compiled into GlassToKey, with no native output.
/// App/UI model types are compiled for compatibility; no model or application is started.
@MainActor
final class ProductionReplaySession {
    final class Output: @unchecked Sendable {
        var events: [RuntimeDispatchEvent] = []
        var voiceTransitions: [Bool] = []
        var intents = SidePair(left: ContentViewModel.IntentDisplay.idle,
                               right: ContentViewModel.IntentDisplay.idle)
    }
    let scheduler: ReplayTouchEngineScheduler
    let output = Output()
    let engine: TouchProcessorEngine

    init(startTime: TimeInterval = 0) {
        let scheduler = ReplayTouchEngineScheduler(startTime: startTime)
        self.scheduler = scheduler
        let output = self.output
        let sink = DispatchService(recordingWith: scheduler) { output.events.append($0) }
        engine = TouchProcessorEngine(
            executionQueue: DispatchQueue(label: "ink.ranna.GlassToKey.OfflineRecognition"),
            dispatchService: sink, scheduler: scheduler,
            voiceSessionChanged: { output.voiceTransitions.append($0) },
            onTypingEnabledChanged: { _ in }, onActiveLayerChanged: { _ in },
            onDebugBindingDetected: { _ in }, onContactCountChanged: { _ in },
            onIntentStateChanged: { output.intents = $0 }, onVoiceGestureChanged: { _ in }
        )
        engine.setCaptureFrameDiagnosticsEnabled(true)
    }

    func configure(profile: AppKeymapProfile, leftIndex: Int?, rightIndex: Int?) {
        let preset = TrackpadLayoutPreset.resolveByNameOrDefault(profile.layoutPreset)
        let name = preset.rawValue
        let size = CGSize(width: ContentView.trackpadWidthMM * ContentView.displayScale,
                          height: ContentView.trackpadHeightMM * ContentView.displayScale)
        let settings = profile.columnSettingsByLayout[name]
            ?? ColumnLayoutDefaults.defaultSettings(columns: preset.columns)
        let geometry = profile.keyGeometryByLayout?[name] ?? [:]
        let spacing = profile.keySpacingPercentByLayout?[name] ?? LayoutKeySpacingDefaults.defaultPercent
        func layout(mirrored: Bool) -> ContentViewModel.Layout {
            if preset == .mobile {
                return mirrored ? ContentViewModel.Layout(keyRects: [], trackpadSize: size)
                    : ContentView.makeMobileKeyLayout(size: size, keyGeometryOverrides: geometry)
            }
            return ContentView.makeKeyLayout(
                size: size, keyWidth: ContentView.baseKeyWidthMM,
                keyHeight: ContentView.baseKeyHeightMM,
                columns: preset.columns, rows: preset.rows,
                trackpadWidth: ContentView.trackpadWidthMM,
                trackpadHeight: ContentView.trackpadHeightMM,
                columnAnchorsMM: preset.columnAnchors, columnSettings: settings,
                keySpacingPercent: spacing, keyGeometryOverrides: geometry, mirrored: mirrored
            )
        }
        engine.updateLayouts(leftLayout: layout(mirrored: true), rightLayout: layout(mirrored: false),
                             leftLabels: preset.leftLabels, rightLabels: preset.rightLabels,
                             trackpadSize: size, trackpadWidthMm: ContentView.trackpadWidthMM)
        engine.updateActiveDevices(leftIndex: leftIndex, rightIndex: rightIndex,
                                   leftDeviceID: profile.leftDeviceID, rightDeviceID: profile.rightDeviceID)
        let layers = profile.customButtonsByLayout[name] ?? [:]
        engine.updateCustomButtons(layers.keys.sorted().flatMap { layers[$0] ?? [] })
        engine.updateKeyMappings(profile.keyMappingsByLayout?[name] ?? [:])
        engine.updateHoldThreshold(profile.tapHoldDurationMs / 1000)
        engine.updateDragCancelDistance(CGFloat(profile.dragCancelDistance))
        engine.updateTypingGrace(profile.typingGraceMs)
        engine.updateIntentMoveThreshold(profile.intentMoveThresholdMm)
        engine.updateIntentVelocityThreshold(profile.intentVelocityThresholdMmPerSec)
        engine.updateForceClickMin(profile.forceClickMin ?? GlassToKeySettings.forceClickMin)
        engine.updateForceClickCap(profile.forceClickCap)
        engine.updateForceClickThreshold(profile.forceClickThreshold)
        engine.updateHapticStrength(profile.hapticStrength)
        engine.updateSnapRadiusPercent(profile.snapRadiusPercent)
        engine.updateKeyboardModeEnabled(profile.keyboardModeEnabled)
        engine.updateHoldRepeatEnabled(profile.holdRepeatEnabled)
        engine.updateTapClickCadence(profile.tapClickCadenceMs)
        engine.updateGestureRepeatCadenceMsById(profile.gestureRepeatCadenceMsById)
        engine.updateGestureActions(GestureActionSet(
            twoFingerTap: KeyActionCatalog.action(for: profile.twoFingerTapGestureAction ?? GlassToKeySettings.twoFingerTapGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerTap: KeyActionCatalog.action(for: profile.threeFingerTapGestureAction ?? GlassToKeySettings.threeFingerTapGestureActionLabel) ?? KeyActionCatalog.noneAction,
            twoFingerHold: KeyActionCatalog.action(for: profile.twoFingerHoldGestureAction ?? GlassToKeySettings.twoFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerHold: KeyActionCatalog.action(for: profile.threeFingerHoldGestureAction ?? GlassToKeySettings.threeFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerHold: KeyActionCatalog.action(for: profile.fourFingerHoldGestureAction ?? GlassToKeySettings.fourFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction,
            outerCornersHold: KeyActionCatalog.action(for: profile.outerCornersHoldGestureAction ?? GlassToKeySettings.outerCornersHoldGestureActionLabel) ?? KeyActionCatalog.noneAction,
            innerCornersHold: KeyActionCatalog.action(for: profile.innerCornersHoldGestureAction ?? GlassToKeySettings.innerCornersHoldGestureActionLabel) ?? KeyActionCatalog.noneAction,
            leftEdgeUp: KeyActionCatalog.action(for: profile.leftEdgeUpGestureAction ?? GlassToKeySettings.leftEdgeUpGestureActionLabel) ?? KeyActionCatalog.noneAction,
            leftEdgeDown: KeyActionCatalog.action(for: profile.leftEdgeDownGestureAction ?? GlassToKeySettings.leftEdgeDownGestureActionLabel) ?? KeyActionCatalog.noneAction,
            rightEdgeUp: KeyActionCatalog.action(for: profile.rightEdgeUpGestureAction ?? GlassToKeySettings.rightEdgeUpGestureActionLabel) ?? KeyActionCatalog.noneAction,
            rightEdgeDown: KeyActionCatalog.action(for: profile.rightEdgeDownGestureAction ?? GlassToKeySettings.rightEdgeDownGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topEdgeLeft: KeyActionCatalog.action(for: profile.topEdgeLeftGestureAction ?? GlassToKeySettings.topEdgeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topEdgeRight: KeyActionCatalog.action(for: profile.topEdgeRightGestureAction ?? GlassToKeySettings.topEdgeRightGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomEdgeLeft: KeyActionCatalog.action(for: profile.bottomEdgeLeftGestureAction ?? GlassToKeySettings.bottomEdgeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomEdgeRight: KeyActionCatalog.action(for: profile.bottomEdgeRightGestureAction ?? GlassToKeySettings.bottomEdgeRightGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerSwipeLeft: KeyActionCatalog.action(for: profile.threeFingerSwipeLeftGestureAction ?? GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerSwipeRight: KeyActionCatalog.action(for: profile.threeFingerSwipeRightGestureAction ?? GlassToKeySettings.threeFingerSwipeRightGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerSwipeUp: KeyActionCatalog.action(for: profile.threeFingerSwipeUpGestureAction ?? GlassToKeySettings.threeFingerSwipeUpGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerSwipeDown: KeyActionCatalog.action(for: profile.threeFingerSwipeDownGestureAction ?? GlassToKeySettings.threeFingerSwipeDownGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerSwipeLeft: KeyActionCatalog.action(for: profile.fourFingerSwipeLeftGestureAction ?? GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerSwipeRight: KeyActionCatalog.action(for: profile.fourFingerSwipeRightGestureAction ?? GlassToKeySettings.fourFingerSwipeRightGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerSwipeUp: KeyActionCatalog.action(for: profile.fourFingerSwipeUpGestureAction ?? GlassToKeySettings.fourFingerSwipeUpGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerSwipeDown: KeyActionCatalog.action(for: profile.fourFingerSwipeDownGestureAction ?? GlassToKeySettings.fourFingerSwipeDownGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fiveFingerSwipeLeft: KeyActionCatalog.action(for: profile.fiveFingerSwipeLeftGestureAction ?? GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fiveFingerSwipeRight: KeyActionCatalog.action(for: profile.fiveFingerSwipeRightGestureAction ?? GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fiveFingerSwipeUp: KeyActionCatalog.action(for: profile.fiveFingerSwipeUpGestureAction ?? GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fiveFingerSwipeDown: KeyActionCatalog.action(for: profile.fiveFingerSwipeDownGestureAction ?? GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topLeftCornerSwipe: KeyActionCatalog.action(for: profile.topLeftCornerSwipeGestureAction ?? GlassToKeySettings.topLeftCornerSwipeGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topRightCornerSwipe: KeyActionCatalog.action(for: profile.topRightCornerSwipeGestureAction ?? GlassToKeySettings.topRightCornerSwipeGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomLeftCornerSwipe: KeyActionCatalog.action(for: profile.bottomLeftCornerSwipeGestureAction ?? GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomRightCornerSwipe: KeyActionCatalog.action(for: profile.bottomRightCornerSwipeGestureAction ?? GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topLeftTriangle: KeyActionCatalog.action(for: profile.topLeftTriangleGestureAction ?? GlassToKeySettings.topLeftTriangleGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topRightTriangle: KeyActionCatalog.action(for: profile.topRightTriangleGestureAction ?? GlassToKeySettings.topRightTriangleGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomLeftTriangle: KeyActionCatalog.action(for: profile.bottomLeftTriangleGestureAction ?? GlassToKeySettings.bottomLeftTriangleGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomRightTriangle: KeyActionCatalog.action(for: profile.bottomRightTriangleGestureAction ?? GlassToKeySettings.bottomRightTriangleGestureActionLabel) ?? KeyActionCatalog.noneAction,
            upperLeftCornerClick: KeyActionCatalog.action(for: profile.upperLeftCornerClickGestureAction ?? GlassToKeySettings.upperLeftCornerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            upperRightCornerClick: KeyActionCatalog.action(for: profile.upperRightCornerClickGestureAction ?? GlassToKeySettings.upperRightCornerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            lowerLeftCornerClick: KeyActionCatalog.action(for: profile.lowerLeftCornerClickGestureAction ?? GlassToKeySettings.lowerLeftCornerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            lowerRightCornerClick: KeyActionCatalog.action(for: profile.lowerRightCornerClickGestureAction ?? GlassToKeySettings.lowerRightCornerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            threeFingerClick: KeyActionCatalog.action(for: profile.threeFingerClickGestureAction ?? GlassToKeySettings.threeFingerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            fourFingerClick: KeyActionCatalog.action(for: profile.fourFingerClickGestureAction ?? GlassToKeySettings.fourFingerClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topLeftForceClick: KeyActionCatalog.action(for: profile.topLeftForceClickGestureAction ?? GlassToKeySettings.topLeftForceClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            topRightForceClick: KeyActionCatalog.action(for: profile.topRightForceClickGestureAction ?? GlassToKeySettings.topRightForceClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomLeftForceClick: KeyActionCatalog.action(for: profile.bottomLeftForceClickGestureAction ?? GlassToKeySettings.bottomLeftForceClickGestureActionLabel) ?? KeyActionCatalog.noneAction,
            bottomRightForceClick: KeyActionCatalog.action(for: profile.bottomRightForceClickGestureAction ?? GlassToKeySettings.bottomRightForceClickGestureActionLabel) ?? KeyActionCatalog.noneAction
        ))
        engine.setPersistentLayer(profile.activeLayer ?? KeyLayerConfig.baseLayer)
        engine.setListening(true)
    }

    @discardableResult
    func ingest(_ frame: RuntimeRawFrame) -> RuntimeFrameDiagnostic? {
        scheduler.advance(to: frame.timestamp)
        return engine.processRuntimeRawFrame(frame)
    }

    func finish(at time: TimeInterval) {
        scheduler.advance(to: time)
        engine.resetState(stopVoiceDictation: true)
        engine.setListening(false)
    }
}

/// Public CLI boundary; transcripts contain actual recognition decisions and output commands.
@MainActor
public enum ProductionReplayHarness {
    public struct Result {
        public let transcript: String
        public let frameCount: Int
    }

    public static func run(captureURL: URL, profileURL: URL? = nil,
                           tailSeconds: Double = 0.25) throws -> Result {
        guard tailSeconds.isFinite, tailSeconds >= 0 else {
            throw ReplayFixtureError.invalidATPCapture(reason: "replay tail must be finite and nonnegative")
        }
        let fixture = try ReplayFixtureParser.load(from: captureURL)
        // v5 captures retain the app's configuration. Legacy fixtures need an explicit
        // profile or the deterministic factory profile (identified in the transcript).
        let container = try ATPCaptureCodec.loadContainer(from: captureURL)
        let replay = container.header.version == ATPCaptureV3Codec.currentVersion
            ? try ATPCaptureV3Codec.readReplayData(from: captureURL) : nil
        let profile: AppKeymapProfile
        let profileSource: String
        if let profileURL {
            let data = try Data(contentsOf: profileURL)
            if let portable = PortableKeymapInterop.decodeBundledDefaultProfile(from: data) {
                profile = portable
            } else {
                profile = try JSONDecoder().decode(AppKeymapProfile.self, from: data)
            }
            profileSource = "explicit"
        } else if let captured = replay?.configuration {
            profile = captured
            profileSource = "capture"
        } else {
            profile = AppKeymapProfile.defaultProfile()
            profileSource = "factory-default"
        }
        let indices = Array(Set(fixture.frames.map(\.deviceIndex))).sorted()
        func index(for id: String) -> Int? {
            fixture.frames.first { $0.deviceID == id }?.deviceIndex
        }
        let configuredLeft = index(for: profile.leftDeviceID)
        let configuredRight = index(for: profile.rightDeviceID)
        let left = configuredLeft ?? indices.first { $0 != configuredRight }
        let right = configuredRight ?? indices.first { $0 != left }
        let firstTime = replay?.records.first?.frame.timestamp ?? fixture.frames.first?.timestampSec ?? 0
        let session = ProductionReplaySession(startTime: firstTime)
        session.configure(profile: profile, leftIndex: left, rightIndex: right)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func line<T: Encodable>(_ value: T) throws -> String {
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        var lines = [try line(["type": "productionReplayMeta", "engine": "TouchProcessorEngine",
                               "schema": "g2k-production-replay-v1", "configuration": profileSource,
                               "leftDeviceIndex": left.map(String.init) ?? "none",
                               "rightDeviceIndex": right.map(String.init) ?? "none"])]
        var eventOffset = 0
        var voiceOffset = 0
        var lastTime = firstTime
        for (frameIndex, frame) in fixture.frames.enumerated() {
            let timestamp = replay?.records[frameIndex].frame.timestamp ?? frame.timestampSec
            guard timestamp.isFinite, timestamp >= lastTime else {
                throw ReplayFixtureError.invalidATPCapture(reason: "non-monotonic replay timestamps")
            }
            let touches = frame.contacts.map { contact in
                OMSRawTouch(id: Int32(contact.id), posX: Float(contact.x), posY: Float(contact.y),
                            total: Float(contact.total), pressure: Float(contact.pressure),
                            majorAxis: Float(contact.majorAxis), minorAxis: Float(contact.minorAxis),
                            angle: Float(contact.angle), density: Float(contact.density),
                            state: OMSState(rawValue: contact.state) ?? .notTouching,
                            telemetry: contact.telemetry.map { raw in
                                OMSTouchTelemetry(
                                    fingerID: raw.fingerID, handID: raw.handID,
                                    velocityX: raw.velocityX, velocityY: raw.velocityY,
                                    absoluteX: raw.absoluteX, absoluteY: raw.absoluteY,
                                    absoluteVelocityX: raw.absoluteVelocityX,
                                    absoluteVelocityY: raw.absoluteVelocityY,
                                    sourceFrame: raw.sourceFrame, sourceTimestamp: raw.sourceTimestamp
                                )
                            })
            }
            // v5 uses the app-decoded raw payload, including total capacitance and
            // telemetry. Only legacy fixture formats need contact reconstruction.
            let raw = replay?.records[frameIndex].frame ?? RuntimeRawFrame(
                sequence: UInt64(frame.seq), timestamp: timestamp,
                deviceNumericID: frame.deviceNumericID, deviceIndex: frame.deviceIndex,
                contacts: [], rawTouches: touches
            )
            let diagnostic = session.ingest(raw)
            lines.append(try line(FrameLine(type: "frame", sequence: raw.sequence,
                                            timestamp: raw.timestamp, diagnostic: diagnostic,
                                            events: Array(session.output.events.dropFirst(eventOffset)),
                                            voiceTransitions: Array(session.output.voiceTransitions.dropFirst(voiceOffset)))))
            eventOffset = session.output.events.count
            voiceOffset = session.output.voiceTransitions.count
            lastTime = timestamp
        }
        session.finish(at: lastTime + max(0, tailSeconds))
        lines.append(try line(FrameLine(type: "finish", sequence: nil,
                                        timestamp: session.scheduler.now, diagnostic: nil,
                                        events: Array(session.output.events.dropFirst(eventOffset)),
                                        voiceTransitions: Array(session.output.voiceTransitions.dropFirst(voiceOffset)))))
        return Result(transcript: lines.joined(separator: "\n") + "\n", frameCount: fixture.frames.count)
    }

    private struct FrameLine: Encodable {
        let type: String
        let sequence: UInt64?
        let timestamp: Double
        let diagnostic: RuntimeFrameDiagnostic?
        let events: [RuntimeDispatchEvent]
        let voiceTransitions: [Bool]
    }
}
#endif
