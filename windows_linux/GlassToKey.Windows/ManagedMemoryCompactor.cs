using System;
using System.Runtime;
using System.Threading;

namespace GlassToKey;

internal static class ManagedMemoryCompactor
{
    private static int _compactionQueued;

    public static void QueueCompaction()
    {
        if (Interlocked.Exchange(ref _compactionQueued, 1) != 0)
        {
            return;
        }

        _ = ThreadPool.QueueUserWorkItem(static _ =>
        {
            try
            {
                GCSettings.LargeObjectHeapCompactionMode = GCLargeObjectHeapCompactionMode.CompactOnce;
                GC.Collect();
                GC.WaitForPendingFinalizers();
                GC.Collect();
            }
            finally
            {
                Volatile.Write(ref _compactionQueued, 0);
            }
        });
    }
}
