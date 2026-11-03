using System.Diagnostics;
using System.Runtime.InteropServices;
namespace AppleMagicTouchstream;

internal sealed partial class SendInputDispatcher
{
    private long _savedTextGeneration;
    private Task<string>? _savedTextRead;
    private string? _savedText;
    private int _savedTextIndex;
    private IntPtr _savedTextFocus;
    private long _savedTextRequestGeneration,_savedTextNext;
    private string? _savedTextStatus;
    private long? _savedTextGestureGeneration;
    private static readonly ushort[] SavedTextModifiers={0x10,0x11,0x12,0x5B,0x5C};
    internal string? SavedTextStatus=>Volatile.Read(ref _savedTextStatus);
    private void CancelSavedText()
    { Interlocked.Increment(ref _savedTextGeneration); _savedText=null; _savedTextRead=null; _savedTextIndex=0; }
    private void BeginSavedText(in DispatchEvent e)
    {
        if(_suppressPhysicalOutput || !TextShortcutReference.TryRead(string.IsNullOrEmpty(e.DispatchLabel) ? e.SemanticAction.Label : e.DispatchLabel,out var id)) return;
        if(e.Kind==DispatchEventKind.GestureText && GestureKeyboardSession?.Accepts(e)!=true) return;
        CancelSavedText();
        _autocorrect.ForceReset("saved_text");
        _savedTextGestureGeneration=e.Kind==DispatchEventKind.GestureText ? e.GestureGeneration : null;
        _savedTextFocus=GetForegroundWindow();
        if(_savedTextFocus==IntPtr.Zero) return;
        _savedTextRequestGeneration=Interlocked.Read(ref _savedTextGeneration);
        _savedTextNext=Stopwatch.GetTimestamp(); _savedTextStatus="Loading saved text";
        _savedTextRead=Task.Run(()=>WindowsTextShortcutStore.Shared.Load(id));
    }
    private void TickSavedText(long now)
    {
        if(_savedTextRead==null && _savedText==null) return;
        if(_suppressPhysicalOutput || _disposed || Interlocked.Read(ref _savedTextGeneration)!=_savedTextRequestGeneration || GetForegroundWindow()!=_savedTextFocus || (_savedTextGestureGeneration is {} generation && GestureKeyboardSession?.AcceptsTextGeneration(generation)!=true))
        { CancelSavedText(); _savedTextStatus="Saved text cancelled"; return; }
        if(_savedTextRead is {} read)
        {
            if(!read.IsCompleted) return;
            _savedTextRead=null;
            if(!read.IsCompletedSuccessfully) { _=read.Exception; CancelSavedText(); _savedTextStatus="Saved text unavailable. Re-enter it on this Windows account."; return; }
            _savedText=read.Result.Replace("\r\n","\n");
        }
        if(_savedText==null || now<_savedTextNext) return;
        if(_savedText.Length==0) { CancelSavedText(); _savedTextStatus="Saved text typed";return; }
        // Never release a user's physical modifiers or another owner's holds.
        // Unicode VK_PACKET output is unsafe while shortcut modifiers are down.
        foreach(var key in SavedTextModifiers)
            if(ExistingPhysicalKey(key) || _modifierRefCounts[key]>0) { CancelSavedText(); _savedTextStatus="Release modifiers and try saved text again."; return; }
        char unit=_savedText[_savedTextIndex];
        var down=unit is '\n' or '\r' or '\t' ? CreateKeyboardInput(unit=='\t' ? (ushort)9 : (ushort)13,false) : new Input { Type=InputKeyboard,Union=new InputUnion { Keyboard=new KeyboardInput { ScanCode=unit,Flags=4 } } };
        var up=down; up.Union.Keyboard.Flags|=KeyeventfKeyup;
        _dualInput[0]=down; _dualInput[1]=up;
        uint sent=SendInput(2,_dualInput,Marshal.SizeOf<Input>());
        if(sent!=2) { if(sent==1) { _singleInput[0]=up; _=SendInput(1,_singleInput,Marshal.SizeOf<Input>()); } CancelSavedText(); _savedTextStatus="Saved text blocked by Windows input permissions."; return; }
        _savedTextIndex++; _savedTextNext=now+Stopwatch.Frequency/200;
        if(_savedTextIndex==_savedText.Length) { CancelSavedText(); _savedTextStatus="Saved text typed"; }
    }
}
