using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux;

public sealed class LinuxInputRuntimeService
{
    private readonly LinuxEvdevReader _reader;
    private readonly ILinuxTrackpadBackend _trackpadBackend;

    public LinuxInputRuntimeService(
        LinuxEvdevReader? reader = null,
        ILinuxTrackpadBackend? trackpadBackend = null)
    {
        _reader = reader ?? new LinuxEvdevReader();
        _trackpadBackend = trackpadBackend ?? new LinuxTrackpadEnumerator();
    }

    public Task RunAsync(
        IReadOnlyList<LinuxTrackpadBinding> bindings,
        ILinuxInputFrameSink sink,
        LinuxInputRuntimeOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        ArgumentNullException.ThrowIfNull(sink);
        if (bindings.Count == 0)
        {
            throw new ArgumentException("At least one Linux trackpad binding is required.", nameof(bindings));
        }

        Task[] tasks = new Task[bindings.Count];
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            tasks[index] = RunBindingLoopAsync(binding, sink, options ?? LinuxInputRuntimeOptions.Default, cancellationToken);
        }

        return Task.WhenAll(tasks);
    }

    public Task RunAsync(
        IReadOnlyList<LinuxTrackpadBinding> bindings,
        ITrackpadFrameTarget target,
        LinuxInputRuntimeOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        ArgumentNullException.ThrowIfNull(target);
        if (bindings.Count == 0)
        {
            throw new ArgumentException("At least one Linux trackpad binding is required.", nameof(bindings));
        }

        Task[] tasks = new Task[bindings.Count];
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            tasks[index] = RunBindingLoopAsync(binding, target, options ?? LinuxInputRuntimeOptions.Default, cancellationToken);
        }

        return Task.WhenAll(tasks);
    }

    private async Task RunBindingLoopAsync(
        LinuxTrackpadBinding binding,
        ILinuxInputFrameSink sink,
        LinuxInputRuntimeOptions options,
        CancellationToken cancellationToken)
    {
        await RunBindingLoopCoreAsync(
            binding,
            options,
            async (activeBinding, snapshot, token) =>
            {
                await sink.OnFrameAsync(new LinuxRuntimeFrame(activeBinding, snapshot), token).ConfigureAwait(false);
                return true;
            },
            cancellationToken).ConfigureAwait(false);
    }

    private async Task RunBindingLoopAsync(
        LinuxTrackpadBinding binding,
        ITrackpadFrameTarget target,
        LinuxInputRuntimeOptions options,
        CancellationToken cancellationToken)
    {
        await RunBindingLoopCoreAsync(
            binding,
            options,
            (activeBinding, snapshot, token) =>
            {
                token.ThrowIfCancellationRequested();
                TrackpadFrameEnvelope envelope = new(
                    activeBinding.Side,
                    snapshot.Frame,
                    snapshot.MaxX,
                    snapshot.MaxY,
                    snapshot.Frame.ArrivalQpcTicks);
                return ValueTask.FromResult(target.Post(in envelope));
            },
            cancellationToken).ConfigureAwait(false);
    }

    private async Task RunBindingLoopCoreAsync(
        LinuxTrackpadBinding binding,
        LinuxInputRuntimeOptions options,
        Func<LinuxTrackpadBinding, LinuxEvdevFrameSnapshot, CancellationToken, ValueTask<bool>> onFrame,
        CancellationToken cancellationToken)
    {
        string stableId = binding.Device.StableId;
        string? activeDeviceNode = null;
        LinuxRuntimeBindingState? lastReported = null;
        Report(options.Observer, ref lastReported, binding.Side, stableId, binding.Device.DeviceNode, LinuxRuntimeBindingStatus.Starting, "Starting Linux input binding.");

        while (!cancellationToken.IsCancellationRequested)
        {
            LinuxInputDeviceDescriptor? currentDevice = ResolveCurrentDevice(stableId);
            if (currentDevice == null)
            {
                Report(options.Observer, ref lastReported, binding.Side, stableId, activeDeviceNode, LinuxRuntimeBindingStatus.WaitingForDevice, "Waiting for trackpad to reappear.");
                activeDeviceNode = null;
                await DelayReconnectAsync(options.ReconnectDelay, cancellationToken).ConfigureAwait(false);
                continue;
            }

            if (!currentDevice.CanOpenEventStream)
            {
                Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.WaitingForDevice, currentDevice.AccessError);
                activeDeviceNode = currentDevice.DeviceNode;
                await DelayReconnectAsync(options.ReconnectDelay, cancellationToken).ConfigureAwait(false);
                continue;
            }

            LinuxTrackpadBinding activeBinding = new(binding.Side, currentDevice);
            if (!string.Equals(activeDeviceNode, currentDevice.DeviceNode, StringComparison.OrdinalIgnoreCase))
            {
                Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.Rebinding, "Opening trackpad event stream.");
                activeDeviceNode = currentDevice.DeviceNode;
            }

            Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.Streaming, "Streaming evdev frames.");

            try
            {
                await _reader.StreamFramesAsync(
                    currentDevice.DeviceNode,
                    snapshot => onFrame(activeBinding, snapshot, cancellationToken),
                    cancellationToken).ConfigureAwait(false);

                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.Disconnected, "Trackpad stream ended; waiting to rebind.");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (IOException ex)
            {
                Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.Disconnected, ex.Message);
            }
            catch (UnauthorizedAccessException ex)
            {
                Report(options.Observer, ref lastReported, binding.Side, stableId, currentDevice.DeviceNode, LinuxRuntimeBindingStatus.Faulted, ex.Message);
            }

            await DelayReconnectAsync(options.ReconnectDelay, cancellationToken).ConfigureAwait(false);
        }

        Report(options.Observer, ref lastReported, binding.Side, stableId, activeDeviceNode, LinuxRuntimeBindingStatus.Stopped, "Stopped Linux input binding.");
    }

    private LinuxInputDeviceDescriptor? ResolveCurrentDevice(string stableId)
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _trackpadBackend.EnumerateDevices();
        for (int index = 0; index < devices.Count; index++)
        {
            if (string.Equals(devices[index].StableId, stableId, StringComparison.OrdinalIgnoreCase))
            {
                return devices[index];
            }
        }

        return null;
    }

    private static async Task DelayReconnectAsync(TimeSpan delay, CancellationToken cancellationToken)
    {
        if (delay <= TimeSpan.Zero)
        {
            return;
        }

        try
        {
            await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal shutdown path for timed runs and process exit.
        }
    }

    private static void Report(
        ILinuxRuntimeObserver? observer,
        ref LinuxRuntimeBindingState? lastReported,
        TrackpadSide side,
        string stableId,
        string? deviceNode,
        LinuxRuntimeBindingStatus status,
        string message)
    {
        LinuxRuntimeBindingState state = new(side, stableId, deviceNode, status, message);
        if (state == lastReported)
        {
            return;
        }

        lastReported = state;
        observer?.OnBindingStateChanged(state);
    }
}
