namespace GlassToKey;

// A live host may publish semantic events directly. Offline engines retain the
// drainable ring for replay/diagnostics without owning a platform dispatcher.
internal interface IEngineDispatchSink
{
    bool TryPublish(in DispatchEvent dispatchEvent);
}
