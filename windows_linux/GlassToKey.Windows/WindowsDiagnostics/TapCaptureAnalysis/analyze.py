"""Offline only. Combine production decoder CSV with original arrival timestamps.

Run from the repository root after --raw-analyze creates contacts.csv here.
No input is opened or injected; coordinates use the Windows runtime defaults.
"""
from pathlib import Path
import csv
import struct
import json
import math
import hashlib

root = Path(__file__).resolve().parent
source = root.parents[2] / "capture-20261023-142718_taps.atpcap"
data = source.read_bytes()
version, frequency = struct.unpack_from("<iq", data, 8)
position = 20
records = []
while position < len(data):
    length, ticks, index, device_hash, vid, pid, usage_page, usage, side, profile = struct.unpack_from("<iqiIIIHHBB", data, position)
    position += 34
    payload = data[position:position + length]
    position += length
    records.append(dict(ticks=ticks, side=side, device=f"{index}:{device_hash:08X}"))

rows = {}
for row in csv.DictReader((root / "contacts.csv").open(encoding="utf-8-sig")):
    if int(row["assigned_flags"], 16) & 2:
        rows.setdefault(int(row["frame_index"]), []).append(dict(
            id=int(row["assigned_contact_id"], 16),
            x=int(row["decoded_x"]) * 160 / 7612,
            y=int(row["decoded_y"]) * 114.9 / 5065))
base = records[0]["ticks"]
frames = [dict(index=i, t=(r["ticks"]-base)/frequency, contacts=rows.get(i, []), side=r["side"])
          for i, r in enumerate(records)]
cycles, current = [], []
for frame in frames:
    if frame["contacts"]:
        current.append(frame)
    elif current:
        cycles.append(current + [frame])
        current = []
if current:
    cycles.append(current)

summary = []
for n, cycle in enumerate(cycles):
    originals, previous = {}, None
    travel, pending, activation = [0, 0], 0, None
    stable_travel, stable_activation, stable_max = [0, 0], None, 0
    max_finger = max_pair = max_step = peak = 0
    pair_time = first_lift = None
    for frame in cycle:
        contacts = frame["contacts"]
        peak = max(peak, len(contacts))
        if len(contacts) == 2 and pair_time is None:
            pair_time = frame["t"]
        if pair_time is not None and len(contacts) < 2 and first_lift is None:
            first_lift = frame["t"]
        for contact in contacts:
            origin = originals.setdefault(contact["id"], contact)
            max_finger = max(max_finger, math.hypot(contact["x"]-origin["x"], contact["y"]-origin["y"]))
        if previous and contacts:
            old = {p["id"]: p for p in previous["contacts"]}
            shared = [(p, old[p["id"]]) for p in contacts if p["id"] in old]
            if shared:
                dx = sum(p["x"]-o["x"] for p, o in shared)/len(shared)
                dy = sum(p["y"]-o["y"] for p, o in shared)/len(shared)
                membership_changed = len(contacts) != len(previous["contacts"]) or len(shared) != len(contacts)
                if membership_changed:
                    stable_travel = [0, 0]
                else:
                    stable_travel[0] += dx
                    stable_travel[1] += dy
                    if len(contacts) == 2:
                        stable_max = max(stable_max, math.hypot(*stable_travel))
                        if stable_activation is None and stable_max >= .35:
                            stable_activation = frame["index"]
                max_step = max(max_step, math.hypot(dx, dy))
                if pending != len(contacts):
                    pending, travel = len(contacts), [0, 0]
                travel[0] += dx
                travel[1] += dy
                if len(contacts) == 2:
                    max_pair = max(max_pair, math.hypot(*travel))
                if activation is None and len(contacts) == 2 and math.hypot(*travel) >= .35:
                    activation = frame
        previous = frame
    summary.append(dict(cycle=n, startFrame=cycle[0]["index"], endFrame=cycle[-1]["index"],
        start=round(cycle[0]["t"], 4), durationMs=round((cycle[-1]["t"]-cycle[0]["t"])*1000, 1),
        frames=len(cycle), peak=peak, maxFingerMm=round(max_finger, 4), maxPendingMm=round(max_pair, 4),
        maxStepMm=round(max_step, 4), activationFrame=activation["index"] if activation else None,
        stableMembershipActivationFrame=stable_activation, stableMembershipMaxMm=round(stable_max, 4),
        activationMs=round((activation["t"]-cycle[0]["t"])*1000, 1) if activation else None,
        landingMs=round((pair_time-cycle[0]["t"])*1000, 1) if pair_time is not None else None,
        liftMs=round((cycle[-1]["t"]-first_lift)*1000, 1) if first_lift is not None else None))

sha = hashlib.sha256(data).hexdigest()
(root / "frames.json").write_text(json.dumps(dict(sourceSha256=sha, frequency=frequency, frames=frames), indent=2), encoding="utf8")
(root / "cycles.json").write_text(json.dumps(summary, indent=2), encoding="utf8")
print("version", version, "records", len(records), "seconds", round(frames[-1]["t"], 3), "cycles", len(cycles), "sha256", sha)
for row in summary:
    print(json.dumps(row))
