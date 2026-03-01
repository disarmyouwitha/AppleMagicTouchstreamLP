using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux;

public sealed class LinuxInputRuntimeService
{
    private readonly LinuxEvdevReader _reader;

    public LinuxInputRuntimeService(LinuxEvdevReader? reader = null)
    {
        _reader = reader ?? new LinuxEvdevReader();
    }

    public Task RunAsync(
        IReadOnlyList<LinuxTrackpadBinding> bindings,
        ILinuxInputFrameSink sink,
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
            tasks[index] = RunBindingAsync(binding, sink, cancellationToken);
        }

        return Task.WhenAll(tasks);
    }

    public Task RunAsync(
        IReadOnlyList<LinuxTrackpadBinding> bindings,
        ITrackpadFrameTarget target,
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
            tasks[index] = RunBindingAsync(binding, target, cancellationToken);
        }

        return Task.WhenAll(tasks);
    }

    private async Task RunBindingAsync(
        LinuxTrackpadBinding binding,
        ILinuxInputFrameSink sink,
        CancellationToken cancellationToken)
    {
        await _reader.StreamFramesAsync(
            binding.Device.DeviceNode,
            async snapshot =>
            {
                await sink.OnFrameAsync(new LinuxRuntimeFrame(binding, snapshot), cancellationToken).ConfigureAwait(false);
                return true;
            },
            cancellationToken).ConfigureAwait(false);
    }

    private async Task RunBindingAsync(
        LinuxTrackpadBinding binding,
        ITrackpadFrameTarget target,
        CancellationToken cancellationToken)
    {
        await _reader.StreamFramesAsync(
            binding.Device.DeviceNode,
            snapshot =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                TrackpadFrameEnvelope envelope = new(
                    binding.Side,
                    snapshot.Frame,
                    snapshot.MaxX,
                    snapshot.MaxY,
                    snapshot.Frame.ArrivalQpcTicks);
                return ValueTask.FromResult(target.Post(in envelope));
            },
            cancellationToken).ConfigureAwait(false);
    }
}
