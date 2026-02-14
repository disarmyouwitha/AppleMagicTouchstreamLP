## Current work:
• Yes, there are still unmapped/partially mapped parts of the 50-byte report.

  What we map confidently now:

  - byte 0: report ID (0x05)
  - per slot (1 + 9*i):
  - +0: stable contact token candidate (now used as Id)
  - +2,+3: raw X
  - +4,+5: raw Y
  - byte 48: contact count
  - report shape/length and slot boundaries are solid

  What is still not fully mapped:

  - per slot +1, +6, +7: unknown semantics (likely non-position metadata)
  - per slot +8: behaves like state/quality (3 vs 1), but exact meaning not proven
  - exact true tip/confidence bit source (we currently force flags for official path)
  - exact meaning of bytes 46-47 (ScanTime) in official stream
  - practical meaning of byte 49 (IsButtonClicked) under this transport

  Estimate:

  - If the question is “can we decode/use it reliably for runtime behavior?”: about 90%.
  - If the question is “have we semantically named every bit in all 50 bytes?”: about 65-70%.

  ---

   Agree, IsButtonClicked is a good next target and probably the easiest high-confidence win.

  What we are forcing for tip/confidence:

  - In official decode, we currently do:
  - normalizedFlags = (contact.Flags & 0xFC) | 0x03 in GlassToKey/TrackpadReportDecoder.cs.
  - Bit meaning comes from PtpContact/ContactFrame:
  - bit 0 = Confidence
  - bit 1 = TipSwitch
  - bits 2..7 are preserved (we don’t overwrite those).
  - So we force TipSwitch=true and Confidence=true for every decoded contact in official usage 0/0.

  Why we do that:

  - Engine and visualizer both ignore non-tip contacts (!TipSwitch) in hot paths (GlassToKey/Core/Engine/TouchProcessorCore.cs,
    GlassToKey/TouchState.cs).
  - On this stream, raw flag semantics are not trustworthy yet, so forcing avoids contact drop/flicker from bad raw bits.

  Cost of forcing:

  - We lose true semantic info for actual tip/confidence in official mode.
  - Any future feature that depends on true confidence/tip quality is currently blocked until we map raw bits.

  Next logical steps (in order):

  1. Map IsButtonClicked (byte 49) with controlled click-only captures.
  2. Add analyzer output for raw slot bytes +1,+6,+7,+8 transition stats vs contact lifecycle events.
  3. Recover true tip/confidence semantics, then remove forced | 0x03 when confidence is high.

  If you want, I can implement step 1 next with a very small capture protocol and analysis output so we can confirm IsButtonClicked
  quickly.