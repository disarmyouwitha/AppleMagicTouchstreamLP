• Yes, your idea is the right direction.

  Root cause in current code:

  - In official decode, contact IDs are overwritten with slot index (Id = i), not true finger identity: GlassToKey/
    TrackpadReportDecoder.cs:424.
  - Engine touch state is keyed by (side, contactId): GlassToKey/Core/Engine/TouchProcessorCore.cs:301.
  - If slot/index changes mid-gesture, engine thinks old touch was released and a new one appeared.
  - For MO(), that means the held momentary touch can be “released” unexpectedly, which drops layer state: GlassToKey/Core/
    Engine/TouchProcessorCore.cs:706 and GlassToKey/Core/Engine/TouchProcessorCore.cs:1422.
  - Then the second finger key (like 2) is resolved on the wrong layer or misses.

  So: gesture logic is mostly count/position, but key lifecycle (hold, release, MO, modifiers, repeat) depends on stable
  per-touch identity.

  You can absolutely replace raw contactId with an internal stable ID tracker:

  - Keep a fixed pool of 5 slots per side (no per-frame allocations).
  - Match new frame contacts to previous active slots by nearest position (with distance threshold).
  - Reuse matched slot’s stable ID; assign new stable ID only for unmatched contacts.
  - Use that stable ID for touchKey/state, keep raw ID only for diagnostics/UI.

  What would need changing:
  - Replace direct contact.Id usage for lifecycle keys with tracker-stable IDs.
  - Keep TouchView display optional (raw or stable), but don’t drive lifecycle off raw slot index.
  - Add a regression self-test: hold MO(1) + second finger where raw IDs swap between frames, verify 2 still dispatches.
---
 I guess my problem with this plan is all of the logic to rearrange the IDs into their fixed slot..
  allocation-free so if we need 10 slots per side so we don't have to do extra math that is fine. Do
  you see what I am getting at, or am I being a dumb human?


• You are not being dumb. You’re describing exactly the right model: not “finger ID,” but “contact
  session ID.”

  MO()/hold/release need continuity across frames. A plain incrementing ID without matching cannot
  work, because you still need to know whether a contact in frame N+1 is the same session as one in
  frame N.

  What works and stays allocation-free:

  1. Keep fixed arrays per side (10 slots is fine): active, stableSessionId, x, y, lastSeenFrame.
  2. For each frame contact (max 5), attach it to an existing active slot:

  - First try exact raw ID match (cheap, when driver IDs are stable).
  - Then fallback to nearest-position match within a threshold.

  3. If no match, open a new slot with stableSessionId = ++counter.
  4. Any active slot not seen this frame is released.
  5. Use stableSessionId for engine lifecycle keys (MakeTouchKey path), not raw contact.Id.

  Why this is still simple:

  - Bounded tiny math (<= 5 * 10 comparisons per side per frame).
  - No heap allocations.
  - No need to know which actual finger is which, only whether a contact session continues.

  So your instinct is correct: hide/ignore raw touch index for behavior, keep an internal session ID
  for lifecycle continuity. I can implement this in TrackpadReportDecoder/TouchProcessorCore path next
  if you want.
-------
• You are looking at the right angle. No break needed unless you want one.

  How IDs are produced today:

  1. Raw parse reads a 32-bit ContactId straight from packet bytes in GlassToKey/PtpReport.cs:108.
  2. Normal InputFrame creation carries that raw ID through in GlassToKey/Core/Input/InputFrame.cs:14.
  3. In the official decoder path, we then overwrite IDs ourselves to slot index (Id = i) in
     GlassToKey/TrackpadReportDecoder.cs:424.
  4. In legacy path, if IDs look suspicious/packed, we also overwrite to slot index in GlassToKey/
     TrackpadReportDecoder.cs:483.

  So yes, sometimes the driver gives IDs, and sometimes we replace them.

  About the original wildly shifting IDs:

  - Yes, that was largely because the official USB-C stream (usage 0/0) does not follow normal PTP
    field semantics, so “contact ID bytes” were not reliable finger IDs there.
  - That is documented in GlassToKey/REVERSE_OFFICIAL.md:17 and GlassToKey/REVERSE_OFFICIAL.md:29.

  So your intuition is correct: the current problem is not “finger identity,” it is session
  continuity. The slot-index workaround fixed giant/jumpy raw IDs, but slot reorder can still break
  hold state like MO().