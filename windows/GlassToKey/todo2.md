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