using Microsoft.Win32.SafeHandles;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace GlassToKey;

internal static class HidResearchTool
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint HidpStatusSuccess = 0x00110000;
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const int ErrorNoMoreItems = 259;
    private static readonly IntPtr InvalidDeviceInfoSet = new(-1);

    public static int Run(ReaderOptions options)
    {
        List<CandidateHidInterface> devices = EnumerateCandidateInterfaces();
        if (devices.Count == 0)
        {
            Console.Error.WriteLine("No trackpads detected.");
            return 20;
        }

        Console.WriteLine("Detected trackpad interfaces:");
        for (int i = 0; i < devices.Count; i++)
        {
            CandidateHidInterface device = devices[i];
            string access = DescribeOpenability(device.Path);
            Console.WriteLine($"[{i}] {device.DisplayName} [{access}] :: {device.Path}");
        }

        if (options.HidDeviceIndex >= devices.Count)
        {
            Console.Error.WriteLine($"--hid-index {options.HidDeviceIndex} is out of range (0..{devices.Count - 1}).");
            return 21;
        }

        int selectedIndex = options.HidDeviceIndex;
        if (!options.HidIndexSpecified)
        {
            int actuatorIndex = FindPreferredActuatorIndex(devices, options.RequiresHidWriteAccess);
            int autoIndex = actuatorIndex >= 0 ? actuatorIndex : FindFirstOpenableIndex(devices, options.RequiresHidWriteAccess);
            if (autoIndex >= 0)
            {
                selectedIndex = autoIndex;
            }
        }

        CandidateHidInterface target = devices[selectedIndex];
        if (string.IsNullOrWhiteSpace(target.Path))
        {
            Console.Error.WriteLine("Selected device path is empty.");
            return 22;
        }

        Console.WriteLine();
        Console.WriteLine($"Using index {selectedIndex}: {target.DisplayName}");

        bool requireWriteAccess = options.RequiresHidWriteAccess;
        if (!TryOpenDevice(target.Path, requireWriteAccess, out SafeFileHandle? handle, out string? openError))
        {
            Console.Error.WriteLine(openError);
            return 23;
        }
        if (handle == null)
        {
            Console.Error.WriteLine("CreateFile returned a null handle.");
            return 23;
        }

        using (handle)
        {
            if (!TryReadProbe(handle, out HidProbeResult probe, out string? probeError))
            {
                Console.Error.WriteLine(probeError ?? "Failed to read HID capabilities.");
                return 24;
            }

            PrintProbe(target.Path, probe);

            bool hasCommandPayload =
                !string.IsNullOrWhiteSpace(options.HidFeaturePayloadHex) ||
                !string.IsNullOrWhiteSpace(options.HidOutputPayloadHex) ||
                !string.IsNullOrWhiteSpace(options.HidWritePayloadHex);
            if (!hasCommandPayload && !options.HidAutoProbe && !options.HidActuatorPulse && !options.HidActuatorVibrate)
            {
                return 0;
            }

            byte[]? featurePayload;
            byte[]? outputPayload;
            byte[]? writePayload;
            string? featureError = null;
            string? outputError = null;
            string? writeError = null;
            if (!TryParsePayload(options.HidFeaturePayloadHex, "--hid-feature", out featurePayload, out featureError) ||
                !TryParsePayload(options.HidOutputPayloadHex, "--hid-output", out outputPayload, out outputError) ||
                !TryParsePayload(options.HidWritePayloadHex, "--hid-write", out writePayload, out writeError))
            {
                string message = featureError ?? outputError ?? writeError ?? "Invalid payload.";
                Console.Error.WriteLine(message);
                return 25;
            }

            for (int i = 0; i < options.HidRepeat; i++)
            {
                int frame = i + 1;
                if (featurePayload != null && !SendFeature(handle, featurePayload, frame))
                {
                    return 26;
                }
                if (outputPayload != null && !SendOutput(handle, outputPayload, frame))
                {
                    return 27;
                }
                if (writePayload != null && !SendWrite(handle, writePayload, frame))
                {
                    return 28;
                }

                if (options.HidIntervalMs > 0 && frame < options.HidRepeat)
                {
                    Thread.Sleep(options.HidIntervalMs);
                }
            }

            if (options.HidAutoProbe)
            {
                if (!RunAutoProbe(handle, probe, target.Path, options))
                {
                    return 29;
                }
            }

            if (options.HidActuatorPulse)
            {
                if (!RunActuatorPulse(handle, probe, options))
                {
                    return 30;
                }
            }

            if (options.HidActuatorVibrate)
            {
                if (!RunActuatorVibrate(handle, probe, options))
                {
                    return 31;
                }
            }
        }

        return 0;
    }

    private static int FindFirstOpenableIndex(List<CandidateHidInterface> devices, bool requireWriteAccess)
    {
        for (int i = 0; i < devices.Count; i++)
        {
            CandidateHidInterface device = devices[i];
            if (!TryOpenDevice(device.Path, requireWriteAccess, out SafeFileHandle? handle, out _))
            {
                continue;
            }

            handle?.Dispose();
            return i;
        }

        return -1;
    }

    private static int FindPreferredActuatorIndex(List<CandidateHidInterface> devices, bool requireWriteAccess)
    {
        for (int i = 0; i < devices.Count; i++)
        {
            CandidateHidInterface device = devices[i];
            if (!TryOpenDevice(device.Path, requireWriteAccess, out SafeFileHandle? handle, out _))
            {
                continue;
            }

            if (handle == null)
            {
                continue;
            }

            using (handle)
            {
                if (!TryReadProbe(handle, out HidProbeResult probe, out _))
                {
                    continue;
                }

                bool actuatorByName = !string.IsNullOrWhiteSpace(probe.Product) &&
                                      probe.Product.Contains("Actuator", StringComparison.OrdinalIgnoreCase);
                bool actuatorByUsage = probe.UsagePage == 0xFF00 && probe.OutputReportBytes > 0;
                if (actuatorByName || actuatorByUsage)
                {
                    return i;
                }
            }
        }

        return -1;
    }

    private static List<CandidateHidInterface> EnumerateCandidateInterfaces()
    {
        Dictionary<string, CandidateHidInterface> result = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in EnumerateSetupDiHidPaths())
        {
            if (!RawInputInterop.TryParseVidPid(path, out uint vid, out uint pid) || !RawInputInterop.IsTargetVidPid(vid, pid))
            {
                continue;
            }

            result[path] = new CandidateHidInterface(path, BuildDisplayName(path, vid, pid));
        }

        HidDeviceInfo[] rawInputDevices = RawInputInterop.EnumerateTrackpads();
        for (int i = 0; i < rawInputDevices.Length; i++)
        {
            HidDeviceInfo device = rawInputDevices[i];
            if (string.IsNullOrWhiteSpace(device.Path))
            {
                continue;
            }

            if (!result.ContainsKey(device.Path))
            {
                result[device.Path] = new CandidateHidInterface(device.Path, $"{device.DisplayName} (RawInput)");
            }
        }

        List<CandidateHidInterface> output = new(result.Values);
        output.Sort(static (a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
        return output;
    }

    private static IEnumerable<string> EnumerateSetupDiHidPaths()
    {
        HidD_GetHidGuid(out Guid hidGuid);
        IntPtr deviceInfoSet = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (deviceInfoSet == IntPtr.Zero || deviceInfoSet == InvalidDeviceInfoSet)
        {
            yield break;
        }

        try
        {
            uint index = 0;
            while (true)
            {
                SpDeviceInterfaceData interfaceData = new()
                {
                    cbSize = Marshal.SizeOf<SpDeviceInterfaceData>()
                };

                bool ok = SetupDiEnumDeviceInterfaces(deviceInfoSet, IntPtr.Zero, ref hidGuid, index, ref interfaceData);
                if (!ok)
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == ErrorNoMoreItems)
                    {
                        break;
                    }

                    break;
                }

                if (TryGetDevicePath(deviceInfoSet, interfaceData, out string? path) && !string.IsNullOrWhiteSpace(path))
                {
                    yield return path;
                }

                index++;
            }
        }
        finally
        {
            _ = SetupDiDestroyDeviceInfoList(deviceInfoSet);
        }
    }

    private static bool TryGetDevicePath(IntPtr deviceInfoSet, SpDeviceInterfaceData interfaceData, out string? path)
    {
        path = null;

        _ = SetupDiGetDeviceInterfaceDetail(deviceInfoSet, ref interfaceData, IntPtr.Zero, 0, out uint requiredSize, IntPtr.Zero);
        if (requiredSize == 0)
        {
            return false;
        }

        IntPtr detailDataBuffer = Marshal.AllocHGlobal((int)requiredSize);
        try
        {
            int cbSize = IntPtr.Size == 8 ? 8 : 6;
            Marshal.WriteInt32(detailDataBuffer, cbSize);

            bool ok = SetupDiGetDeviceInterfaceDetail(
                deviceInfoSet,
                ref interfaceData,
                detailDataBuffer,
                requiredSize,
                out _,
                IntPtr.Zero);
            if (!ok)
            {
                return false;
            }

            IntPtr pDevicePathName = IntPtr.Add(detailDataBuffer, 4);
            path = Marshal.PtrToStringUni(pDevicePathName);
            return !string.IsNullOrWhiteSpace(path);
        }
        finally
        {
            Marshal.FreeHGlobal(detailDataBuffer);
        }
    }

    private static string BuildDisplayName(string path, uint vid, uint pid)
    {
        string upper = path.ToUpperInvariant();
        string collection = "COL??";
        int colIndex = upper.IndexOf("COL", StringComparison.Ordinal);
        if (colIndex >= 0 && colIndex + 5 <= upper.Length)
        {
            collection = upper.Substring(colIndex, 5);
        }

        return $"Magic Trackpad 2 [{vid:X4}:{pid:X4} {collection}]";
    }

    private static bool TryOpenDevice(string path, bool requireWriteAccess, out SafeFileHandle? handle, out string? error)
    {
        uint desiredAccess = GenericRead | (requireWriteAccess ? GenericWrite : 0);
        handle = CreateFile(path, desiredAccess, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!handle.IsInvalid)
        {
            error = null;
            return true;
        }

        int lastError = Marshal.GetLastWin32Error();
        handle.Dispose();

        if (requireWriteAccess)
        {
            error = $"CreateFile failed for device path '{path}' with read/write access (Win32=0x{lastError:X}).";
            handle = null;
            return false;
        }

        handle = CreateFile(path, GenericRead, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!handle.IsInvalid)
        {
            error = null;
            return true;
        }

        int readOnlyError = Marshal.GetLastWin32Error();
        handle.Dispose();
        handle = null;
        error = $"CreateFile failed for device path '{path}' (read/write Win32=0x{lastError:X}, read Win32=0x{readOnlyError:X}).";
        return false;
    }

    private static string DescribeOpenability(string path)
    {
        SafeFileHandle rw = CreateFile(path, GenericRead | GenericWrite, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!rw.IsInvalid)
        {
            rw.Dispose();
            return "rw";
        }

        int rwError = Marshal.GetLastWin32Error();
        rw.Dispose();

        SafeFileHandle r = CreateFile(path, GenericRead, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!r.IsInvalid)
        {
            r.Dispose();
            return $"r (rw 0x{rwError:X})";
        }

        int rError = Marshal.GetLastWin32Error();
        r.Dispose();
        return $"locked (rw 0x{rwError:X}, r 0x{rError:X})";
    }

    private static bool TryReadProbe(SafeFileHandle handle, out HidProbeResult probe, out string? error)
    {
        probe = default;

        HiddAttributes attributes = new() { Size = Marshal.SizeOf<HiddAttributes>() };
        if (!HidD_GetAttributes(handle, ref attributes))
        {
            error = $"HidD_GetAttributes failed (Win32=0x{Marshal.GetLastWin32Error():X}).";
            return false;
        }

        IntPtr preparsedData = IntPtr.Zero;
        if (!HidD_GetPreparsedData(handle, out preparsedData) || preparsedData == IntPtr.Zero)
        {
            error = $"HidD_GetPreparsedData failed (Win32=0x{Marshal.GetLastWin32Error():X}).";
            return false;
        }

        try
        {
            uint capsStatus = (uint)HidP_GetCaps(preparsedData, out HidpCaps caps);
            if (capsStatus != HidpStatusSuccess)
            {
                error = $"HidP_GetCaps failed (NTSTATUS=0x{capsStatus:X8}).";
                return false;
            }

            probe = new HidProbeResult(
                attributes.VendorID,
                attributes.ProductID,
                attributes.VersionNumber,
                caps.UsagePage,
                caps.Usage,
                caps.InputReportByteLength,
                caps.OutputReportByteLength,
                caps.FeatureReportByteLength,
                GetUnicodeHidString(handle, HidD_GetManufacturerString),
                GetUnicodeHidString(handle, HidD_GetProductString),
                GetUnicodeHidString(handle, HidD_GetSerialNumberString));
            error = null;
            return true;
        }
        finally
        {
            _ = HidD_FreePreparsedData(preparsedData);
        }
    }

    private static void PrintProbe(string path, in HidProbeResult probe)
    {
        Console.WriteLine();
        Console.WriteLine($"Selected HID path: {path}");
        Console.WriteLine($"VID:PID {probe.VendorId:X4}:{probe.ProductId:X4} (version 0x{probe.VersionNumber:X4})");
        Console.WriteLine($"UsagePage/Usage: 0x{probe.UsagePage:X4}/0x{probe.Usage:X4}");
        Console.WriteLine($"Report lengths: input={probe.InputReportBytes} output={probe.OutputReportBytes} feature={probe.FeatureReportBytes}");
        if (!string.IsNullOrWhiteSpace(probe.Manufacturer))
        {
            Console.WriteLine($"Manufacturer: {probe.Manufacturer}");
        }
        if (!string.IsNullOrWhiteSpace(probe.Product))
        {
            Console.WriteLine($"Product: {probe.Product}");
        }
        if (!string.IsNullOrWhiteSpace(probe.SerialNumber))
        {
            Console.WriteLine($"Serial: {probe.SerialNumber}");
        }
    }

    private static bool SendFeature(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = HidD_SetFeature(handle, payload, payload.Length);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] HidD_SetFeature failed (Win32=0x{Marshal.GetLastWin32Error():X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] HidD_SetFeature OK payload={FormatHex(payload)}");
        return true;
    }

    private static bool SendOutput(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = TrySetOutputReport(handle, payload, out int win32Error);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] HidD_SetOutputReport failed (Win32=0x{win32Error:X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] HidD_SetOutputReport OK payload={FormatHex(payload)}");
        return true;
    }

    private static bool SendWrite(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = TryWriteReport(handle, payload, out int win32Error, out uint written);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] WriteFile failed (Win32=0x{win32Error:X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] WriteFile OK bytes={written}/{payload.Length} payload={FormatHex(payload)}");
        return written == payload.Length;
    }

    private static bool RunAutoProbe(SafeFileHandle handle, in HidProbeResult probe, string path, ReaderOptions options)
    {
        if (probe.OutputReportBytes == 0)
        {
            Console.Error.WriteLine("Auto probe requires an interface with OutputReportByteLength > 0. Select actuator interface with --hid-index.");
            return false;
        }

        ProbeLog log = new();
        log.Info($"timestamp_utc={DateTime.UtcNow:O}");
        log.Info($"path={path}");
        log.Info($"vidpid={probe.VendorId:X4}:{probe.ProductId:X4}");
        log.Info($"usage={probe.UsagePage:X4}/{probe.Usage:X4}");
        log.Info($"product={probe.Product ?? "<null>"}");
        log.Info($"output_len={probe.OutputReportBytes}");
        int alternateLength = probe.OutputReportBytes + 1;
        log.Info($"tested_lengths={probe.OutputReportBytes},{alternateLength}");
        log.Info($"scan_report_id_range=0x00..0x{options.HidAutoReportMax:X2}");
        log.Info($"interval_ms={options.HidAutoIntervalMs}");

        int totalAttempts = 0;
        int outputSuccess = 0;
        int writeSuccess = 0;
        HashSet<int> successfulReportIds = new();

        for (int reportId = 0; reportId <= options.HidAutoReportMax; reportId++)
        {
            int[] lengths = { 14, probe.OutputReportBytes, alternateLength };
            foreach (int length in lengths)
            {
                if (length <= 0 || length > 512)
                {
                    continue;
                }

                byte[] zeros = BuildAutoPayload(length, (byte)reportId, secondByte: null);
                byte[] marker = BuildAutoPayload(length, (byte)reportId, secondByte: 0x01);

                ProbeAttemptResult outputZeros = ProbeOutputAttempt(handle, reportId, "zeros", zeros);
                ProbeAttemptResult writeZeros = ProbeWriteAttempt(handle, reportId, "zeros", zeros);
                ProbeAttemptResult outputMarker = ProbeOutputAttempt(handle, reportId, "marker01", marker);
                ProbeAttemptResult writeMarker = ProbeWriteAttempt(handle, reportId, "marker01", marker);

                totalAttempts += 4;
                if (outputZeros.Ok) outputSuccess++;
                if (writeZeros.Ok) writeSuccess++;
                if (outputMarker.Ok) outputSuccess++;
                if (writeMarker.Ok) writeSuccess++;
                if (outputZeros.Ok || writeZeros.Ok || outputMarker.Ok || writeMarker.Ok)
                {
                    _ = successfulReportIds.Add(reportId);
                }

                log.Info(outputZeros.ToLogLine());
                log.Info(writeZeros.ToLogLine());
                log.Info(outputMarker.ToLogLine());
                log.Info(writeMarker.ToLogLine());
            }

            if (options.HidAutoIntervalMs > 0)
            {
                Thread.Sleep(options.HidAutoIntervalMs);
            }
        }

        if (successfulReportIds.Count > 0)
        {
            List<int> hitList = new(successfulReportIds);
            hitList.Sort();
            log.Info($"phase2_focus report_ids={FormatReportIdList(hitList)}");
            for (int i = 0; i < hitList.Count; i++)
            {
                int reportId = hitList[i];
                RunFocusedTemplateProbe(
                    handle,
                    probe,
                    reportId,
                    log,
                    ref totalAttempts,
                    ref outputSuccess,
                    ref writeSuccess);
            }
        }
        else
        {
            log.Info("phase2_focus report_ids=<none>");
        }

        log.Info($"summary attempts={totalAttempts} output_ok={outputSuccess} write_ok={writeSuccess}");
        string logPath = ResolveAutoProbeLogPath(options.HidAutoLogPath);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            File.WriteAllLines(logPath, log.Lines);
            Console.WriteLine($"Auto probe log written: {logPath}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to write auto probe log '{logPath}': {ex.Message}");
        }

        return true;
    }

    private static void RunFocusedTemplateProbe(
        SafeFileHandle handle,
        in HidProbeResult probe,
        int reportId,
        ProbeLog log,
        ref int totalAttempts,
        ref int outputSuccess,
        ref int writeSuccess)
    {
        log.Info($"phase2_begin rid=0x{reportId:X2}");
        List<NamedPayload> templates = BuildKnownActuatorTemplates(reportId, probe.OutputReportBytes);
        for (int i = 0; i < templates.Count; i++)
        {
            NamedPayload template = templates[i];
            string variant = $"tpl:{template.Name}";
            ProbeAttemptResult outAttempt = ProbeOutputAttempt(handle, reportId, variant, template.Payload);
            ProbeAttemptResult wrAttempt = ProbeWriteAttempt(handle, reportId, variant, template.Payload);

            totalAttempts += 2;
            if (outAttempt.Ok) outputSuccess++;
            if (wrAttempt.Ok) writeSuccess++;

            log.Info(outAttempt.ToLogLine());
            log.Info(wrAttempt.ToLogLine());

            if (probe.InputReportBytes > 0)
            {
                InputReportSnapshot snap = TryReadInputReport(handle, probe.InputReportBytes, (byte)reportId);
                log.Info(snap.ToLogLine(reportId, variant));
            }
        }

        log.Info($"phase2_end rid=0x{reportId:X2} templates={templates.Count}");
    }

    private static List<NamedPayload> BuildKnownActuatorTemplates(int reportId, int outputReportBytes)
    {
        List<NamedPayload> templates = new();

        byte[] exact14 = BuildBytes(
            (byte)reportId, 0x01, 0x15, 0x6C, 0x02, 0x00,
            0x21, 0x2B, 0x06, 0x01, 0x00, 0x16, 0x41, 0x13);
        templates.Add(new NamedPayload("imbushuo14", exact14));
        templates.Add(new NamedPayload("imbushuo14_padOut", PadPayload(exact14, outputReportBytes)));

        byte[] zeros14 = BuildAutoPayload(14, (byte)reportId, secondByte: 0x00);
        templates.Add(new NamedPayload("zeros14_cmd0", zeros14));
        templates.Add(new NamedPayload("zeros14_cmd1", BuildAutoPayload(14, (byte)reportId, secondByte: 0x01)));

        byte[] baseStrength = BuildBytes(
            (byte)reportId, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x21, 0x2B, 0x06, 0x01, 0x00, 0x16, 0x41, 0x13);
        templates.Add(new NamedPayload("base14_strength0", baseStrength));
        templates.Add(new NamedPayload("base14_strength0_padOut", PadPayload(baseStrength, outputReportBytes)));

        // Archived: old scanning candidates. Kept minimal now that production uses a strength slider.
        uint[] strengthCandidates = { 0x00026C00u | 0x15u };
        for (int i = 0; i < strengthCandidates.Length; i++)
        {
            uint strength = strengthCandidates[i];
            byte[] candidate = (byte[])baseStrength.Clone();
            candidate[2] = (byte)(strength & 0xFF);
            candidate[3] = (byte)((strength >> 8) & 0xFF);
            candidate[4] = (byte)((strength >> 16) & 0xFF);
            candidate[5] = (byte)((strength >> 24) & 0xFF);
            templates.Add(new NamedPayload($"base14_strength_{strength:X8}", candidate));
            templates.Add(new NamedPayload($"base14_strength_{strength:X8}_padOut", PadPayload(candidate, outputReportBytes)));
        }

        byte[] xorChecksum = (byte[])baseStrength.Clone();
        xorChecksum[13] = ComputeXorChecksum(xorChecksum, 13);
        templates.Add(new NamedPayload("base14_xorchk", xorChecksum));
        templates.Add(new NamedPayload("base14_xorchk_padOut", PadPayload(xorChecksum, outputReportBytes)));

        byte[] sumChecksum = (byte[])baseStrength.Clone();
        sumChecksum[13] = ComputeSumChecksum(sumChecksum, 13);
        templates.Add(new NamedPayload("base14_sumchk", sumChecksum));
        templates.Add(new NamedPayload("base14_sumchk_padOut", PadPayload(sumChecksum, outputReportBytes)));

        // dos1 / Linux-Magic-Trackpad-2-Driver issue hints: USB form (BT form prefixes 0xF2).
        // Body (14 bytes, USB): 22/23, 01, s1, 78, 02, s2, 24, 30, 06, 01, s3, 18, 48, 13.
        byte[] dos1ClickLow = BuildDos1StrengthConfigBody(eventId: 0x22, s1: 0x15, s2: 0x04, s3: 0x04);
        byte[] dos1ReleaseLow = BuildDos1StrengthConfigBody(eventId: 0x23, s1: 0x10, s2: 0x00, s3: 0x00);
        templates.Add(new NamedPayload("dos1_click_low_14", PrependReportId(reportId, dos1ClickLow)));
        templates.Add(new NamedPayload("dos1_click_low_padOut", PadPayload(PrependReportId(reportId, dos1ClickLow), outputReportBytes)));
        templates.Add(new NamedPayload("dos1_release_low_14", PrependReportId(reportId, dos1ReleaseLow)));
        templates.Add(new NamedPayload("dos1_release_low_padOut", PadPayload(PrependReportId(reportId, dos1ReleaseLow), outputReportBytes)));

        byte[] dos1ClickMed = BuildDos1StrengthConfigBody(eventId: 0x22, s1: 0x17, s2: 0x06, s3: 0x06);
        byte[] dos1ReleaseMed = BuildDos1StrengthConfigBody(eventId: 0x23, s1: 0x14, s2: 0x00, s3: 0x00);
        templates.Add(new NamedPayload("dos1_click_med_padOut", PadPayload(PrependReportId(reportId, dos1ClickMed), outputReportBytes)));
        templates.Add(new NamedPayload("dos1_release_med_padOut", PadPayload(PrependReportId(reportId, dos1ReleaseMed), outputReportBytes)));

        byte[] dos1ClickHigh = BuildDos1StrengthConfigBody(eventId: 0x22, s1: 0x1E, s2: 0x08, s3: 0x08);
        byte[] dos1ReleaseHigh = BuildDos1StrengthConfigBody(eventId: 0x23, s1: 0x18, s2: 0x02, s3: 0x02);
        templates.Add(new NamedPayload("dos1_click_high_padOut", PadPayload(PrependReportId(reportId, dos1ClickHigh), outputReportBytes)));
        templates.Add(new NamedPayload("dos1_release_high_padOut", PadPayload(PrependReportId(reportId, dos1ReleaseHigh), outputReportBytes)));

        return templates;
    }

    private static bool RunActuatorPulse(SafeFileHandle handle, in HidProbeResult probe, ReaderOptions options)
    {
        if (probe.OutputReportBytes <= 0)
        {
            Console.Error.WriteLine("Actuator pulse requires OutputReportByteLength > 0 (select actuator interface).");
            return false;
        }

        // Your sweeps show report ID 0x53 is accepted on the Actuator interface.
        const int reportId = 0x53;

        byte s1 = (byte)(options.HidActuatorParam32 & 0xFF);
        byte s2 = (byte)((options.HidActuatorParam32 >> 8) & 0xFF);
        byte s3 = (byte)((options.HidActuatorParam32 >> 16) & 0xFF);

        byte[] clickBody = BuildDos1StrengthConfigBody(eventId: 0x22, s1: s1, s2: s2, s3: s3);
        byte[] releaseBody = BuildDos1StrengthConfigBody(eventId: 0x23, s1: 0x00, s2: 0x00, s3: 0x00);

        byte[] click = PadPayload(PrependReportId(reportId, clickBody), probe.OutputReportBytes);
        byte[] release = PadPayload(PrependReportId(reportId, releaseBody), probe.OutputReportBytes);

        Console.WriteLine();
        Console.WriteLine($"Actuator pulse: rid=0x{reportId:X2} count={options.HidActuatorCount} interval_ms={options.HidActuatorIntervalMs} param32=0x{options.HidActuatorParam32:X8} (s1={s1:X2} s2={s2:X2} s3={s3:X2})");

        for (int i = 0; i < options.HidActuatorCount; i++)
        {
            int frame = i + 1;
            bool okClick = TrySetOutputReport(handle, click, out int errClick) || TryWriteReport(handle, click, out errClick, out _);
            Console.WriteLine($"[{frame}] click_cfg ok={okClick} win32=0x{errClick:X}");

            bool okRelease = TrySetOutputReport(handle, release, out int errRelease) || TryWriteReport(handle, release, out errRelease, out _);
            Console.WriteLine($"[{frame}] release_cfg ok={okRelease} win32=0x{errRelease:X}");

            if (options.HidActuatorIntervalMs > 0 && frame < options.HidActuatorCount)
            {
                Thread.Sleep(options.HidActuatorIntervalMs);
            }
        }

        return true;
    }

    private static bool RunActuatorVibrate(SafeFileHandle handle, in HidProbeResult probe, ReaderOptions options)
    {
        if (probe.OutputReportBytes <= 0)
        {
            Console.Error.WriteLine("Actuator vibrate requires OutputReportByteLength > 0 (select actuator interface).");
            return false;
        }

        // Reverse-engineered by others: this "0x53" report appears to trigger immediate haptic output
        // on at least some AMT2 firmwares when sent to the Actuator interface.
        const int reportId = 0x53;

        uint strength = options.HidActuatorParam32;
        byte b0 = (byte)(strength & 0xFF);
        byte b1 = (byte)((strength >> 8) & 0xFF);
        byte b2 = (byte)((strength >> 16) & 0xFF);
        byte b3 = (byte)((strength >> 24) & 0xFF);

        // Matches https://gist.github.com/imbushuo/bed4c3641a827c62ffdd8629b5d04c74 (amt2-vibrator.cs)
        // Format:
        //  [0]  report id (0x53)
        //  [1]  magic (0x01)
        //  [2..5] strength (uint32 LE)
        //  [6..13] tail constants
        byte[] raw14 = BuildBytes(
            (byte)reportId, 0x01, b0, b1, b2, b3,
            0x21, 0x2B, 0x06, 0x01, 0x00, 0x16, 0x41, 0x13);

        byte[] payload = PadPayload(raw14, probe.OutputReportBytes);

        Console.WriteLine();
        Console.WriteLine($"Actuator vibrate: rid=0x{reportId:X2} count={options.HidActuatorCount} interval_ms={options.HidActuatorIntervalMs} strength=0x{strength:X8}");

        for (int i = 0; i < options.HidActuatorCount; i++)
        {
            int frame = i + 1;
            bool ok = TrySetOutputReport(handle, payload, out int err) || TryWriteReport(handle, payload, out err, out _);
            Console.WriteLine($"[{frame}] vibrate ok={ok} win32=0x{err:X}");

            if (options.HidActuatorIntervalMs > 0 && frame < options.HidActuatorCount)
            {
                Thread.Sleep(options.HidActuatorIntervalMs);
            }
        }

        return true;
    }

    private static byte[] BuildDos1StrengthConfigBody(byte eventId, byte s1, byte s2, byte s3)
    {
        // USB form: 14 bytes.
        return BuildBytes(
            eventId, 0x01,
            s1, 0x78, 0x02,
            s2, 0x24, 0x30, 0x06, 0x01,
            s3, 0x18, 0x48, 0x13);
    }

    private static byte[] PrependReportId(int reportId, byte[] body)
    {
        byte[] payload = new byte[1 + body.Length];
        payload[0] = (byte)reportId;
        Buffer.BlockCopy(body, 0, payload, 1, body.Length);
        return payload;
    }

    private static byte[] BuildBytes(params byte[] bytes)
    {
        byte[] payload = new byte[bytes.Length];
        Buffer.BlockCopy(bytes, 0, payload, 0, bytes.Length);
        return payload;
    }

    private static byte[] PadPayload(byte[] source, int length)
    {
        int targetLength = Math.Max(length, source.Length);
        byte[] payload = new byte[targetLength];
        Buffer.BlockCopy(source, 0, payload, 0, source.Length);
        return payload;
    }

    private static byte ComputeXorChecksum(byte[] buffer, int count)
    {
        byte checksum = 0;
        for (int i = 0; i < count && i < buffer.Length; i++)
        {
            checksum ^= buffer[i];
        }
        return checksum;
    }

    private static byte ComputeSumChecksum(byte[] buffer, int count)
    {
        int sum = 0;
        for (int i = 0; i < count && i < buffer.Length; i++)
        {
            sum = (sum + buffer[i]) & 0xFF;
        }
        return (byte)sum;
    }

    private static string FormatReportIdList(List<int> reportIds)
    {
        if (reportIds.Count == 0)
        {
            return "<none>";
        }

        StringBuilder sb = new();
        for (int i = 0; i < reportIds.Count; i++)
        {
            if (i > 0)
            {
                _ = sb.Append(',');
            }
            _ = sb.Append("0x");
            _ = sb.Append(reportIds[i].ToString("X2"));
        }

        return sb.ToString();
    }

    private static byte[] BuildAutoPayload(int length, byte reportId, byte? secondByte)
    {
        byte[] payload = new byte[length];
        payload[0] = reportId;
        if (secondByte.HasValue && length > 1)
        {
            payload[1] = secondByte.Value;
        }

        return payload;
    }

    private static ProbeAttemptResult ProbeOutputAttempt(SafeFileHandle handle, int reportId, string variant, byte[] payload)
    {
        bool ok = TrySetOutputReport(handle, payload, out int win32Error);
        return new ProbeAttemptResult(
            "set_output",
            reportId,
            variant,
            payload.Length,
            ok,
            win32Error,
            ok ? payload.Length : 0);
    }

    private static ProbeAttemptResult ProbeWriteAttempt(SafeFileHandle handle, int reportId, string variant, byte[] payload)
    {
        bool ok = TryWriteReport(handle, payload, out int win32Error, out uint bytesWritten);
        return new ProbeAttemptResult(
            "write_file",
            reportId,
            variant,
            payload.Length,
            ok,
            win32Error,
            (int)bytesWritten);
    }

    private static bool TrySetOutputReport(SafeFileHandle handle, byte[] payload, out int win32Error)
    {
        bool ok = HidD_SetOutputReport(handle, payload, payload.Length);
        win32Error = ok ? 0 : Marshal.GetLastWin32Error();
        return ok;
    }

    private static bool TryWriteReport(SafeFileHandle handle, byte[] payload, out int win32Error, out uint bytesWritten)
    {
        bool ok = WriteFile(handle, payload, (uint)payload.Length, out bytesWritten, IntPtr.Zero);
        win32Error = ok ? 0 : Marshal.GetLastWin32Error();
        return ok;
    }

    private static InputReportSnapshot TryReadInputReport(SafeFileHandle handle, int inputLength, byte reportId)
    {
        if (inputLength <= 0)
        {
            return new InputReportSnapshot(false, 0, null);
        }

        byte[] buffer = new byte[inputLength];
        buffer[0] = reportId;
        bool ok = HidD_GetInputReport(handle, buffer, buffer.Length);
        int win32Error = ok ? 0 : Marshal.GetLastWin32Error();
        string? payloadHex = ok ? FormatHex(buffer) : null;
        return new InputReportSnapshot(ok, win32Error, payloadHex);
    }

    private static string ResolveAutoProbeLogPath(string? requestedPath)
    {
        if (!string.IsNullOrWhiteSpace(requestedPath))
        {
            return Path.GetFullPath(requestedPath);
        }

        string localRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "GlassToKey");
        return Path.Combine(localRoot, $"hid-auto-probe-{DateTime.Now:yyyyMMdd-HHmmss}.log");
    }

    private static string FormatHex(byte[] bytes)
    {
        if (bytes.Length == 0)
        {
            return "<empty>";
        }

        StringBuilder sb = new(bytes.Length * 3);
        for (int i = 0; i < bytes.Length; i++)
        {
            if (i > 0)
            {
                _ = sb.Append(' ');
            }
            _ = sb.Append(bytes[i].ToString("X2"));
        }
        return sb.ToString();
    }

    private static bool TryParsePayload(string? payloadText, string optionName, out byte[]? payload, out string? error)
    {
        payload = null;
        error = null;
        if (string.IsNullOrWhiteSpace(payloadText))
        {
            return true;
        }

        if (!TryParseHexBytes(payloadText, out byte[] bytes))
        {
            error = $"{optionName} must be hex bytes like \"01 02 A0\" or \"0102A0\".";
            return false;
        }

        if (bytes.Length == 0)
        {
            error = $"{optionName} payload cannot be empty.";
            return false;
        }

        payload = bytes;
        return true;
    }

    private static bool TryParseHexBytes(string text, out byte[] bytes)
    {
        bytes = Array.Empty<byte>();
        string normalized = text
            .Replace(",", " ", StringComparison.Ordinal)
            .Replace(";", " ", StringComparison.Ordinal)
            .Replace("|", " ", StringComparison.Ordinal)
            .Trim();
        if (normalized.Length == 0)
        {
            return false;
        }

        string[] tokens = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        List<byte> output = new();

        if (tokens.Length == 1 && IsContiguousHex(tokens[0]))
        {
            string token = StripHexPrefix(tokens[0]);
            if ((token.Length & 1) != 0)
            {
                return false;
            }

            for (int i = 0; i < token.Length; i += 2)
            {
                if (!byte.TryParse(token.AsSpan(i, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte value))
                {
                    return false;
                }
                output.Add(value);
            }

            bytes = output.ToArray();
            return true;
        }

        foreach (string raw in tokens)
        {
            string token = StripHexPrefix(raw);
            if (token.Length == 0 || token.Length > 2)
            {
                return false;
            }
            if (!byte.TryParse(token, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte value))
            {
                return false;
            }
            output.Add(value);
        }

        bytes = output.ToArray();
        return output.Count > 0;
    }

    private static bool IsContiguousHex(string token)
    {
        string trimmed = StripHexPrefix(token);
        if (trimmed.Length == 0)
        {
            return false;
        }

        for (int i = 0; i < trimmed.Length; i++)
        {
            char ch = trimmed[i];
            bool isHex =
                (ch >= '0' && ch <= '9') ||
                (ch >= 'a' && ch <= 'f') ||
                (ch >= 'A' && ch <= 'F');
            if (!isHex)
            {
                return false;
            }
        }
        return true;
    }

    private static string StripHexPrefix(string token)
    {
        if (token.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return token.Substring(2);
        }

        return token;
    }

    private static string? GetUnicodeHidString(SafeFileHandle handle, HidStringReader reader)
    {
        byte[] buffer = new byte[256];
        if (!reader(handle, buffer, buffer.Length))
        {
            return null;
        }

        string value = Encoding.Unicode.GetString(buffer).TrimEnd('\0', ' ');
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private readonly record struct HidProbeResult(
        ushort VendorId,
        ushort ProductId,
        ushort VersionNumber,
        ushort UsagePage,
        ushort Usage,
        ushort InputReportBytes,
        ushort OutputReportBytes,
        ushort FeatureReportBytes,
        string? Manufacturer,
        string? Product,
        string? SerialNumber);

    private readonly record struct CandidateHidInterface(string Path, string DisplayName);

    private readonly record struct NamedPayload(string Name, byte[] Payload);

    private readonly record struct ProbeAttemptResult(
        string Api,
        int ReportId,
        string Variant,
        int Length,
        bool Ok,
        int Win32Error,
        int BytesWritten)
    {
        public string ToLogLine()
        {
            return $"api={Api} rid=0x{ReportId:X2} variant={Variant} len={Length} ok={Ok} win32=0x{Win32Error:X} bytes={BytesWritten}";
        }
    }

    private readonly record struct InputReportSnapshot(
        bool Ok,
        int Win32Error,
        string? PayloadHex)
    {
        public string ToLogLine(int reportId, string variant)
        {
            if (!Ok)
            {
                return $"api=get_input rid=0x{reportId:X2} variant={variant} ok=False win32=0x{Win32Error:X}";
            }

            return $"api=get_input rid=0x{reportId:X2} variant={variant} ok=True win32=0x0 payload={PayloadHex}";
        }
    }

    private sealed class ProbeLog
    {
        private readonly List<string> _lines = new();

        public IReadOnlyList<string> Lines => _lines;

        public void Info(string line)
        {
            _lines.Add(line);
            Console.WriteLine(line);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HiddAttributes
    {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HidpCaps
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    private delegate bool HidStringReader(SafeFileHandle handle, byte[] buffer, int bufferLength);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(
        SafeFileHandle hFile,
        byte[] lpBuffer,
        uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten,
        IntPtr lpOverlapped);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetAttributes(SafeFileHandle hidDeviceObject, ref HiddAttributes attributes);

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle hidDeviceObject, out IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsedData, out HidpCaps capabilities);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetOutputReport(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetInputReport(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetManufacturerString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetProductString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetSerialNumberString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid,
        IntPtr enumerator,
        IntPtr hwndParent,
        uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet,
        IntPtr deviceInfoData,
        ref Guid interfaceClassGuid,
        uint memberIndex,
        ref SpDeviceInterfaceData deviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet,
        ref SpDeviceInterfaceData deviceInterfaceData,
        IntPtr deviceInterfaceDetailData,
        uint deviceInterfaceDetailDataSize,
        out uint requiredSize,
        IntPtr deviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);
}
