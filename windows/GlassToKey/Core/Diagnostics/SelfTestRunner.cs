using System;
using System.IO;
using System.Text.Json;

namespace GlassToKey;

internal static class SelfTestRunner
{
    public static SelfTestResult Run()
    {
        if (!RunParserTests(out string parserFailure))
        {
            return new SelfTestResult(false, $"Parser tests failed: {parserFailure}");
        }

        if (!RunButtonEdgeTrackerTests(out string buttonFailure))
        {
            return new SelfTestResult(false, $"Button edge helper tests failed: {buttonFailure}");
        }

        if (!RunReplayTests(out string replayFailure))
        {
            return new SelfTestResult(false, $"Replay tests failed: {replayFailure}");
        }

        if (!RunEngineIntentTests(out string intentFailure))
        {
            return new SelfTestResult(false, $"Engine intent tests failed: {intentFailure}");
        }

        if (!RunEngineDispatchTests(out string dispatchFailure))
        {
            return new SelfTestResult(false, $"Engine dispatch tests failed: {dispatchFailure}");
        }

        if (!RunTypingToggleDispatchResumeTests(out string typingToggleFailure))
        {
            return new SelfTestResult(false, $"Typing toggle tests failed: {typingToggleFailure}");
        }

        if (!RunCrossSideFiveFingerToggleTests(out string crossSideFailure))
        {
            return new SelfTestResult(false, $"Cross-side five-finger tests failed: {crossSideFailure}");
        }

        if (!RunRightSideFiveFingerToggleResumeTests(out string rightSideFailure))
        {
            return new SelfTestResult(false, $"Right-side five-finger tests failed: {rightSideFailure}");
        }

        if (!RunChordShiftTapReleaseTests(out string chordTapFailure))
        {
            return new SelfTestResult(false, $"Chord-shift tap tests failed: {chordTapFailure}");
        }

        if (!RunTapGestureTests(out string tapFailure))
        {
            return new SelfTestResult(false, $"Tap gesture tests failed: {tapFailure}");
        }

        if (!RunThreePlusGesturePriorityTests(out string threePlusFailure))
        {
            return new SelfTestResult(false, $"Three-plus gesture priority tests failed: {threePlusFailure}");
        }

        if (!RunCornerHoldGestureTests(out string cornerFailure))
        {
            return new SelfTestResult(false, $"Corner hold tests failed: {cornerFailure}");
        }

        if (!RunFiveFingerSwipeTests(out string fiveFingerFailure))
        {
            return new SelfTestResult(false, $"Five-finger swipe tests failed: {fiveFingerFailure}");
        }

        return new SelfTestResult(true, "All self-tests passed.");
    }

    private static bool RunParserTests(out string failure)
    {
        Span<byte> reportBytes = stackalloc byte[PtpReport.ExpectedSize];
        reportBytes[0] = RawInputInterop.ReportIdMultitouch;
        WriteContact(reportBytes, 0, flags: 0x03, contactId: 101, x: 1234, y: 2345);
        WriteContact(reportBytes, 1, flags: 0x01, contactId: 102, x: 2234, y: 3345);
        reportBytes[46] = 0x44;
        reportBytes[47] = 0x01;
        reportBytes[48] = 2;
        reportBytes[49] = 1;

        if (!PtpReport.TryParse(reportBytes, out PtpReport parsed))
        {
            failure = "valid report did not parse";
            return false;
        }

        if (parsed.ReportId != RawInputInterop.ReportIdMultitouch ||
            parsed.GetClampedContactCount() != 2 ||
            parsed.GetContact(0).ContactId != 101 ||
            parsed.GetContact(0).X != 1234 ||
            parsed.GetContact(1).TipSwitch ||
            parsed.ScanTime != 0x0144 ||
            parsed.IsButtonClicked != 1)
        {
            failure = "decoded fields mismatched expected values";
            return false;
        }

        RawInputDeviceInfo deviceInfo = new(
            VendorId: RawInputInterop.VendorId,
            ProductId: RawInputInterop.ProductIdMt2,
            UsagePage: RawInputInterop.UsagePageDigitizer,
            Usage: RawInputInterop.UsageTouchpad);
        if (!TrackpadReportDecoder.TryDecode(reportBytes, deviceInfo, arrivalQpcTicks: 100, out TrackpadDecodeResult nativeDecoded) ||
            nativeDecoded.Kind != TrackpadReportKind.PtpNative ||
            nativeDecoded.Frame.GetClampedContactCount() != 2)
        {
            failure = "native PTP decode failed";
            return false;
        }

        Span<byte> embedded = stackalloc byte[64];
        embedded[0] = 0x31;
        reportBytes.CopyTo(embedded.Slice(8));
        if (!TrackpadReportDecoder.TryDecode(embedded, deviceInfo, arrivalQpcTicks: 200, out TrackpadDecodeResult embeddedDecoded) ||
            embeddedDecoded.Kind != TrackpadReportKind.PtpEmbedded ||
            embeddedDecoded.PayloadOffset != 8 ||
            embeddedDecoded.Frame.GetClampedContactCount() != 2)
        {
            failure = "embedded PTP decode failed";
            return false;
        }

        Span<byte> officialLike = stackalloc byte[PtpReport.ExpectedSize];
        officialLike[0] = RawInputInterop.ReportIdMultitouch;
        WriteContact(officialLike, 0, flags: 0x04, contactId: 0x12345600, x: 2500, y: 1900);
        officialLike[48] = 1;
        RawInputDeviceInfo officialInfo = new(
            VendorId: 0x05AC,
            ProductId: RawInputInterop.ProductIdMt2,
            UsagePage: 0,
            Usage: 0);
        if (!TrackpadReportDecoder.TryDecode(officialLike, officialInfo, arrivalQpcTicks: 300, TrackpadDecoderProfile.Official, out TrackpadDecodeResult officialDecoded) ||
            officialDecoded.Profile != TrackpadDecoderProfile.Official ||
            officialDecoded.Frame.GetClampedContactCount() != 1 ||
            !officialDecoded.Frame.GetContact(0).TipSwitch ||
            officialDecoded.Frame.GetContact(0).Id != 4)
        {
            failure = "official profile decode failed";
            return false;
        }

        Span<byte> appleVidLegacyLikeUsageZero = stackalloc byte[PtpReport.ExpectedSize];
        appleVidLegacyLikeUsageZero[0] = RawInputInterop.ReportIdMultitouch;
        WriteContact(appleVidLegacyLikeUsageZero, 0, flags: 0x03, contactId: 101, x: 1600, y: 1200);
        appleVidLegacyLikeUsageZero[48] = 1;
        RawInputDeviceInfo appleVidUsageZeroInfo = new(
            VendorId: 0x05AC,
            ProductId: RawInputInterop.ProductIdMt2,
            UsagePage: 0,
            Usage: 0);
        if (!TrackpadReportDecoder.TryDecode(appleVidLegacyLikeUsageZero, appleVidUsageZeroInfo, arrivalQpcTicks: 320, TrackpadDecoderProfile.Legacy, out TrackpadDecodeResult appleVidLegacyDecoded) ||
            appleVidLegacyDecoded.Profile != TrackpadDecoderProfile.Legacy ||
            appleVidLegacyDecoded.Frame.GetClampedContactCount() != 1 ||
            appleVidLegacyDecoded.Frame.GetContact(0).Id != 101)
        {
            failure = "apple VID usage 0/0 PTP should stay on legacy profile";
            return false;
        }

        Span<byte> opensourceVidLegacyLikeUsageZero = stackalloc byte[PtpReport.ExpectedSize];
        opensourceVidLegacyLikeUsageZero[0] = RawInputInterop.ReportIdMultitouch;
        WriteContact(opensourceVidLegacyLikeUsageZero, 0, flags: 0x03, contactId: 0, x: 1600, y: 1200);
        opensourceVidLegacyLikeUsageZero[48] = 1;
        RawInputDeviceInfo opensourceVidUsageZeroInfo = new(
            VendorId: 0x004C,
            ProductId: RawInputInterop.ProductIdMt2,
            UsagePage: 0,
            Usage: 0);
        if (!TrackpadReportDecoder.TryDecode(opensourceVidLegacyLikeUsageZero, opensourceVidUsageZeroInfo, arrivalQpcTicks: 340, TrackpadDecoderProfile.Legacy, out TrackpadDecodeResult opensourceVidLegacyDecoded) ||
            opensourceVidLegacyDecoded.Profile != TrackpadDecoderProfile.Legacy ||
            opensourceVidLegacyDecoded.Frame.GetClampedContactCount() != 1)
        {
            failure = "opensource VID usage 0/0 PTP should stay on legacy profile";
            return false;
        }

        Span<byte> opensourceNoTipLegacyFrame = stackalloc byte[PtpReport.ExpectedSize];
        opensourceNoTipLegacyFrame[0] = RawInputInterop.ReportIdMultitouch;
        WriteContact(opensourceNoTipLegacyFrame, 0, flags: 0x01, contactId: 12, x: 2200, y: 1700);
        opensourceNoTipLegacyFrame[48] = 1;
        if (!TrackpadReportDecoder.TryDecode(opensourceNoTipLegacyFrame, opensourceVidUsageZeroInfo, arrivalQpcTicks: 360, TrackpadDecoderProfile.Legacy, out TrackpadDecodeResult opensourceNoTipDecoded) ||
            opensourceNoTipDecoded.Profile != TrackpadDecoderProfile.Legacy ||
            opensourceNoTipDecoded.Frame.GetClampedContactCount() != 1)
        {
            failure = "opensource legacy frame with confidence-only flags should still decode";
            return false;
        }

        Span<byte> malformed = stackalloc byte[PtpReport.ExpectedSize - 1];
        if (PtpReport.TryParse(malformed, out _))
        {
            failure = "short report should fail parsing";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunButtonEdgeTrackerTests(out string failure)
    {
        ButtonEdgeTracker tracker = default;
        ButtonEdgeState state = tracker.Current;
        if (state.HasHistory || state.IsPressed || state.Changed)
        {
            failure = "default tracker current state should be unknown";
            return false;
        }

        state = tracker.Update(0);
        if (state.HasHistory || state.IsPressed || state.Changed)
        {
            failure = "first up sample should have no history and no edges";
            return false;
        }

        state = tracker.Update(1);
        if (!state.HasHistory || !state.IsPressed || !state.JustPressed || state.JustReleased)
        {
            failure = "up-to-down transition should be reported as just-pressed";
            return false;
        }

        state = tracker.Update(1);
        if (!state.HasHistory || !state.IsPressed || state.Changed)
        {
            failure = "steady pressed sample should have no edge";
            return false;
        }

        InputFrame released = MakeFrame(contactCount: 0);
        released.IsButtonClicked = 0;
        state = tracker.Update(in released);
        if (!state.HasHistory || state.IsPressed || state.JustPressed || !state.JustReleased)
        {
            failure = "down-to-up transition should be reported as just-released";
            return false;
        }

        tracker.Reset();
        state = tracker.Current;
        if (state.HasHistory || state.IsPressed || state.Changed)
        {
            failure = "reset tracker should clear history";
            return false;
        }

        InputFrame pressed = MakeFrame(contactCount: 0);
        pressed.IsButtonClicked = 1;
        state = tracker.Update(in pressed);
        if (state.HasHistory || !state.IsPressed || state.Changed)
        {
            failure = "first pressed sample after reset should not report an edge";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunCrossSideFiveFingerToggleTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        KeyLayout rightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false);

        NormalizedRect leftKeyRect = leftLayout.Rects[0][1];
        ushort leftKeyX = (ushort)Math.Clamp((int)Math.Round((leftKeyRect.X + (leftKeyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort leftKeyY = (ushort)Math.Clamp((int)Math.Round((leftKeyRect.Y + (leftKeyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        string leftKeyStorage = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 1);
        keymap.Mappings[0][leftKeyStorage] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue queue = new();
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame allUp = MakeFrame(contactCount: 0);

        InputFrame rightStartFive = MakeFrame(
            contactCount: 5,
            id0: 200, x0: 900, y0: 1500,
            id1: 201, x1: 1200, y1: 1550,
            id2: 202, x2: 1500, y2: 1600,
            id3: 203, x3: 1800, y3: 1650,
            id4: 204, x4: 2100, y4: 1700);
        InputFrame rightSwipeFive = MakeFrame(
            contactCount: 5,
            id0: 200, x0: 3200, y0: 1500,
            id1: 201, x1: 3500, y1: 1550,
            id2: 202, x2: 3800, y2: 1600,
            id3: 203, x3: 4100, y3: 1650,
            id4: 204, x4: 4400, y4: 1700);

        InputFrame leftStartFive = MakeFrame(
            contactCount: 5,
            id0: 210, x0: 900, y0: 1500,
            id1: 211, x1: 1200, y1: 1550,
            id2: 212, x2: 1500, y2: 1600,
            id3: 213, x3: 1800, y3: 1650,
            id4: 214, x4: 2100, y4: 1700);
        InputFrame leftSwipeFive = MakeFrame(
            contactCount: 5,
            id0: 210, x0: 3200, y0: 1500,
            id1: 211, x1: 3500, y1: 1550,
            id2: 212, x2: 3800, y2: 1600,
            id3: 213, x3: 4100, y3: 1650,
            id4: 214, x4: 4400, y4: 1700);

        // RHS swipe -> typing off.
        actor.Post(TrackpadSide.Right, in rightStartFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in rightSwipeFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in allUp, maxX, maxY, now);

        // While off, left key taps should be suppressed.
        now += MsToTicks(16);
        InputFrame leftKeyDownOff = MakeFrame(contactCount: 1, id0: 220, x0: leftKeyX, y0: leftKeyY);
        actor.Post(TrackpadSide.Left, in leftKeyDownOff, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // LHS swipe -> typing on.
        now += MsToTicks(20);
        actor.Post(TrackpadSide.Left, in leftStartFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in leftSwipeFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // After re-enable, left key tap should dispatch.
        now += MsToTicks(16);
        InputFrame leftKeyDownOn = MakeFrame(contactCount: 1, id0: 221, x0: leftKeyX, y0: leftKeyY);
        actor.Post(TrackpadSide.Left, in leftKeyDownOn, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        actor.WaitForIdle();

        int aTapCount = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                aTapCount++;
            }
        }

        if (aTapCount != 1)
        {
            failure = $"cross-side five-finger toggle dispatch mismatch (A taps={aTapCount}, expected=1)";
            return false;
        }

        if (!actor.Snapshot().TypingEnabled)
        {
            failure = "cross-side five-finger toggle left typing disabled at end of scenario";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunRightSideFiveFingerToggleResumeTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout rightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false);
        NormalizedRect rightKeyRect = rightLayout.Rects[0][1];
        ushort rightKeyX = (ushort)Math.Clamp((int)Math.Round((rightKeyRect.X + (rightKeyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort rightKeyY = (ushort)Math.Clamp((int)Math.Round((rightKeyRect.Y + (rightKeyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        string rightKeyStorage = GridKeyPosition.StorageKey(TrackpadSide.Right, 0, 1);
        keymap.Mappings[0][rightKeyStorage] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue queue = new();
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame allUp = MakeFrame(contactCount: 0);
        InputFrame startFive = MakeFrame(
            contactCount: 5,
            id0: 300, x0: 900, y0: 1500,
            id1: 301, x1: 1200, y1: 1550,
            id2: 302, x2: 1500, y2: 1600,
            id3: 303, x3: 1800, y3: 1650,
            id4: 304, x4: 2100, y4: 1700);
        InputFrame swipeFive = MakeFrame(
            contactCount: 5,
            id0: 300, x0: 3200, y0: 1500,
            id1: 301, x1: 3500, y1: 1550,
            id2: 302, x2: 3800, y2: 1600,
            id3: 303, x3: 4100, y3: 1650,
            id4: 304, x4: 4400, y4: 1700);

        // off
        actor.Post(TrackpadSide.Right, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in swipeFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in allUp, maxX, maxY, now);

        // on
        now += MsToTicks(20);
        actor.Post(TrackpadSide.Right, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in swipeFive, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in allUp, maxX, maxY, now);

        actor.WaitForIdle();
        while (queue.TryDequeue(out _, waitMs: 0))
        {
        }

        // right should dispatch immediately without any left-side frames.
        now += MsToTicks(12);
        InputFrame rightKeyDown = MakeFrame(contactCount: 1, id0: 305, x0: rightKeyX, y0: rightKeyY);
        actor.Post(TrackpadSide.Right, in rightKeyDown, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in allUp, maxX, maxY, now);
        actor.WaitForIdle();

        int aTapCount = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                aTapCount++;
            }
        }

        if (aTapCount != 1)
        {
            failure = $"right-side five-finger toggle resume mismatch (A taps={aTapCount}, expected=1)";
            return false;
        }

        if (!actor.Snapshot().TypingEnabled)
        {
            failure = "right-side five-finger toggle left typing disabled at end of scenario";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunChordShiftTapReleaseTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        NormalizedRect leftKeyRect = leftLayout.Rects[0][1];
        ushort leftKeyX = (ushort)Math.Clamp((int)Math.Round((leftKeyRect.X + (leftKeyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort leftKeyY = (ushort)Math.Clamp((int)Math.Round((leftKeyRect.Y + (leftKeyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        string leftKeyStorage = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 1);
        keymap.Mappings[0][leftKeyStorage] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue queue = new();
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame allUp = MakeFrame(contactCount: 0);

        // Quick 4-finger tap on right side.
        InputFrame rightChordTap = MakeFrame(
            contactCount: 4,
            id0: 330, x0: 900, y0: 1500,
            id1: 331, x1: 1200, y1: 1550,
            id2: 332, x2: 1500, y2: 1600,
            id3: 333, x3: 1800, y3: 1650);
        actor.Post(TrackpadSide.Right, in rightChordTap, maxX, maxY, now);

        // Follow-up frame with only non-tip (hover/linger), should not keep chord shift latched.
        now += MsToTicks(12);
        InputFrame rightHover = new()
        {
            ReportId = RawInputInterop.ReportIdMultitouch,
            ContactCount = 1,
            ScanTime = 0,
            IsButtonClicked = 0
        };
        rightHover.SetContact(0, new ContactFrame(334, 1200, 1500, 0x00));
        actor.Post(TrackpadSide.Right, in rightHover, maxX, maxY, now);

        now += MsToTicks(12);
        actor.Post(TrackpadSide.Right, in allUp, maxX, maxY, now);

        // Left key should not be shifted/stuck.
        now += MsToTicks(12);
        InputFrame leftKeyDown = MakeFrame(contactCount: 1, id0: 335, x0: leftKeyX, y0: leftKeyY);
        actor.Post(TrackpadSide.Left, in leftKeyDown, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        actor.WaitForIdle();

        bool sawShiftDown = false;
        bool sawShiftUp = false;
        int leftATaps = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown && dispatchEvent.VirtualKey == 0x10)
            {
                sawShiftDown = true;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.ModifierUp && dispatchEvent.VirtualKey == 0x10)
            {
                sawShiftUp = true;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyTap &&
                     dispatchEvent.VirtualKey == 0x41 &&
                     dispatchEvent.Side == TrackpadSide.Left)
            {
                leftATaps++;
            }
        }

        if (leftATaps != 1)
        {
            failure = $"chord-shift tap release mismatch (left A taps={leftATaps}, expected=1)";
            return false;
        }

        if (sawShiftDown && !sawShiftUp)
        {
            failure = "chord-shift tap left Shift stuck down";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunTypingToggleDispatchResumeTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        NormalizedRect toggleRect = leftLayout.Rects[0][2];
        NormalizedRect keyRect = leftLayout.Rects[0][1];

        ushort toggleX = (ushort)Math.Clamp((int)Math.Round((toggleRect.X + (toggleRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort toggleY = (ushort)Math.Clamp((int)Math.Round((toggleRect.Y + (toggleRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        string toggleStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 2);
        string keyStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 1);
        keymap.Mappings[0][toggleStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "TypingToggle" },
            Hold = null
        };
        keymap.Mappings[0][keyStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue queue = new();
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame allUp = MakeFrame(contactCount: 0);

        // Baseline: key dispatch works.
        InputFrame keyDown1 = MakeFrame(contactCount: 1, id0: 90, x0: keyX, y0: keyY);
        actor.Post(TrackpadSide.Left, in keyDown1, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // Toggle typing off.
        now += MsToTicks(12);
        InputFrame toggleDownOff = MakeFrame(contactCount: 1, id0: 91, x0: toggleX, y0: toggleY);
        actor.Post(TrackpadSide.Left, in toggleDownOff, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // While typing off: key dispatch should be suppressed.
        now += MsToTicks(12);
        InputFrame keyDownSuppressed = MakeFrame(contactCount: 1, id0: 92, x0: keyX, y0: keyY);
        actor.Post(TrackpadSide.Left, in keyDownSuppressed, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // Toggle typing back on.
        now += MsToTicks(12);
        InputFrame toggleDownOn = MakeFrame(contactCount: 1, id0: 93, x0: toggleX, y0: toggleY);
        actor.Post(TrackpadSide.Left, in toggleDownOn, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // After re-enable: key dispatch should resume.
        now += MsToTicks(12);
        InputFrame keyDown2 = MakeFrame(contactCount: 1, id0: 94, x0: keyX, y0: keyY);
        actor.Post(TrackpadSide.Left, in keyDown2, maxX, maxY, now);
        now += MsToTicks(12);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        actor.WaitForIdle();

        int tapCount = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                tapCount++;
            }
        }

        // Expected taps:
        // 1) baseline while typing on
        // 2) after toggling back on
        if (tapCount != 2)
        {
            failure = $"typing toggle dispatch resume mismatch (A taps={tapCount}, expected=2)";
            return false;
        }

        if (!actor.Snapshot().TypingEnabled)
        {
            failure = "typing toggle dispatch resume left typing disabled at end of scenario";
            return false;
        }

        // Swipe toggle path: off -> on should also restore key dispatch.
        KeymapStore swipeKeymap = KeymapStore.LoadBundledDefault();
        swipeKeymap.Mappings[0][keyStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };
        TouchProcessorCore swipeCore = TouchProcessorFactory.CreateDefault(swipeKeymap);
        using DispatchEventQueue swipeQueue = new();
        using TouchProcessorActor swipeActor = new(swipeCore, dispatchQueue: swipeQueue);

        now = 0;
        InputFrame startFive = MakeFrame(
            contactCount: 5,
            id0: 100, x0: 900, y0: 1500,
            id1: 101, x1: 1200, y1: 1550,
            id2: 102, x2: 1500, y2: 1600,
            id3: 103, x3: 1800, y3: 1650,
            id4: 104, x4: 2100, y4: 1700);
        InputFrame swipeFive = MakeFrame(
            contactCount: 5,
            id0: 100, x0: 3200, y0: 1500,
            id1: 101, x1: 3500, y1: 1550,
            id2: 102, x2: 3800, y2: 1600,
            id3: 103, x3: 4100, y3: 1650,
            id4: 104, x4: 4400, y4: 1700);

        swipeActor.Post(TrackpadSide.Left, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in swipeFive, maxX, maxY, now); // off
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // Suppressed while off.
        now += MsToTicks(12);
        InputFrame swipeKeyDownSuppressed = MakeFrame(contactCount: 1, id0: 105, x0: keyX, y0: keyY);
        swipeActor.Post(TrackpadSide.Left, in swipeKeyDownSuppressed, maxX, maxY, now);
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // Back on via second swipe.
        now += MsToTicks(20);
        swipeActor.Post(TrackpadSide.Left, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in swipeFive, maxX, maxY, now); // on
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        // Dispatch should resume.
        now += MsToTicks(12);
        InputFrame swipeKeyDownRestored = MakeFrame(contactCount: 1, id0: 106, x0: keyX, y0: keyY);
        swipeActor.Post(TrackpadSide.Left, in swipeKeyDownRestored, maxX, maxY, now);
        now += MsToTicks(12);
        swipeActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);

        swipeActor.WaitForIdle();
        int swipeTapCount = 0;
        while (swipeQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                swipeTapCount++;
            }
        }

        if (swipeTapCount != 1)
        {
            failure = $"five-finger typing toggle dispatch resume mismatch (A taps={swipeTapCount}, expected=1)";
            return false;
        }

        if (!swipeActor.Snapshot().TypingEnabled)
        {
            failure = "five-finger typing toggle left typing disabled at end of scenario";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunReplayTests(out string failure)
    {
        string tempRoot = Path.Combine(Path.GetTempPath(), "GlassToKeySelfTest", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        string capturePath = Path.Combine(tempRoot, "fixture.atpcap");
        string fixturePath = Path.Combine(tempRoot, "fixture.json");
        string tracePath = Path.Combine(tempRoot, "replay-trace.json");
        try
        {
            RawInputDeviceSnapshot snapshot = new(
                DeviceName: "selftest-device",
                Info: new RawInputDeviceInfo(VendorId: 0x8910, ProductId: 0x0265, UsagePage: RawInputInterop.UsagePageDigitizer, Usage: RawInputInterop.UsageTouchpad),
                Tag: new RawInputDeviceTag(Index: 0, Hash: 0x00ABCDEF));

            using (InputCaptureWriter writer = new(capturePath))
            {
                Span<byte> valid = stackalloc byte[PtpReport.ExpectedSize];
                valid[0] = RawInputInterop.ReportIdMultitouch;
                WriteContact(valid, 0, 0x03, 5, 1500, 2500);
                valid[46] = 0x11;
                valid[47] = 0x00;
                valid[48] = 1;
                valid[49] = 0;
                writer.WriteFrame(snapshot, valid, arrivalQpcTicks: 100);

                Span<byte> nonTouch = stackalloc byte[PtpReport.ExpectedSize];
                nonTouch[0] = 0x09;
                writer.WriteFrame(snapshot, nonTouch, arrivalQpcTicks: 200);

                Span<byte> shortPayload = stackalloc byte[8];
                writer.WriteFrame(snapshot, shortPayload, arrivalQpcTicks: 300);
            }

            ReplayRunner runner = new();
            ReplayRunResult baseline = runner.Run(capturePath, fixturePath: null, traceOutputPath: tracePath);
            if (!baseline.Success)
            {
                failure = "baseline replay pass failed determinism check";
                return false;
            }

            if (!File.Exists(tracePath))
            {
                failure = "replay trace output file was not created";
                return false;
            }

            using (JsonDocument traceDoc = JsonDocument.Parse(File.ReadAllText(tracePath)))
            {
                JsonElement root = traceDoc.RootElement;
                if (!root.TryGetProperty("EngineDiagnostics", out JsonElement diagnostics) ||
                    diagnostics.ValueKind != JsonValueKind.Array ||
                    diagnostics.GetArrayLength() == 0)
                {
                    failure = "replay trace did not include engine diagnostics";
                    return false;
                }

                bool sawFrameDiagnostic = false;
                foreach (JsonElement entry in diagnostics.EnumerateArray())
                {
                    if (entry.TryGetProperty("Kind", out JsonElement kind) &&
                        string.Equals(kind.GetString(), "Frame", StringComparison.Ordinal))
                    {
                        sawFrameDiagnostic = true;
                        break;
                    }
                }

                if (!sawFrameDiagnostic)
                {
                    failure = "replay trace diagnostics missing frame events";
                    return false;
                }

                if (!root.TryGetProperty("FirstPass", out JsonElement firstPass) ||
                    !firstPass.TryGetProperty("DispatchSuppressedTypingDisabled", out _))
                {
                    failure = "replay trace first-pass metrics missing suppression counters";
                    return false;
                }
            }

            string expectedFingerprint = $"0x{baseline.FirstPass.Fingerprint:X16}";
            File.WriteAllText(
                fixturePath,
                JsonSerializer.Serialize(
                    new
                    {
                        capturePath = "fixture.atpcap",
                        expected = new
                        {
                            fingerprint = expectedFingerprint,
                            intentFingerprint = $"0x{baseline.FirstPass.EngineIntentFingerprint:X16}",
                            intentTransitions = baseline.FirstPass.EngineTransitionCount,
                            dispatchFingerprint = $"0x{baseline.FirstPass.DispatchFingerprint:X16}",
                            dispatchEvents = baseline.FirstPass.DispatchEventCount,
                            dispatchEnqueued = baseline.FirstPass.DispatchEnqueued,
                            dispatchSuppressedTypingDisabled = baseline.FirstPass.DispatchSuppressedTypingDisabled,
                            dispatchSuppressedRingFull = baseline.FirstPass.DispatchSuppressedRingFull,
                            modifierUnbalanced = baseline.FirstPass.ModifierUnbalancedCount,
                            repeatStarts = baseline.FirstPass.RepeatStartCount,
                            repeatCancels = baseline.FirstPass.RepeatCancelCount,
                            framesSeen = baseline.FirstPass.Metrics.FramesSeen,
                            framesParsed = baseline.FirstPass.Metrics.FramesParsed,
                            framesDispatched = baseline.FirstPass.Metrics.FramesDispatched,
                            framesDropped = baseline.FirstPass.Metrics.FramesDropped
                        }
                    },
                    new JsonSerializerOptions { WriteIndented = true }));

            ReplayRunResult validated = runner.Run(capturePath, fixturePath);
            if (!validated.Success)
            {
                failure = "fixture replay validation failed";
                return false;
            }
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunEngineIntentTests(out string failure)
    {
        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        long now = 0;
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        NormalizedRect keyRect = leftLayout.Rects[0][2];
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        // key candidate -> typing committed path
        core.ResetState();
        InputFrame keyDown = MakeFrame(contactCount: 1, id0: 1, x0: keyX, y0: keyY);
        core.ProcessFrame(TrackpadSide.Left, in keyDown, maxX, maxY, now);
        now += MsToTicks(60);
        core.ProcessFrame(TrackpadSide.Left, in keyDown, maxX, maxY, now);
        now += MsToTicks(10);
        InputFrame allUp = MakeFrame(contactCount: 0);
        core.ProcessFrame(TrackpadSide.Left, in allUp, maxX, maxY, now);
        TouchProcessorSnapshot insideGraceSnapshot = core.Snapshot(now + MsToTicks(20));
        if (insideGraceSnapshot.IntentMode != IntentMode.TypingCommitted)
        {
            failure = "expected typingCommitted while inside typing grace window";
            return false;
        }

        TouchProcessorSnapshot postGraceSnapshot = core.Snapshot(now + MsToTicks(200));
        if (postGraceSnapshot.IntentMode != IntentMode.Idle)
        {
            failure = "expected idle after typing grace elapsed without additional frames";
            return false;
        }

        IntentTransition[] transitions = new IntentTransition[64];
        int transitionCount = core.CopyIntentTransitions(transitions);
        if (!ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.KeyCandidate) ||
            !ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.TypingCommitted) ||
            !ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.Idle))
        {
            failure = "expected keyCandidate->typingCommitted->idle transitions were missing";
            return false;
        }

        // mouse candidate -> mouse active path
        core.ResetState();
        now = 0;
        BindingIndex leftIndex = BindingIndex.Build(leftLayout, TrackpadSide.Left, layer: 0, keymap);
        (ushort offX, ushort offY) = FindOffKeyPoint(leftIndex, maxX, maxY, preferTopLeft: true);
        InputFrame offKey = MakeFrame(contactCount: 1, id0: 2, x0: offX, y0: offY);
        core.ProcessFrame(TrackpadSide.Left, in offKey, maxX, maxY, now);
        now += MsToTicks(10);
        (ushort movedX, ushort movedY) = FindOffKeyPoint(leftIndex, maxX, maxY, preferTopLeft: false);
        InputFrame moved = MakeFrame(contactCount: 1, id0: 2, x0: movedX, y0: movedY);
        core.ProcessFrame(TrackpadSide.Left, in moved, maxX, maxY, now);
        transitionCount = core.CopyIntentTransitions(transitions);
        if (!ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.MouseCandidate) ||
            !ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.MouseActive))
        {
            failure = "expected mouseCandidate->mouseActive transitions were missing";
            return false;
        }

        // gesture candidate path
        core.ResetState();
        now = 0;
        InputFrame gesture = MakeFrame(contactCount: 2, id0: 10, x0: 2000, y0: 1200, id1: 11, x1: 2600, y1: 1300);
        core.ProcessFrame(TrackpadSide.Left, in gesture, maxX, maxY, now);
        transitionCount = core.CopyIntentTransitions(transitions);
        if (!ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.GestureCandidate))
        {
            failure = "expected gestureCandidate transition was missing";
            return false;
        }

        // gesture candidate path: 3-finger staggered landing should still enter gesture mode.
        core.ResetState();
        now = 0;
        InputFrame g3a = MakeFrame(contactCount: 1, id0: 30, x0: 1600, y0: 1500);
        InputFrame g3b = MakeFrame(contactCount: 2, id0: 30, x0: 1600, y0: 1500, id1: 31, x1: 2000, y1: 1550);
        InputFrame g3c = MakeFrame(contactCount: 3, id0: 30, x0: 1600, y0: 1500, id1: 31, x1: 2000, y1: 1550, id2: 32, x2: 2400, y2: 1600);
        core.ProcessFrame(TrackpadSide.Left, in g3a, maxX, maxY, now);
        now += MsToTicks(25);
        core.ProcessFrame(TrackpadSide.Left, in g3b, maxX, maxY, now);
        now += MsToTicks(25);
        core.ProcessFrame(TrackpadSide.Left, in g3c, maxX, maxY, now);
        transitionCount = core.CopyIntentTransitions(transitions);
        if (!ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.GestureCandidate))
        {
            failure = "expected 3-finger gestureCandidate transition was missing";
            return false;
        }

        // gesture candidate path: 5-finger staggered landing should still enter gesture mode.
        core.ResetState();
        now = 0;
        InputFrame g5a = MakeFrame(contactCount: 3, id0: 40, x0: 1200, y0: 1400, id1: 41, x1: 1600, y1: 1450, id2: 42, x2: 2000, y2: 1500);
        InputFrame g5b = MakeFrame(contactCount: 4, id0: 40, x0: 1200, y0: 1400, id1: 41, x1: 1600, y1: 1450, id2: 42, x2: 2000, y2: 1500, id3: 43, x3: 2400, y3: 1550);
        InputFrame g5c = MakeFrame(contactCount: 5, id0: 40, x0: 1200, y0: 1400, id1: 41, x1: 1600, y1: 1450, id2: 42, x2: 2000, y2: 1500, id3: 43, x3: 2400, y3: 1550, id4: 44, x4: 2800, y4: 1600);
        core.ProcessFrame(TrackpadSide.Left, in g5a, maxX, maxY, now);
        now += MsToTicks(20);
        core.ProcessFrame(TrackpadSide.Left, in g5b, maxX, maxY, now);
        now += MsToTicks(20);
        core.ProcessFrame(TrackpadSide.Left, in g5c, maxX, maxY, now);
        transitionCount = core.CopyIntentTransitions(transitions);
        if (!ContainsMode(transitions.AsSpan(0, transitionCount), IntentMode.GestureCandidate))
        {
            failure = "expected 5-finger gestureCandidate transition was missing";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static (ushort X, ushort Y) FindOffKeyPoint(BindingIndex index, ushort maxX, ushort maxY, bool preferTopLeft)
    {
        const int steps = 24;
        if (preferTopLeft)
        {
            for (int yi = 0; yi <= steps; yi++)
            {
                double y = (yi + 0.5) / (steps + 1.0);
                for (int xi = 0; xi <= steps; xi++)
                {
                    double x = (xi + 0.5) / (steps + 1.0);
                    if (!index.HitTest(x, y).Found)
                    {
                        ushort rawX = (ushort)Math.Clamp((int)Math.Round(x * maxX), 1, maxX - 1);
                        ushort rawY = (ushort)Math.Clamp((int)Math.Round(y * maxY), 1, maxY - 1);
                        return (rawX, rawY);
                    }
                }
            }
        }
        else
        {
            for (int yi = steps; yi >= 0; yi--)
            {
                double y = (yi + 0.5) / (steps + 1.0);
                for (int xi = steps; xi >= 0; xi--)
                {
                    double x = (xi + 0.5) / (steps + 1.0);
                    if (!index.HitTest(x, y).Found)
                    {
                        ushort rawX = (ushort)Math.Clamp((int)Math.Round(x * maxX), 1, maxX - 1);
                        ushort rawY = (ushort)Math.Clamp((int)Math.Round(y * maxY), 1, maxY - 1);
                        return (rawX, rawY);
                    }
                }
            }
        }

        return (1, 1);
    }

    private static bool RunEngineDispatchTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        NormalizedRect keyRect = leftLayout.Rects[0][2];
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue queue = new();
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame keyDown = MakeFrame(contactCount: 1, id0: 42, x0: keyX, y0: keyY);
        InputFrame allUp = MakeFrame(contactCount: 0);
        actor.Post(TrackpadSide.Left, in keyDown, maxX, maxY, now);
        now += MsToTicks(10);
        actor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        actor.WaitForIdle();

        bool sawTap = false;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                sawTap = true;
            }
        }

        if (!sawTap)
        {
            failure = "expected key tap dispatch event was missing";
            return false;
        }

        // Snap rule: if release lands inside any key, dispatch that direct hit and do not run snap.
        KeymapStore directHitKeymap = KeymapStore.LoadBundledDefault();
        string snapStartStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 1, 3);
        string snapTargetStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 1, 4);
        directHitKeymap.Mappings[0][snapStartStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "S" },
            Hold = null
        };
        directHitKeymap.Mappings[0][snapTargetStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };
        TouchProcessorCore directHitCore = TouchProcessorFactory.CreateDefault(directHitKeymap);
        directHitCore.Configure(directHitCore.CurrentConfig with { DragCancelMm = 1000.0 });
        using DispatchEventQueue directHitQueue = new();
        using TouchProcessorActor directHitActor = new(directHitCore, dispatchQueue: directHitQueue);

        NormalizedRect startRect = leftLayout.Rects[1][3]; // S
        NormalizedRect targetRect = leftLayout.Rects[1][4]; // A
        ushort startX = (ushort)Math.Clamp((int)Math.Round((startRect.X + (startRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort startY = (ushort)Math.Clamp((int)Math.Round((startRect.Y + (startRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort targetX = (ushort)Math.Clamp((int)Math.Round((targetRect.X + (targetRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort targetY = (ushort)Math.Clamp((int)Math.Round((targetRect.Y + (targetRect.Height * 0.5)) * maxY), 1, maxY - 1);

        now = 0;
        InputFrame dragDown = MakeFrame(contactCount: 1, id0: 80, x0: startX, y0: startY);
        InputFrame dragMove = MakeFrame(contactCount: 1, id0: 80, x0: targetX, y0: targetY);
        InputFrame dragUp = MakeFrame(contactCount: 0);
        directHitActor.Post(TrackpadSide.Left, in dragDown, maxX, maxY, now);
        now += MsToTicks(10);
        directHitActor.Post(TrackpadSide.Left, in dragMove, maxX, maxY, now);
        now += MsToTicks(10);
        directHitActor.Post(TrackpadSide.Left, in dragUp, maxX, maxY, now);
        directHitActor.WaitForIdle();
        TouchProcessorSnapshot directHitSnapshot = directHitActor.Snapshot();

        bool sawATap = false;
        bool sawSTap = false;
        List<string> directHitEvents = new();
        while (directHitQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            directHitEvents.Add($"{dispatchEvent.Kind}:0x{dispatchEvent.VirtualKey:X2}:{dispatchEvent.DispatchLabel}");
            if (dispatchEvent.Kind != DispatchEventKind.KeyTap)
            {
                continue;
            }

            if (dispatchEvent.VirtualKey == 0x41)
            {
                sawATap = true;
            }
            else if (dispatchEvent.VirtualKey == 0x53)
            {
                sawSTap = true;
            }
        }

        if (sawATap || sawSTap)
        {
            failure = $"cross-key drag should cancel dispatch (expected no key taps after S->A drag; events=[{string.Join(", ", directHitEvents)}])";
            return false;
        }

        if (directHitSnapshot.SnapAttempts != 0)
        {
            failure = $"direct-hit release incorrectly used snap (snapAttempts={directHitSnapshot.SnapAttempts}, expected=0)";
            return false;
        }

        // Snap rule: off-key touch starts in typing mode should still be eligible for snap on release.
        KeyLayout snapGapLeftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true, keySpacingPercent: 30.0);
        KeyLayout snapGapRightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false, keySpacingPercent: 30.0);
        TouchProcessorCore offKeySnapCore = TouchProcessorFactory.CreateDefault(directHitKeymap);
        offKeySnapCore.ConfigureLayouts(snapGapLeftLayout, snapGapRightLayout);
        offKeySnapCore.Configure(offKeySnapCore.CurrentConfig with { DragCancelMm = 1000.0, SnapRadiusPercent = 200.0 });
        using DispatchEventQueue offKeySnapQueue = new();
        using TouchProcessorActor offKeySnapActor = new(offKeySnapCore, dispatchQueue: offKeySnapQueue);

        NormalizedRect snapPrimeRect = snapGapLeftLayout.Rects[1][3]; // S
        NormalizedRect snapResolveRect = snapGapLeftLayout.Rects[1][4]; // A
        ushort snapPrimeX = (ushort)Math.Clamp((int)Math.Round((snapPrimeRect.X + (snapPrimeRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort snapPrimeY = (ushort)Math.Clamp((int)Math.Round((snapPrimeRect.Y + (snapPrimeRect.Height * 0.5)) * maxY), 1, maxY - 1);

        double resolveCenterY = snapResolveRect.Y + (snapResolveRect.Height * 0.5);
        double offKeySnapXNorm = 0.0;
        double offKeySnapYNorm = 0.0;
        bool foundOffKeySnap = false;

        for (int yStep = 0; yStep <= 30 && !foundOffKeySnap; yStep++)
        {
            double yOffset = yStep * 0.002;
            for (int sign = 0; sign < 2 && !foundOffKeySnap; sign++)
            {
                double y = resolveCenterY + (sign == 0 ? yOffset : -yOffset);
                if (y <= 0.01 || y >= 0.99)
                {
                    continue;
                }

                for (double x = snapResolveRect.X + snapResolveRect.Width + 0.001; x < 0.99; x += 0.002)
                {
                    if (IsInsideAnyKeyRect(snapGapLeftLayout, x, y))
                    {
                        continue;
                    }

                    (int row, int col, _) = FindNearestKeyCenter(snapGapLeftLayout, x, y);
                    if (row == 1 && col == 4)
                    {
                        offKeySnapXNorm = x;
                        offKeySnapYNorm = y;
                        foundOffKeySnap = true;
                        break;
                    }
                }
            }
        }

        if (!foundOffKeySnap)
        {
            failure = "failed to find an off-key snap probe point";
            return false;
        }

        (int nearestRow, int nearestCol, double nearestDistSq) = FindNearestKeyCenter(snapGapLeftLayout, offKeySnapXNorm, offKeySnapYNorm);
        if (nearestRow != 1 || nearestCol != 4)
        {
            failure = $"off-key snap probe nearest key mismatch (nearest={nearestRow}:{nearestCol}, expected=1:4, distSq={nearestDistSq:F6})";
            return false;
        }

        ushort offKeySnapX = (ushort)Math.Clamp((int)Math.Round(offKeySnapXNorm * maxX), 1, maxX - 1);
        ushort offKeySnapY = (ushort)Math.Clamp((int)Math.Round(offKeySnapYNorm * maxY), 1, maxY - 1);

        now = 0;
        InputFrame typingPrimeDown = MakeFrame(contactCount: 1, id0: 95, x0: snapPrimeX, y0: snapPrimeY);
        InputFrame typingPrimeUp = MakeFrame(contactCount: 0);
        offKeySnapActor.Post(TrackpadSide.Left, in typingPrimeDown, maxX, maxY, now);
        now += MsToTicks(60);
        offKeySnapActor.Post(TrackpadSide.Left, in typingPrimeDown, maxX, maxY, now);
        now += MsToTicks(10);
        offKeySnapActor.Post(TrackpadSide.Left, in typingPrimeUp, maxX, maxY, now);
        offKeySnapActor.WaitForIdle();
        while (offKeySnapQueue.TryDequeue(out _, waitMs: 0))
        {
            // Drain priming events.
        }

        InputFrame offKeySnapDown = MakeFrame(contactCount: 1, id0: 96, x0: offKeySnapX, y0: offKeySnapY);
        InputFrame offKeySnapUp = MakeFrame(contactCount: 0);
        now += MsToTicks(20);
        offKeySnapActor.Post(TrackpadSide.Left, in offKeySnapDown, maxX, maxY, now);
        now += MsToTicks(12);
        offKeySnapActor.Post(TrackpadSide.Left, in offKeySnapUp, maxX, maxY, now);
        offKeySnapActor.WaitForIdle();
        TouchProcessorSnapshot offKeySnapSnapshot = offKeySnapActor.Snapshot();

        bool sawSnapATap = false;
        List<string> offKeySnapEvents = new();
        while (offKeySnapQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            offKeySnapEvents.Add($"{dispatchEvent.Kind}:0x{dispatchEvent.VirtualKey:X2}:{dispatchEvent.DispatchLabel}");
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                sawSnapATap = true;
            }
        }

        if (!sawSnapATap)
        {
            failure = $"off-key snap did not resolve to A (events=[{string.Join(", ", offKeySnapEvents)}], snap={offKeySnapSnapshot.SnapAccepted}/{offKeySnapSnapshot.SnapAttempts})";
            return false;
        }

        // MO() bypass: if a key touch starts before MO goes active, release should still resolve on the MO layer.
        KeymapStore momentaryBypassKeymap = KeymapStore.LoadBundledDefault();
        string moStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 0);
        string moTargetStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 1);
        momentaryBypassKeymap.Mappings[0][moStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "MO(1)" },
            Hold = null
        };
        momentaryBypassKeymap.Mappings[0][moTargetStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "None" },
            Hold = null
        };
        momentaryBypassKeymap.Mappings[1][moTargetStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        NormalizedRect moRect = leftLayout.Rects[0][0];
        NormalizedRect moTargetRect = leftLayout.Rects[0][1];
        ushort moX = (ushort)Math.Clamp((int)Math.Round((moRect.X + (moRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort moY = (ushort)Math.Clamp((int)Math.Round((moRect.Y + (moRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort moTargetX = (ushort)Math.Clamp((int)Math.Round((moTargetRect.X + (moTargetRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort moTargetY = (ushort)Math.Clamp((int)Math.Round((moTargetRect.Y + (moTargetRect.Height * 0.5)) * maxY), 1, maxY - 1);

        InputFrame moTargetDown = MakeFrame(contactCount: 1, id0: 150, x0: moTargetX, y0: moTargetY);
        InputFrame moAndTargetDown = MakeFrame(contactCount: 2, id0: 150, x0: moTargetX, y0: moTargetY, id1: 151, x1: moX, y1: moY);
        InputFrame moOnlyDown = MakeFrame(contactCount: 1, id0: 151, x0: moX, y0: moY);
        InputFrame moAllUp = MakeFrame(contactCount: 0);

        // Sanity: MO key should actually activate layer 1 when held.
        TouchProcessorCore moSanityCore = TouchProcessorFactory.CreateDefault(momentaryBypassKeymap);
        using DispatchEventQueue moSanityQueue = new();
        using TouchProcessorActor moSanityActor = new(moSanityCore, dispatchQueue: moSanityQueue);
        now = 0;
        moSanityActor.Post(TrackpadSide.Left, in moOnlyDown, maxX, maxY, now);
        moSanityActor.WaitForIdle();
        TouchProcessorSnapshot moSanitySnapshot = moSanityActor.Snapshot();
        if (moSanitySnapshot.ActiveLayer != 1 || !moSanitySnapshot.MomentaryLayerActive)
        {
            failure = $"MO sanity failed to activate layer 1 (snapshot={moSanitySnapshot.ToSummary()})";
            return false;
        }

        // Mouse-only mode (typing disabled): MO should allow key dispatch.
        TouchProcessorCore moBypassMouseCore = TouchProcessorFactory.CreateDefault(momentaryBypassKeymap);
        moBypassMouseCore.SetTypingEnabled(false);
        using DispatchEventQueue moBypassMouseQueue = new();
        using TouchProcessorActor moBypassMouseActor = new(moBypassMouseCore, dispatchQueue: moBypassMouseQueue);

        now = 0;
        moBypassMouseActor.Post(TrackpadSide.Left, in moTargetDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassMouseActor.Post(TrackpadSide.Left, in moAndTargetDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassMouseActor.Post(TrackpadSide.Left, in moOnlyDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassMouseActor.Post(TrackpadSide.Left, in moAllUp, maxX, maxY, now);
        moBypassMouseActor.WaitForIdle();
        TouchProcessorSnapshot moBypassMouseSnapshot = moBypassMouseActor.Snapshot();

        bool sawMouseModeBypassTap = false;
        List<string> moBypassMouseEvents = new();
        while (moBypassMouseQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            moBypassMouseEvents.Add($"{dispatchEvent.Kind}:0x{dispatchEvent.VirtualKey:X2}:{dispatchEvent.DispatchLabel}");
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                sawMouseModeBypassTap = true;
            }
        }

        if (!sawMouseModeBypassTap)
        {
            failure = $"MO bypass failed in mouse-only mode (events=[{string.Join(", ", moBypassMouseEvents)}], snapshot={moBypassMouseSnapshot.ToSummary()})";
            return false;
        }

        // Keyboard-only mode: MO should bypass keyboard-only intent lock for dispatch.
        TouchProcessorCore moBypassKeyboardCore = TouchProcessorFactory.CreateDefault(momentaryBypassKeymap);
        moBypassKeyboardCore.SetTypingEnabled(true);
        moBypassKeyboardCore.SetKeyboardModeEnabled(true);
        using DispatchEventQueue moBypassKeyboardQueue = new();
        using TouchProcessorActor moBypassKeyboardActor = new(moBypassKeyboardCore, dispatchQueue: moBypassKeyboardQueue);

        now = 0;
        moBypassKeyboardActor.Post(TrackpadSide.Left, in moTargetDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassKeyboardActor.Post(TrackpadSide.Left, in moAndTargetDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassKeyboardActor.Post(TrackpadSide.Left, in moOnlyDown, maxX, maxY, now);
        now += MsToTicks(8);
        moBypassKeyboardActor.Post(TrackpadSide.Left, in moAllUp, maxX, maxY, now);
        moBypassKeyboardActor.WaitForIdle();

        bool sawKeyboardModeBypassTap = false;
        List<string> moBypassKeyboardEvents = new();
        while (moBypassKeyboardQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            moBypassKeyboardEvents.Add($"{dispatchEvent.Kind}:0x{dispatchEvent.VirtualKey:X2}:{dispatchEvent.DispatchLabel}");
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                sawKeyboardModeBypassTap = true;
            }
        }

        if (!sawKeyboardModeBypassTap)
        {
            failure = $"MO bypass failed in keyboard-only mode (events=[{string.Join(", ", moBypassKeyboardEvents)}])";
            return false;
        }

        KeymapStore modifierKeymap = KeymapStore.LoadBundledDefault();
        string storageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 2);
        modifierKeymap.Mappings[0][storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "Shift" },
            Hold = null
        };

        TouchProcessorCore modifierCore = TouchProcessorFactory.CreateDefault(modifierKeymap);
        using DispatchEventQueue modifierQueue = new();
        using TouchProcessorActor modifierActor = new(modifierCore, dispatchQueue: modifierQueue);

        now = 0;
        InputFrame modDown = MakeFrame(contactCount: 1, id0: 43, x0: keyX, y0: keyY);
        InputFrame modUp = MakeFrame(contactCount: 0);
        modifierActor.Post(TrackpadSide.Left, in modDown, maxX, maxY, now);
        now += MsToTicks(20);
        modifierActor.Post(TrackpadSide.Left, in modUp, maxX, maxY, now);
        modifierActor.WaitForIdle();

        int modifierDown = 0;
        int modifierUp = 0;
        while (modifierQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown)
            {
                modifierDown++;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.ModifierUp)
            {
                modifierUp++;
            }
        }

        if (modifierDown == 0 || modifierDown != modifierUp)
        {
            failure = $"modifier balance mismatch (down={modifierDown}, up={modifierUp})";
            return false;
        }

        // Held modifier should remain active across multiple taps until explicit release,
        // even if the holding finger drifts past drag-cancel distance.
        KeymapStore heldModifierKeymap = KeymapStore.LoadBundledDefault();
        string heldTapStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Left, 0, 3);
        heldModifierKeymap.Mappings[0][storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "Shift" },
            Hold = null
        };
        heldModifierKeymap.Mappings[0][heldTapStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "A" },
            Hold = null
        };

        TouchProcessorCore heldModifierCore = TouchProcessorFactory.CreateDefault(heldModifierKeymap);
        using DispatchEventQueue heldModifierQueue = new();
        using TouchProcessorActor heldModifierActor = new(heldModifierCore, dispatchQueue: heldModifierQueue);

        NormalizedRect heldModifierRect = leftLayout.Rects[0][2];
        NormalizedRect heldTapRect = leftLayout.Rects[0][3];
        ushort heldModifierX = (ushort)Math.Clamp((int)Math.Round((heldModifierRect.X + (heldModifierRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort heldModifierY = (ushort)Math.Clamp((int)Math.Round((heldModifierRect.Y + (heldModifierRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort heldTapX = (ushort)Math.Clamp((int)Math.Round((heldTapRect.X + (heldTapRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort heldTapY = (ushort)Math.Clamp((int)Math.Round((heldTapRect.Y + (heldTapRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort heldModifierDriftX = (ushort)Math.Clamp(heldModifierX + 500, 1, maxX - 1);

        now = 0;
        InputFrame heldShiftDown = MakeFrame(contactCount: 1, id0: 53, x0: heldModifierX, y0: heldModifierY);
        InputFrame heldShiftDrift = MakeFrame(contactCount: 1, id0: 53, x0: heldModifierDriftX, y0: heldModifierY);
        InputFrame heldTap1Down = MakeFrame(contactCount: 2, id0: 53, x0: heldModifierDriftX, y0: heldModifierY, id1: 54, x1: heldTapX, y1: heldTapY);
        InputFrame heldTap1Up = MakeFrame(contactCount: 1, id0: 53, x0: heldModifierDriftX, y0: heldModifierY);
        InputFrame heldTap2Down = MakeFrame(contactCount: 2, id0: 53, x0: heldModifierDriftX, y0: heldModifierY, id1: 55, x1: heldTapX, y1: heldTapY);
        InputFrame heldTap2Up = MakeFrame(contactCount: 1, id0: 53, x0: heldModifierDriftX, y0: heldModifierY);
        InputFrame heldAllUp = MakeFrame(contactCount: 0);
        heldModifierActor.Post(TrackpadSide.Left, in heldShiftDown, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldShiftDrift, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldTap1Down, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldTap1Up, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldTap2Down, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldTap2Up, maxX, maxY, now);
        now += MsToTicks(8);
        heldModifierActor.Post(TrackpadSide.Left, in heldAllUp, maxX, maxY, now);
        heldModifierActor.WaitForIdle();

        int eventIndex = 0;
        int shiftDownIndex = -1;
        int shiftUpIndex = -1;
        int firstTapIndex = -1;
        int lastTapIndex = -1;
        int heldTapCount = 0;
        bool earlyShiftUp = false;
        List<string> heldModifierEvents = new();
        while (heldModifierQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            heldModifierEvents.Add($"{dispatchEvent.Kind}:0x{dispatchEvent.VirtualKey:X2}:{dispatchEvent.DispatchLabel}");
            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown && dispatchEvent.VirtualKey == 0x10 && shiftDownIndex < 0)
            {
                shiftDownIndex = eventIndex;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.ModifierUp && dispatchEvent.VirtualKey == 0x10)
            {
                if (heldTapCount < 2)
                {
                    earlyShiftUp = true;
                }
                if (shiftUpIndex < 0)
                {
                    shiftUpIndex = eventIndex;
                }
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x41)
            {
                if (firstTapIndex < 0)
                {
                    firstTapIndex = eventIndex;
                }
                lastTapIndex = eventIndex;
                heldTapCount++;
            }

            eventIndex++;
        }

        if (shiftDownIndex < 0 ||
            shiftUpIndex < 0 ||
            heldTapCount != 2 ||
            firstTapIndex < 0 ||
            lastTapIndex < 0 ||
            shiftDownIndex > firstTapIndex ||
            shiftUpIndex < lastTapIndex ||
            earlyShiftUp)
        {
            failure = $"held modifier sequencing mismatch (downIdx={shiftDownIndex}, upIdx={shiftUpIndex}, firstTap={firstTapIndex}, lastTap={lastTapIndex}, tapCount={heldTapCount}, earlyUp={earlyShiftUp}, events=[{string.Join(", ", heldModifierEvents)}])";
            return false;
        }

        KeymapStore chordKeymap = KeymapStore.LoadBundledDefault();
        chordKeymap.Mappings[0][storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "Ctrl+C" },
            Hold = null
        };

        TouchProcessorCore chordCore = TouchProcessorFactory.CreateDefault(chordKeymap);
        using DispatchEventQueue chordQueue = new();
        using TouchProcessorActor chordActor = new(chordCore, dispatchQueue: chordQueue);

        now = 0;
        InputFrame chordDown = MakeFrame(contactCount: 1, id0: 44, x0: keyX, y0: keyY);
        InputFrame chordUp = MakeFrame(contactCount: 0);
        chordActor.Post(TrackpadSide.Left, in chordDown, maxX, maxY, now);
        now += MsToTicks(20);
        chordActor.Post(TrackpadSide.Left, in chordUp, maxX, maxY, now);
        chordActor.WaitForIdle();

        bool sawChordModifierDown = false;
        bool sawChordKeyTap = false;
        bool sawChordModifierUp = false;
        while (chordQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown && dispatchEvent.VirtualKey == 0x11)
            {
                sawChordModifierDown = true;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyTap && dispatchEvent.VirtualKey == 0x43)
            {
                sawChordKeyTap = true;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.ModifierUp && dispatchEvent.VirtualKey == 0x11)
            {
                sawChordModifierUp = true;
            }
        }

        if (!sawChordModifierDown || !sawChordKeyTap || !sawChordModifierUp)
        {
            failure = "Ctrl+C chord dispatch sequence missing expected modifier/key events";
            return false;
        }

        // Chordal shift: 4 fingers on left should shift key taps on right.
        // Also validate stale-source timeout: if left side stops reporting, shift should clear.
        KeymapStore chordShiftKeymap = KeymapStore.LoadBundledDefault();
        string rightStorageKey = GridKeyPosition.StorageKey(TrackpadSide.Right, 0, 2);
        chordShiftKeymap.Mappings[0][rightStorageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "a" },
            Hold = null
        };

        KeyLayout rightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false);
        NormalizedRect rightKeyRect = rightLayout.Rects[0][2];
        ushort rightKeyX = (ushort)Math.Clamp((int)Math.Round((rightKeyRect.X + (rightKeyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort rightKeyY = (ushort)Math.Clamp((int)Math.Round((rightKeyRect.Y + (rightKeyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        TouchProcessorCore chordShiftCore = TouchProcessorFactory.CreateDefault(chordShiftKeymap);
        using DispatchEventQueue chordShiftQueue = new();
        using TouchProcessorActor chordShiftActor = new(chordShiftCore, dispatchQueue: chordShiftQueue);

        now = 0;
        InputFrame leftChordHold = MakeFrame(
            contactCount: 4,
            id0: 60, x0: 800, y0: 900,
            id1: 61, x1: 1200, y1: 1100,
            id2: 62, x2: 1600, y2: 1300,
            id3: 63, x3: 2000, y3: 1500);
        InputFrame rightKeyDown = MakeFrame(contactCount: 1, id0: 64, x0: rightKeyX, y0: rightKeyY);
        InputFrame rightKeyUp = MakeFrame(contactCount: 0);

        chordShiftActor.Post(TrackpadSide.Left, in leftChordHold, maxX, maxY, now);
        now += MsToTicks(10);
        chordShiftActor.Post(TrackpadSide.Right, in rightKeyDown, maxX, maxY, now);
        now += MsToTicks(10);
        chordShiftActor.Post(TrackpadSide.Right, in rightKeyUp, maxX, maxY, now);

        // No left-side frame here: emulate source side stalling without explicit release.
        // After timeout, chord-shift should clear.
        now += MsToTicks(320);
        InputFrame rightIdle = MakeFrame(contactCount: 0);
        chordShiftActor.Post(TrackpadSide.Right, in rightIdle, maxX, maxY, now);
        now += MsToTicks(10);
        chordShiftActor.Post(TrackpadSide.Right, in rightKeyUp, maxX, maxY, now);
        chordShiftActor.WaitForIdle();
        TouchProcessorSnapshot chordShiftSnapshot = chordShiftActor.Snapshot();

        bool sawShiftedTapDown = false;
        bool sawShiftedTapKey = false;
        bool sawShiftedTapUp = false;
        int shiftDownCount = 0;
        while (chordShiftQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (!sawShiftedTapDown &&
                dispatchEvent.Kind == DispatchEventKind.ModifierDown &&
                dispatchEvent.VirtualKey == 0x10)
            {
                sawShiftedTapDown = true;
                shiftDownCount++;
                continue;
            }
            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown &&
                dispatchEvent.VirtualKey == 0x10)
            {
                shiftDownCount++;
            }

            if (sawShiftedTapDown &&
                !sawShiftedTapKey &&
                dispatchEvent.Kind == DispatchEventKind.KeyTap &&
                dispatchEvent.VirtualKey == 0x41)
            {
                sawShiftedTapKey = true;
                continue;
            }

            if (sawShiftedTapDown &&
                sawShiftedTapKey &&
                dispatchEvent.Kind == DispatchEventKind.ModifierUp &&
                dispatchEvent.VirtualKey == 0x10)
            {
                sawShiftedTapUp = true;
                break;
            }
        }

        if (!sawShiftedTapDown || !sawShiftedTapKey || !sawShiftedTapUp)
        {
            failure = "chordal shift dispatch sequence missing expected Shift down/key tap/up events";
            return false;
        }

        if (shiftDownCount != 1)
        {
            failure = $"chordal shift stale-source timeout mismatch (shiftDown={shiftDownCount}, expected=1)";
            return false;
        }

        if (chordShiftSnapshot.ChordShiftRight)
        {
            failure = "chordal shift remained latched after source side stalled past timeout";
            return false;
        }

        // Chord-source side should not emit hold/tap actions while providing shift anchor.
        KeymapStore chordSourceSuppressKeymap = KeymapStore.LoadBundledDefault();
        chordSourceSuppressKeymap.Mappings[0][storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = "a" },
            Hold = new KeyAction { Label = "b" }
        };

        TouchProcessorCore chordSourceSuppressCore = TouchProcessorFactory.CreateDefault(chordSourceSuppressKeymap);
        using DispatchEventQueue chordSourceSuppressQueue = new();
        using TouchProcessorActor chordSourceSuppressActor = new(chordSourceSuppressCore, dispatchQueue: chordSourceSuppressQueue);

        now = 0;
        InputFrame leftChordSuppressDown = MakeFrame(
            contactCount: 4,
            id0: 70, x0: keyX, y0: keyY,
            id1: 71, x1: 1200, y1: 1100,
            id2: 72, x2: 1600, y2: 1300,
            id3: 73, x3: 2000, y3: 1500);
        InputFrame leftChordSuppressUp = MakeFrame(contactCount: 0);
        chordSourceSuppressActor.Post(TrackpadSide.Left, in leftChordSuppressDown, maxX, maxY, now);
        now += MsToTicks(220);
        chordSourceSuppressActor.Post(TrackpadSide.Left, in leftChordSuppressDown, maxX, maxY, now);
        now += MsToTicks(10);
        chordSourceSuppressActor.Post(TrackpadSide.Left, in leftChordSuppressUp, maxX, maxY, now);
        chordSourceSuppressActor.WaitForIdle();

        while (chordSourceSuppressQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Side == TrackpadSide.Left &&
                dispatchEvent.Kind is DispatchEventKind.KeyTap or DispatchEventKind.KeyDown)
            {
                failure = "chord-source side emitted key events while acting as shift anchor";
                return false;
            }
            if (dispatchEvent.Side == TrackpadSide.Left &&
                dispatchEvent.Kind == DispatchEventKind.ModifierDown &&
                dispatchEvent.VirtualKey != 0x10)
            {
                failure = "chord-source side emitted non-shift modifier while acting as shift anchor";
                return false;
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunTapGestureTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        NormalizedRect keyRect = leftLayout.Rects[0][2];
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        // Positive: two-finger single tap -> left click.
        if (!RunTapScenario(
            configure: core => { },
            act: actor =>
            {
                long now = 0;
                InputFrame down = MakeFrame(contactCount: 2, id0: 1, x0: 120, y0: 120, id1: 2, x1: 420, y1: 220);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
                now += MsToTicks(24);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 1,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        // Positive: two-finger double tap cadence -> two left clicks.
        if (!RunTapScenario(
            configure: core => { },
            act: actor =>
            {
                long now = 0;
                InputFrame downA = MakeFrame(contactCount: 2, id0: 3, x0: 130, y0: 130, id1: 4, x1: 460, y1: 240);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in downA, maxX, maxY, now);
                now += MsToTicks(18);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
                now += MsToTicks(120);
                InputFrame downB = MakeFrame(contactCount: 2, id0: 5, x0: 140, y0: 140, id1: 6, x1: 500, y1: 260);
                actor.Post(TrackpadSide.Left, in downB, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 2,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        // Positive: three-finger tap -> right click.
        if (!RunTapScenario(
            configure: core => { },
            act: actor =>
            {
                long now = 0;
                InputFrame down = MakeFrame(contactCount: 3, id0: 7, x0: 120, y0: 140, id1: 8, x1: 420, y1: 260, id2: 9, x2: 760, y2: 300);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
                now += MsToTicks(22);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 0,
            expectedRightClicks: 1,
            out failure))
        {
            return false;
        }

        // Negative: movement stress should reject false positives.
        if (!RunTapScenario(
            configure: core => { },
            act: actor =>
            {
                long now = 0;
                InputFrame down = MakeFrame(contactCount: 2, id0: 10, x0: 120, y0: 120, id1: 11, x1: 420, y1: 220);
                InputFrame moved = MakeFrame(contactCount: 2, id0: 10, x0: 120, y0: 120, id1: 11, x1: 3400, y1: 1900);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in moved, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 0,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        // Negative: drag-cancel motion should reject tap even if tap-move threshold is relaxed.
        if (!RunTapScenario(
            configure: core =>
            {
                core.Configure(core.CurrentConfig with
                {
                    DragCancelMm = 1.0,
                    TapMoveThresholdMm = 10.0
                });
            },
            act: actor =>
            {
                long now = 0;
                InputFrame down = MakeFrame(contactCount: 2, id0: 24, x0: 120, y0: 120, id1: 25, x1: 420, y1: 220);
                InputFrame moved = MakeFrame(contactCount: 2, id0: 24, x0: 220, y0: 120, id1: 25, x1: 520, y1: 220);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in moved, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 0,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        // Priority: three-finger tap should still win even when one touch is on a key.
        KeymapStore priorityKeymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore priorityCore = TouchProcessorFactory.CreateDefault(priorityKeymap);
        using DispatchEventQueue priorityQueue = new(capacity: 2048);
        using TouchProcessorActor priorityActor = new(priorityCore, dispatchQueue: priorityQueue);
        long priorityNow = 0;
        InputFrame priorityDown = MakeFrame(contactCount: 3, id0: 14, x0: keyX, y0: keyY, id1: 15, x1: 420, y1: 260, id2: 16, x2: 760, y2: 300);
        InputFrame priorityUp = MakeFrame(contactCount: 0);
        priorityActor.Post(TrackpadSide.Left, in priorityDown, maxX, maxY, priorityNow);
        priorityNow += MsToTicks(22);
        priorityActor.Post(TrackpadSide.Left, in priorityUp, maxX, maxY, priorityNow);
        priorityActor.WaitForIdle();

        int priorityRightClicks = 0;
        int priorityKeyTaps = 0;
        while (priorityQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.MouseButtonClick &&
                dispatchEvent.MouseButton == DispatchMouseButton.Right)
            {
                priorityRightClicks++;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                priorityKeyTaps++;
            }
        }

        if (priorityRightClicks != 1 || priorityKeyTaps != 0)
        {
            failure = $"three-finger tap priority mismatch (rightClicks={priorityRightClicks}, keyTaps={priorityKeyTaps}, expected=1/0)";
            return false;
        }

        // Suppression: keyboard-only mode disables tap-click.
        if (!RunTapScenario(
            configure: core =>
            {
                core.SetKeyboardModeEnabled(true);
                core.SetTypingEnabled(true);
            },
            act: actor =>
            {
                long now = 0;
                InputFrame down = MakeFrame(contactCount: 2, id0: 12, x0: 130, y0: 120, id1: 13, x1: 430, y1: 240);
                InputFrame up = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
            },
            expectedLeftClicks: 0,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        // Suppression: typing grace suppresses tap-click.
        if (!RunTapScenario(
            configure: core => { },
            act: actor =>
            {
                long now = 0;
                TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
                ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
                KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
                NormalizedRect keyRect = leftLayout.Rects[0][2];
                ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
                ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

                InputFrame keyDown = MakeFrame(contactCount: 1, id0: 21, x0: keyX, y0: keyY);
                InputFrame keyUp = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in keyDown, maxX, maxY, now);
                now += MsToTicks(50);
                actor.Post(TrackpadSide.Left, in keyUp, maxX, maxY, now);

                now += MsToTicks(30); // inside default typing grace window.
                InputFrame tapDown = MakeFrame(contactCount: 2, id0: 22, x0: 120, y0: 140, id1: 23, x1: 420, y1: 240);
                InputFrame tapUp = MakeFrame(contactCount: 0);
                actor.Post(TrackpadSide.Left, in tapDown, maxX, maxY, now);
                now += MsToTicks(20);
                actor.Post(TrackpadSide.Left, in tapUp, maxX, maxY, now);
            },
            expectedLeftClicks: 0,
            expectedRightClicks: 0,
            out failure))
        {
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunThreePlusGesturePriorityTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);

        // Any 3+ contact set should suppress normal key/custom dispatch.
        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore threeFingerCore = TouchProcessorFactory.CreateDefault(keymap);
        using DispatchEventQueue threeFingerQueue = new(capacity: 4096);
        using TouchProcessorActor threeFingerActor = new(threeFingerCore, dispatchQueue: threeFingerQueue);

        NormalizedRect key0 = leftLayout.Rects[0][2];
        NormalizedRect key1 = leftLayout.Rects[0][3];
        NormalizedRect key2 = leftLayout.Rects[1][2];
        ushort key0X = (ushort)Math.Clamp((int)Math.Round((key0.X + (key0.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort key0Y = (ushort)Math.Clamp((int)Math.Round((key0.Y + (key0.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort key1X = (ushort)Math.Clamp((int)Math.Round((key1.X + (key1.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort key1Y = (ushort)Math.Clamp((int)Math.Round((key1.Y + (key1.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort key2X = (ushort)Math.Clamp((int)Math.Round((key2.X + (key2.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort key2Y = (ushort)Math.Clamp((int)Math.Round((key2.Y + (key2.Height * 0.5)) * maxY), 1, maxY - 1);

        long now = 0;
        InputFrame threeDown = MakeFrame(contactCount: 3, id0: 101, x0: key0X, y0: key0Y, id1: 102, x1: key1X, y1: key1Y, id2: 103, x2: key2X, y2: key2Y);
        InputFrame allUp = MakeFrame(contactCount: 0);
        threeFingerActor.Post(TrackpadSide.Left, in threeDown, maxX, maxY, now);
        now += MsToTicks(140);
        threeFingerActor.Post(TrackpadSide.Left, in threeDown, maxX, maxY, now);
        now += MsToTicks(10);
        threeFingerActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        threeFingerActor.WaitForIdle();

        int threeFingerKeyTaps = 0;
        while (threeFingerQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                threeFingerKeyTaps++;
            }
        }

        if (threeFingerKeyTaps != 0)
        {
            failure = $"three-finger priority mismatch (keyTaps={threeFingerKeyTaps}, expected=0)";
            return false;
        }

        // Two-finger hold action should fire once after hold duration.
        TouchProcessorCore twoFingerHoldCore = TouchProcessorFactory.CreateDefault(keymap);
        twoFingerHoldCore.Configure(twoFingerHoldCore.CurrentConfig with
        {
            TwoFingerTapAction = "None",
            ThreeFingerTapAction = "None",
            TwoFingerHoldAction = "Left Click",
            HoldDurationMs = 120.0
        });
        using DispatchEventQueue twoFingerHoldQueue = new(capacity: 4096);
        using TouchProcessorActor twoFingerHoldActor = new(twoFingerHoldCore, dispatchQueue: twoFingerHoldQueue);

        now = 0;
        InputFrame twoDown = MakeFrame(contactCount: 2, id0: 121, x0: key0X, y0: key0Y, id1: 122, x1: key1X, y1: key1Y);
        InputFrame oneStillDown = MakeFrame(contactCount: 1, id0: 121, x0: key0X, y0: key0Y);
        twoFingerHoldActor.Post(TrackpadSide.Left, in twoDown, maxX, maxY, now);
        now += MsToTicks(140);
        twoFingerHoldActor.Post(TrackpadSide.Left, in twoDown, maxX, maxY, now);
        now += MsToTicks(10);
        twoFingerHoldActor.Post(TrackpadSide.Left, in oneStillDown, maxX, maxY, now);
        now += MsToTicks(10);
        twoFingerHoldActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        twoFingerHoldActor.WaitForIdle();

        int twoFingerHoldClicks = 0;
        int twoFingerHoldKeyTaps = 0;
        while (twoFingerHoldQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.MouseButtonClick)
            {
                twoFingerHoldClicks++;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                twoFingerHoldKeyTaps++;
            }
        }

        if (twoFingerHoldClicks != 1 || twoFingerHoldKeyTaps != 0)
        {
            failure = $"two-finger hold mismatch (clicks={twoFingerHoldClicks}, keyTaps={twoFingerHoldKeyTaps}, expected=1/0)";
            return false;
        }

        // Three-finger hold action should fire once after hold duration.
        TouchProcessorCore threeFingerHoldCore = TouchProcessorFactory.CreateDefault(keymap);
        threeFingerHoldCore.SetTypingEnabled(true);
        threeFingerHoldCore.Configure(threeFingerHoldCore.CurrentConfig with
        {
            TwoFingerTapAction = "None",
            ThreeFingerTapAction = "None",
            ThreeFingerHoldAction = "Typing Toggle",
            HoldDurationMs = 120.0
        });
        using DispatchEventQueue threeFingerHoldQueue = new(capacity: 4096);
        using TouchProcessorActor threeFingerHoldActor = new(threeFingerHoldCore, dispatchQueue: threeFingerHoldQueue);

        now = 0;
        InputFrame threeHoldDown = MakeFrame(contactCount: 3, id0: 131, x0: key0X, y0: key0Y, id1: 132, x1: key1X, y1: key1Y, id2: 133, x2: key2X, y2: key2Y);
        threeFingerHoldActor.Post(TrackpadSide.Left, in threeHoldDown, maxX, maxY, now);
        now += MsToTicks(140);
        threeFingerHoldActor.Post(TrackpadSide.Left, in threeHoldDown, maxX, maxY, now);
        now += MsToTicks(10);
        threeFingerHoldActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        threeFingerHoldActor.WaitForIdle();
        TouchProcessorSnapshot threeFingerHoldSnapshot = threeFingerHoldActor.Snapshot();

        int threeFingerHoldKeyTaps = 0;
        while (threeFingerHoldQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                threeFingerHoldKeyTaps++;
            }
        }

        if (threeFingerHoldSnapshot.TypingEnabled || threeFingerHoldKeyTaps != 0)
        {
            failure = $"three-finger hold mismatch (typingEnabled={threeFingerHoldSnapshot.TypingEnabled}, keyTaps={threeFingerHoldKeyTaps}, expected=false/0)";
            return false;
        }

        // Four-finger hold action should fire, and key hits under those fingers should stay suppressed.
        TouchProcessorCore fourFingerCore = TouchProcessorFactory.CreateDefault(keymap);
        fourFingerCore.SetTypingEnabled(true);
        fourFingerCore.Configure(fourFingerCore.CurrentConfig with
        {
            FourFingerHoldAction = "Typing Toggle",
            HoldDurationMs = 120.0
        });
        using DispatchEventQueue fourFingerQueue = new(capacity: 4096);
        using TouchProcessorActor fourFingerActor = new(fourFingerCore, dispatchQueue: fourFingerQueue);

        NormalizedRect key3 = leftLayout.Rects[1][3];
        ushort key3X = (ushort)Math.Clamp((int)Math.Round((key3.X + (key3.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort key3Y = (ushort)Math.Clamp((int)Math.Round((key3.Y + (key3.Height * 0.5)) * maxY), 1, maxY - 1);

        now = 0;
        InputFrame fourDown = MakeFrame(contactCount: 4, id0: 111, x0: key0X, y0: key0Y, id1: 112, x1: key1X, y1: key1Y, id2: 113, x2: key2X, y2: key2Y, id3: 114, x3: key3X, y3: key3Y);
        fourFingerActor.Post(TrackpadSide.Left, in fourDown, maxX, maxY, now);
        now += MsToTicks(140);
        fourFingerActor.Post(TrackpadSide.Left, in fourDown, maxX, maxY, now);
        now += MsToTicks(10);
        fourFingerActor.Post(TrackpadSide.Left, in allUp, maxX, maxY, now);
        fourFingerActor.WaitForIdle();
        TouchProcessorSnapshot fourFingerSnapshot = fourFingerActor.Snapshot();

        int fourFingerKeyTaps = 0;
        while (fourFingerQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.KeyTap)
            {
                fourFingerKeyTaps++;
            }
        }

        if (fourFingerSnapshot.TypingEnabled || fourFingerKeyTaps != 0)
        {
            failure = $"four-finger hold priority mismatch (typingEnabled={fourFingerSnapshot.TypingEnabled}, keyTaps={fourFingerKeyTaps}, expected=false/0)";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunCornerHoldGestureTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout leftLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: true);
        if (!TryFindOuterCornerOffKeyPair(leftLayout, out double topXNorm, out double topYNorm, out double bottomXNorm, out double bottomYNorm))
        {
            failure = "failed to find off-key outer-corner pair points";
            return false;
        }

        ushort topX = (ushort)Math.Clamp((int)Math.Round(topXNorm * maxX), 1, maxX - 1);
        ushort topY = (ushort)Math.Clamp((int)Math.Round(topYNorm * maxY), 1, maxY - 1);
        ushort bottomX = (ushort)Math.Clamp((int)Math.Round(bottomXNorm * maxX), 1, maxX - 1);
        ushort bottomY = (ushort)Math.Clamp((int)Math.Round(bottomYNorm * maxY), 1, maxY - 1);

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        core.Configure(core.CurrentConfig with
        {
            OuterCornersAction = "A",
            HoldDurationMs = 120.0,
            SnapRadiusPercent = 0.0,
            DragCancelMm = 1000.0
        });

        using DispatchEventQueue queue = new(capacity: 2048);
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        long now = 0;
        InputFrame down = MakeFrame(contactCount: 2, id0: 90, x0: topX, y0: topY, id1: 91, x1: bottomX, y1: bottomY);
        InputFrame up = MakeFrame(contactCount: 0);

        // Below hold duration: should not emit.
        actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
        now += MsToTicks(70);
        actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
        now += MsToTicks(10);
        actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);

        // Above hold duration: should emit configured corner action once.
        now += MsToTicks(60);
        actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
        now += MsToTicks(135);
        actor.Post(TrackpadSide.Left, in down, maxX, maxY, now);
        now += MsToTicks(10);
        actor.Post(TrackpadSide.Left, in up, maxX, maxY, now);
        actor.WaitForIdle();

        int cornerATaps = 0;
        int otherKeyTaps = 0;
        int cornerMouseClicks = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind == DispatchEventKind.MouseButtonClick)
            {
                cornerMouseClicks++;
                continue;
            }

            if (dispatchEvent.Kind != DispatchEventKind.KeyTap)
            {
                continue;
            }

            if (dispatchEvent.VirtualKey == 0x41)
            {
                cornerATaps++;
            }
            else
            {
                otherKeyTaps++;
            }
        }

        if (cornerATaps != 1 || otherKeyTaps != 0 || cornerMouseClicks != 0)
        {
            failure = $"corner hold dispatch mismatch (A={cornerATaps}, otherKeyTaps={otherKeyTaps}, mouseClicks={cornerMouseClicks}, expected=1/0/0)";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunFiveFingerSwipeTests(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);

        core.SetTypingEnabled(true);
        core.ResetState();

        long now = 0;
        InputFrame startFive = MakeFrame(
            contactCount: 5,
            id0: 80, x0: 900, y0: 1500,
            id1: 81, x1: 1200, y1: 1550,
            id2: 82, x2: 1500, y2: 1600,
            id3: 83, x3: 1800, y3: 1650,
            id4: 84, x4: 2100, y4: 1700);

        // Real-world swipe jitter: one finger can briefly disappear.
        InputFrame jitterFour = MakeFrame(
            contactCount: 4,
            id0: 80, x0: 980, y0: 1500,
            id1: 81, x1: 1280, y1: 1550,
            id2: 82, x2: 1580, y2: 1600,
            id3: 83, x3: 1880, y3: 1650);

        InputFrame swipeFive = MakeFrame(
            contactCount: 5,
            id0: 80, x0: 3200, y0: 1500,
            id1: 81, x1: 3500, y1: 1550,
            id2: 82, x2: 3800, y2: 1600,
            id3: 83, x3: 4100, y3: 1650,
            id4: 84, x4: 4400, y4: 1700);

        InputFrame allUp = MakeFrame(contactCount: 0);

        core.ProcessFrame(TrackpadSide.Left, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        core.ProcessFrame(TrackpadSide.Left, in jitterFour, maxX, maxY, now);
        now += MsToTicks(12);
        core.ProcessFrame(TrackpadSide.Left, in swipeFive, maxX, maxY, now);

        if (core.Snapshot().TypingEnabled)
        {
            failure = "typing toggle did not switch off after five-finger swipe with 5->4 jitter";
            return false;
        }

        now += MsToTicks(16);
        core.ProcessFrame(TrackpadSide.Left, in allUp, maxX, maxY, now);

        now += MsToTicks(20);
        core.ProcessFrame(TrackpadSide.Left, in startFive, maxX, maxY, now);
        now += MsToTicks(12);
        core.ProcessFrame(TrackpadSide.Left, in swipeFive, maxX, maxY, now);

        if (!core.Snapshot().TypingEnabled)
        {
            failure = "typing toggle did not switch back on after second five-finger swipe";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool RunTapScenario(
        Action<TouchProcessorCore> configure,
        Action<TouchProcessorActor> act,
        int expectedLeftClicks,
        int expectedRightClicks,
        out string failure)
    {
        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap);
        configure(core);

        using DispatchEventQueue queue = new(capacity: 8192);
        using TouchProcessorActor actor = new(core, dispatchQueue: queue);

        act(actor);
        actor.WaitForIdle();

        int leftClicks = 0;
        int rightClicks = 0;
        while (queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            if (dispatchEvent.Kind != DispatchEventKind.MouseButtonClick)
            {
                continue;
            }

            if (dispatchEvent.MouseButton == DispatchMouseButton.Left)
            {
                leftClicks++;
            }
            else if (dispatchEvent.MouseButton == DispatchMouseButton.Right)
            {
                rightClicks++;
            }
        }

        if (leftClicks != expectedLeftClicks || rightClicks != expectedRightClicks)
        {
            failure = $"tap scenario mismatch (left={leftClicks}/{expectedLeftClicks}, right={rightClicks}/{expectedRightClicks})";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ContainsMode(ReadOnlySpan<IntentTransition> transitions, IntentMode mode)
    {
        for (int i = 0; i < transitions.Length; i++)
        {
            if (transitions[i].Current == mode)
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsInsideAnyKeyRect(KeyLayout layout, double xNorm, double yNorm)
    {
        for (int row = 0; row < layout.Rects.Length; row++)
        {
            NormalizedRect[] rowRects = layout.Rects[row];
            for (int col = 0; col < rowRects.Length; col++)
            {
                if (rowRects[col].Contains(xNorm, yNorm))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool TryFindOuterCornerOffKeyPair(
        KeyLayout layout,
        out double topXNorm,
        out double topYNorm,
        out double bottomXNorm,
        out double bottomYNorm)
    {
        const double cornerThreshold = 0.16;
        topXNorm = 0;
        topYNorm = 0;
        bottomXNorm = 0;
        bottomYNorm = 0;

        for (double y = 0.01; y <= (cornerThreshold - 0.005); y += 0.005)
        {
            for (double x = 0.01; x <= (cornerThreshold - 0.005); x += 0.005)
            {
                if (!IsInsideAnyKeyRect(layout, x, y))
                {
                    topXNorm = x;
                    topYNorm = y;
                    break;
                }
            }

            if (topXNorm > 0)
            {
                break;
            }
        }

        for (double y = (1.0 - cornerThreshold + 0.005); y <= 0.99; y += 0.005)
        {
            for (double x = 0.01; x <= (cornerThreshold - 0.005); x += 0.005)
            {
                if (!IsInsideAnyKeyRect(layout, x, y))
                {
                    bottomXNorm = x;
                    bottomYNorm = y;
                    break;
                }
            }

            if (bottomXNorm > 0)
            {
                break;
            }
        }

        return topXNorm > 0 && bottomXNorm > 0;
    }

    private static (int Row, int Col, double DistSq) FindNearestKeyCenter(KeyLayout layout, double xNorm, double yNorm)
    {
        int bestRow = -1;
        int bestCol = -1;
        double bestDistSq = double.MaxValue;
        for (int row = 0; row < layout.Rects.Length; row++)
        {
            NormalizedRect[] rowRects = layout.Rects[row];
            for (int col = 0; col < rowRects.Length; col++)
            {
                NormalizedRect rect = rowRects[col];
                double centerX = rect.X + (rect.Width * 0.5);
                double centerY = rect.Y + (rect.Height * 0.5);
                double dx = centerX - xNorm;
                double dy = centerY - yNorm;
                double distSq = (dx * dx) + (dy * dy);
                if (distSq < bestDistSq)
                {
                    bestDistSq = distSq;
                    bestRow = row;
                    bestCol = col;
                }
            }
        }

        return (bestRow, bestCol, bestDistSq);
    }

    private static InputFrame MakeFrame(
        byte contactCount,
        uint id0 = 0,
        ushort x0 = 0,
        ushort y0 = 0,
        uint id1 = 0,
        ushort x1 = 0,
        ushort y1 = 0,
        uint id2 = 0,
        ushort x2 = 0,
        ushort y2 = 0,
        uint id3 = 0,
        ushort x3 = 0,
        ushort y3 = 0,
        uint id4 = 0,
        ushort x4 = 0,
        ushort y4 = 0)
    {
        InputFrame frame = new()
        {
            ReportId = RawInputInterop.ReportIdMultitouch,
            ContactCount = contactCount,
            ScanTime = 0,
            IsButtonClicked = 0
        };

        if (contactCount > 0)
        {
            frame.SetContact(0, new ContactFrame(id0, x0, y0, 0x03));
        }

        if (contactCount > 1)
        {
            frame.SetContact(1, new ContactFrame(id1, x1, y1, 0x03));
        }

        if (contactCount > 2)
        {
            frame.SetContact(2, new ContactFrame(id2, x2, y2, 0x03));
        }

        if (contactCount > 3)
        {
            frame.SetContact(3, new ContactFrame(id3, x3, y3, 0x03));
        }

        if (contactCount > 4)
        {
            frame.SetContact(4, new ContactFrame(id4, x4, y4, 0x03));
        }

        return frame;
    }

    private static long MsToTicks(double milliseconds)
    {
        return (long)Math.Round(milliseconds * System.Diagnostics.Stopwatch.Frequency / 1000.0);
    }

    private static void WriteContact(Span<byte> reportBytes, int index, byte flags, uint contactId, ushort x, ushort y)
    {
        int offset = 1 + (index * 9);
        reportBytes[offset] = flags;
        WriteUInt32(reportBytes.Slice(offset + 1, 4), contactId);
        WriteUInt16(reportBytes.Slice(offset + 5, 2), x);
        WriteUInt16(reportBytes.Slice(offset + 7, 2), y);
    }

    private static void WriteUInt16(Span<byte> target, ushort value)
    {
        target[0] = (byte)(value & 0xFF);
        target[1] = (byte)((value >> 8) & 0xFF);
    }

    private static void WriteUInt32(Span<byte> target, uint value)
    {
        target[0] = (byte)(value & 0xFF);
        target[1] = (byte)((value >> 8) & 0xFF);
        target[2] = (byte)((value >> 16) & 0xFF);
        target[3] = (byte)((value >> 24) & 0xFF);
    }
}

internal readonly record struct SelfTestResult(bool Success, string Summary);

