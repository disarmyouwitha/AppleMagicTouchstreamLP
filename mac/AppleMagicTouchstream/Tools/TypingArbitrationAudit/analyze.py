#!/usr/bin/env python3
"""Read-only audit of recorded v5 typing/gesture arbitration, without native input.

Counts observed contact lifetimes, not intended keystrokes. Diagnostic reasons are
recorded live decisions; this does not rerun recognition or infer intended text.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import struct


def analyze(path):
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("Truncated capture header")
    magic, version, frequency = struct.unpack_from("<8siq", data)
    if magic != b"ATPCAP01" or version != 5 or frequency <= 0:
        raise ValueError("Expected an ATPCAP01 v5 capture with a positive clock frequency")
    offset = 20
    frames, events = [], []
    profile = {}
    while offset < len(data):
        if offset + 34 > len(data):
            raise ValueError("Truncated record header")
        length, ticks, device = struct.unpack_from("<iqi", data, offset)
        offset += 34
        if length < 0 or offset + length > len(data):
            raise ValueError("Invalid record payload length")
        payload = data[offset:offset + length]
        offset += length
        if device not in (-2, -4, -5):
            continue
        record = json.loads(payload)
        if device == -2:
            profile = record["profile"]
        elif device == -4:
            events.append(record["dispatch"])
        else:
            frames.append(record["record"])
            events.extend(record["record"].get("dispatchEvents", []))

    active, generations, lifetimes = {}, collections.Counter(), []
    reasons, counts, devices = collections.Counter(), collections.Counter(), collections.Counter()
    cycle_by_pad, cycles = {}, []
    queue_max = dict.fromkeys(("liveDroppedFrames", "dispatchDropped", "liveQueueDepth", "dispatchQueueDepth"), 0)
    timeline = []
    for record in frames:
        frame = record["frame"]
        device = frame["deviceNumericID"]
        now = record["arrivalTicks"] / frequency
        touches = frame["rawTouches"]
        diagnostic = record.get("diagnostic") or {}
        devices[device] += 1
        present = {t["id"] for t in touches if t["state"] in ("starting", "making", "touching", "lingering")}
        for touch in touches:
            key = (device, touch["id"])
            if touch["id"] in present and key not in active:
                generations[key] += 1
                life = dict(device=device, id=touch["id"], generation=generations[key],
                            start_ms=round(now * 1000, 3), end_ms=round(now * 1000, 3), reasons=set(), labels=set())
                active[key] = life
                lifetimes.append(life)
            if key in active:
                active[key]["end_ms"] = round(now * 1000, 3)
        for touch in diagnostic.get("touches", []):
            reason = touch.get("reason", "none")
            reasons[reason] += 1
            life = active.get((device, touch["id"]))
            if life is not None:
                life["reasons"].add(reason)
                if touch.get("target"):
                    life["labels"].add(touch["target"]["label"])
        for key in list(active):
            if key[0] == device and key[1] not in present:
                del active[key]
        count = sum(t["state"] in ("making", "touching") for t in touches)
        counts[count] += 1
        reserved = any(t.get("reason") == "gestureReserved" for t in diagnostic.get("touches", []))
        if count and device not in cycle_by_pad:
            cycle = dict(device=device, start_ms=round(now * 1000, 3), end_ms=round(now * 1000, 3), max_contacts=count, reserved=False)
            cycle_by_pad[device] = cycle
            cycles.append(cycle)
        if device in cycle_by_pad:
            cycle = cycle_by_pad[device]
            cycle["end_ms"] = round(now * 1000, 3)
            cycle["max_contacts"] = max(cycle["max_contacts"], count)
            cycle["reserved"] |= reserved
            if not count:
                del cycle_by_pad[device]
        for key in queue_max:
            queue_max[key] = max(queue_max[key], (record.get("ingress") or {}).get(key, 0))
        timeline.append(dict(time_ms=round(now * 1000, 3), device=device, sequence=frame["sequence"],
                             contacts=[dict(id=t["id"], state=t["state"]) for t in touches],
                             decisions=[{key: t[key] for key in ("id", "reason", "decision") if key in t}
                                        for t in diagnostic.get("touches", [])]))
    for life in lifetimes:
        life["reasons"] = sorted(life["reasons"])
        life["labels"] = sorted(life["labels"])
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(), version=version,
                frames=len(frames), last_arrival_ms=round(frames[-1]["arrivalTicks"] / frequency * 1000, 3) if frames else 0,
                frames_by_device=dict(devices), active_count_histogram=dict(counts),
                diagnostic_samples_by_reason=dict(reasons), queue_maxima=queue_max,
                dispatch_statuses=dict(collections.Counter(e["event"]["status"] for e in events)),
                dispatch_kinds=dict(collections.Counter(e["event"]["kind"]["type"] for e in events)),
                observed_contact_lifetimes=len(lifetimes),
                reserved_contact_lifetimes=sum("gestureReserved" in l["reasons"] for l in lifetimes),
                reserved_count_cycles=sum(c["reserved"] for c in cycles), count_cycles=cycles,
                legacy_typing_grace_ms=profile.get("typingGraceMs"),
                capture_has_hand_gesture_settings=profile.get("handGestureSettings") is not None,
                lifetimes=lifetimes, timeline=timeline,
                limits="Observed lifetimes may be capture-censored. Reasons count samples, not intended keys. Direct pointer output is not established by absence of dispatch records. No replay or physical intent inferred.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = analyze(args.capture)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("lifetimes", "timeline", "count_cycles")}, indent=2))
