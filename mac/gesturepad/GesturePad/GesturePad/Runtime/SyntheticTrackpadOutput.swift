import AppKit
import ApplicationServices
import Foundation
import OpenMultitouchSupport
import os

/// GesturePad's optional interpretation. The capture/coordinator does not post
/// events itself; another app can inject its own interpreter or consume frames directly.
@MainActor
final class SyntheticTrackpadOutput: TrackpadFrameOutput {
    private let pointer = InterpretedTrackpadPointer.shared
    private var clickTracker = DriverClickTracker()
    private var clickEnabled = false
    private var selectedDevices: Set<UInt64> = []
    var postedPointerEvents: UInt64 { pointer.postedEventCount }

    func configure(devices: Set<UInt64>, pointerEnabled: Bool, clickEnabled: Bool) -> Bool {
        self.clickEnabled = clickEnabled
        selectedDevices = devices
        if !clickEnabled { releaseButtons() }
        guard !(pointerEnabled || clickEnabled) || AXIsProcessTrusted() else {
            pointer.stop(); releaseButtons()
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }
        if pointerEnabled { pointer.enable(devices: devices) }
        else { pointer.stop() }
        return true
    }
    func process(_ frame: TrackpadContactFrame) {
        guard selectedDevices.contains(frame.deviceID) else { return }
        if clickEnabled && AXIsProcessTrusted() {
            postClicks(clickTracker.update(device: frame.deviceID, buttons: frame.buttons))
        }
        pointer.process(device: frame.deviceID, time: frame.sourceTimestamp,
            contacts: frame.contacts, suppress: frame.buttons != 0)
    }
    func reset(device: UInt64) {
        postClicks(clickTracker.reset(device: device))
        pointer.resetBaseline(device: device)
    }
    func releaseButtons() { postClicks(clickTracker.reset()) }
    func stop() { pointer.stop(); releaseButtons(); selectedDevices = []; clickEnabled = false }

    private func postClicks(_ changes: [DriverButtonChange]) {
        guard !changes.isEmpty, let location = CGEvent(source: nil)?.location else { return }
        for change in changes {
            let right = change.mask == 2
            let type: CGEventType = right ? (change.down ? .rightMouseDown : .rightMouseUp)
                : (change.down ? .leftMouseDown : .leftMouseUp)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: location, mouseButton: right ? .right : .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: TakeoverConfiguration.pointerEventTag)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
    }

}

/// Merge physical button state across selected pads. A new/reset source must
/// report buttons-up before it can press, so enabling mid-click cannot click.
struct DriverButtonChange: Equatable {
    let mask: UInt8
    let down: Bool
}
struct DriverClickTracker {
    private var buttons: [UInt64: UInt8] = [:]
    private var armed: Set<UInt64> = []
    private var combined: UInt8 { buttons.values.reduce(0, |) }
    private func changes(from old: UInt8) -> [DriverButtonChange] {
        let next = combined
        guard old != next else { return [] }
        return [UInt8(1), 2].compactMap { mask in
            guard old & mask != next & mask else { return nil }
            return DriverButtonChange(mask: mask, down: next & mask != 0)
        }
    }
    mutating func update(device: UInt64, buttons value: UInt8) -> [DriverButtonChange] {
        let value = value & 3
        if value == 0 { armed.insert(device) }
        guard armed.contains(device) else { return [] }
        let old = combined
        buttons[device] = value
        return changes(from: old)
    }
    mutating func reset(device: UInt64) -> [DriverButtonChange] {
        let old = combined
        buttons[device] = nil; armed.remove(device)
        return changes(from: old)
    }
    mutating func reset() -> [DriverButtonChange] {
        let old = combined
        buttons.removeAll(keepingCapacity: true); armed.removeAll(keepingCapacity: true)
        return changes(from: old)
    }
}

/// Experimental two-contact relative pointer; per-device baselines never cross pads.
struct TwoFingerPointerTracker {
    struct Baseline { let first: Int32; let second: Int32; let point: CGPoint; let time: Double }
    private var baselines: [UInt64: Baseline] = [:]
    mutating func reset() { baselines.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { baselines[device] = nil }
    mutating func process(device: UInt64, time: Double, touches: OMSRawTouchBufferView) -> CGPoint? {
        process(device: device, time: time, contacts: touches)
    }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C) -> CGPoint? where C.Element == OMSRawTouch {
        var first: OMSRawTouch?, second: OMSRawTouch?
        var count = 0
        for touch in contacts where touch.state == .starting || touch.state == .making || touch.state == .touching {
            count += 1
            if count > 2 || touch.telemetry?.fingerID == 6 {
                baselines.removeValue(forKey: device); return nil
            }
            if first == nil { first = touch } else { second = touch }
        }
        guard count == 2, let a = first, let b = second,
              a.id != b.id, time.isFinite,
              a.posX.isFinite, a.posY.isFinite, b.posX.isFinite, b.posY.isFinite else {
            baselines.removeValue(forKey: device); return nil
        }
        let point = CGPoint(x: Double(a.posX + b.posX) / 2, y: Double(a.posY + b.posY) / 2)
        let next = Baseline(first: min(a.id, b.id), second: max(a.id, b.id), point: point, time: time)
        let old = baselines.updateValue(next, forKey: device)
        guard let old, old.first == next.first, old.second == next.second,
              time > old.time, time - old.time < 0.15 else { return nil }
        // Provisional constant gain: 6 screen points per mm on a 160 x 114.9 mm pad.
        let delta = CGPoint(x: (point.x - old.point.x) * 160 * 6,
                            y: -(point.y - old.point.y) * 114.9 * 6)
        guard abs(delta.x) < 150, abs(delta.y) < 150 else { return nil }
        return delta
    }
}

final class InterpretedTrackpadPointer: @unchecked Sendable {
    static let shared = InterpretedTrackpadPointer()
    private struct State {
        var devices: Set<UInt64> = []
        var tracker = TwoFingerPointerTracker()
        var displayBounds: [CGRect] = []
        var postedEvents: UInt64 = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    func enable(devices: Set<UInt64>) {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let bounds: [CGRect]
        if CGGetActiveDisplayList(16, &displays, &count) == .success {
            bounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        } else { bounds = [] }
        lock.withLock { state in
            for device in state.devices.symmetricDifference(devices) { state.tracker.reset(device: device) }
            state.devices = devices; state.displayBounds = bounds
        }
    }
    var postedEventCount: UInt64 { lock.withLock { $0.postedEvents } }
    func stop() { lock.withLock { $0.devices.removeAll(keepingCapacity: true); $0.tracker.reset() } }
    func resetBaseline() { lock.withLock { $0.tracker.reset() } }
    func resetBaseline(device: UInt64) { lock.withLock { $0.tracker.reset(device: device) } }
    func process(_ frame: OMSRawTouchFrame) {
        process(device: frame.deviceIDNumeric, time: frame.timestamp, contacts: frame.touches)
    }
    func process<C: Collection & Sendable>(device: UInt64, time: Double, contacts: C, suppress: Bool = false) where C.Element == OMSRawTouch {
        lock.withLock { state in
            guard state.devices.contains(device) else { return }
            // Native click-and-drag remains in charge while a mouse button is held.
            if suppress || CGEventSource.buttonState(.combinedSessionState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .right)
                || CGEventSource.buttonState(.combinedSessionState, button: .center) {
                state.tracker.reset()
                return
            }
            guard
                  let delta = state.tracker.process(device: device,
                    time: time, contacts: contacts),
                  delta.x != 0 || delta.y != 0,
                  let current = CGEvent(source: nil)?.location else { return }
            var location = CGPoint(x: current.x + delta.x, y: current.y + delta.y)
            // Clamp to the nearest actual display, including negative-origin displays.
            var closest: CGPoint?; var distance = Double.infinity
            for bounds in state.displayBounds {
                let candidate = CGPoint(x: min(max(location.x, bounds.minX), bounds.maxX - 1),
                                        y: min(max(location.y, bounds.minY), bounds.maxY - 1))
                let dx = candidate.x - location.x, dy = candidate.y - location.y
                let d = dx * dx + dy * dy
                if d < distance { distance = d; closest = candidate }
            }
            if let closest { location = closest }
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                       mouseCursorPosition: location, mouseButton: .left) else { return }
            event.setIntegerValueField(.eventSourceUserData, value: TakeoverConfiguration.pointerEventTag)
            event.setDoubleValueField(.mouseEventDeltaX, value: delta.x)
            event.setDoubleValueField(.mouseEventDeltaY, value: delta.y)
            event.post(tap: .cghidEventTap)
            state.postedEvents &+= 1
        }
    }
}

