• Up-To-Speed Summary

  - REVERSE_OFFICIAL.md aligns with the current official decode path: slot model (1 + i*9), XY from
    +2/+3 and +4/+5, forced tip/confidence flags, and axis-specific scaling (14720/10240) are all
    implemented in GlassToKey/TrackpadReportDecoder.cs:25, GlassToKey/TrackpadReportDecoder.cs:413,
    GlassToKey/TrackpadReportDecoder.cs:424, GlassToKey/TrackpadReportDecoder.cs:438.
  - Raw parser is still standard 50-byte PTP (reportId + 5 contacts + tail) with LE ContactId/X/Y at
    parse time in GlassToKey/PtpReport.cs:23, GlassToKey/PtpReport.cs:108.
  - Official profile always rewrites contact IDs to slot index (Id=i), while legacy only rewrites when
    IDs look packed/suspicious in GlassToKey/TrackpadReportDecoder.cs:424, GlassToKey/
    TrackpadReportDecoder.cs:445.
  - Engine lifecycle uses (side, contactId) touch keys, so ID/slot churn can drop MO holds exactly as
    described in your bug notes (GlassToKey/Core/Engine/TouchProcessorCore.cs:301, GlassToKey/Core/
    Engine/TouchProcessorCore.cs:706, GlassToKey/Core/Engine/TouchProcessorCore.cs:2353).
  - The proposed “stable session ID tracker” in GlassToKey/BUG_contact_fix.md:19 is not implemented
    yet.
  - Runtime guardrails from the reverse doc are present: contextual fault logging + temporary raw-
    input pause after repeated faults in GlassToKey/Core/Diagnostics/RuntimeFaultLogger.cs:49,
    GlassToKey/TouchRuntimeService.cs:419.
  - --decoder-debug is wired and logs chosen profile + first contact fields in GlassToKey/
    ReaderOptions.cs:90, GlassToKey/TouchRuntimeService.cs:412.
  - Raw analyzer is still signature/summary oriented (counts, offsets, hot bytes, samples), with no
    built-in per-frame XY dump in GlassToKey/Core/Diagnostics/RawCaptureAnalyzer.cs:10.
  - Capture/replay metadata includes side hint + decoder profile in GlassToKey/Core/Diagnostics/
    InputCaptureFile.cs:122, and replay reuses that preferred profile in GlassToKey/Core/Diagnostics/
    ReplayRunner.cs:89.

  Notable Drift / Health

  - Docs say key/mouse candidate buffer is fixed at 40ms (GlassToKey/README.md:45), but runtime config
    currently hardcodes 20ms (GlassToKey/RuntimeConfigurationFactory.cs:13).
  - Self-test baseline is currently failing locally: Engine intent tests failed: expected
    mouseCandidate->mouseActive transitions were missing (dotnet run --project
    GlassToKey\GlassToKey.csproj -c Release -- --selftest).

  If you want, I can next do one of these:

  1. Implement the allocation-free stable session ID tracker for lifecycle continuity.
  2. Add per-frame CSV/JSON XY+slot-byte diagnostics to RawCaptureAnalyzer.
  3. Triage and fix the current self-test failure first.

-------

 Implemented exactly the diagnostics path (no stable-session ID tracker/lifecycle logic changes).

  What I changed

  - Added --raw-analyze-contacts-out <path> option parsing in GlassToKey/ReaderOptions.cs:18 and
    GlassToKey/ReaderOptions.cs:91.
  - Wired raw-analyze flow to pass that path in GlassToKey/App.xaml.cs:90.
  - Extended analyzer to emit per-contact CSV rows with raw vs assigned IDs (plus flags/XY and slot
    bytes) in GlassToKey/Core/Diagnostics/RawCaptureAnalyzer.cs:92, GlassToKey/Core/Diagnostics/
    RawCaptureAnalyzer.cs:174, GlassToKey/Core/Diagnostics/RawCaptureAnalyzer.cs:180.
  - Added a debug formatter for live rawId -> assignedId mapping in GlassToKey/
    TrackpadDecoderDebugFormatter.cs:9.
  - Hooked that mapping into decoder debug logs in GlassToKey/TouchRuntimeService.cs:305, GlassToKey/
    TouchRuntimeService.cs:419, GlassToKey/MainWindow.xaml.cs:3493, GlassToKey/
    MainWindow.xaml.cs:3586.
  - Documented new flag in GlassToKey/README.md:86.
  - Updated reverse notes context in GlassToKey/REVERSE_OFFICIAL.md:72.

  How to use

  - Offline capture analysis:
    dotnet run --project GlassToKey\GlassToKey.csproj -c Release -- --raw-analyze <capture.atpcap>
    --raw-analyze-contacts-out <contacts.csv>
  - Live decoder logging:
    dotnet run --project GlassToKey\GlassToKey.csproj -c Release -- --decoder-debug

  CSV includes:
  raw_contact_id, assigned_contact_id, raw_flags, assigned_flags, raw_x, raw_y, decoded_x, decoded_y,
  slot_offset, slot_hex.

  Verification

  - dotnet build GlassToKey\GlassToKey.csproj -c Release passed.
  - Ran on GlassToKey\fixtures\replay\smoke.atpcap; output row showed raw/assigned mapping, e.g.
    raw_contact_id=0x0000004D and assigned_contact_id=0x00000000 (official profile normalization).