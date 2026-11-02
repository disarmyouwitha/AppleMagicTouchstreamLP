using System.Diagnostics;
using System.Runtime.InteropServices;
namespace AppleMagicTouchstream;

internal sealed partial class SendInputDispatcher
{
    private int _stenoResetRequested;
    private readonly Queue<DispatchEvent> _stenoPending=new();
    private string? _stenoText;
    private int _stenoTextIndex,_stenoDeletes;
    private long _stenoEditGeneration;
    private IntPtr _stenoFocus;
    private readonly Input[] _stenoInputs=new Input[64];
    private void CancelStenoText()
    { _stenoText=null;_stenoPending.Clear();_stenoDeletes=0;StenoConnection?.ResetTranslation(); }
    private void DispatchSteno(in DispatchEvent e)
    {
        if(_stenoText!=null){if(_stenoPending.Count>=64){CancelStenoText();return;}_stenoPending.Enqueue(e);return;}
        var connection=StenoConnection;if(connection==null)return;
        IntPtr focus=GetForegroundWindow();
        if(focus!=_stenoFocus){connection.ResetTranslation();_stenoFocus=focus;}
        if(connection.Send(e) && connection.TakeEdit() is {} edit)
        { _stenoText=edit.Text;_stenoDeletes=edit.Backspaces;_stenoTextIndex=0;_stenoEditGeneration=e.StenoGeneration; }
    }
    private void TickStenoText()
    {
        if(_stenoText==null)return;
        if(_suppressPhysicalOutput || _disposed || StenoConnection?.CanOutput(_stenoEditGeneration)!=true || GetForegroundWindow()!=_stenoFocus)
        {CancelStenoText();return;}
        foreach(ushort key in new ushort[]{0x10,0x11,0x12,0x5B,0x5C})if(ExistingPhysicalKey(key)||_modifierRefCounts[key]>0){CancelStenoText();return;}
        int count=0;
        while(count+2<=_stenoInputs.Length && (_stenoDeletes>0 || _stenoTextIndex<_stenoText.Length))
        {
            Input down;
            if(_stenoDeletes>0){down=CreateKeyboardInput(8,false);_stenoDeletes--;}
            else
            {
                char unit=_stenoText[_stenoTextIndex++];
                down=unit is '\r' or '\n' or '\t' ? CreateKeyboardInput(unit=='\t' ? (ushort)9:(ushort)13,false):new Input {Type=InputKeyboard,Union=new InputUnion {Keyboard=new KeyboardInput {ScanCode=unit,Flags=4}}};
            }
            var up=down;up.Union.Keyboard.Flags|=KeyeventfKeyup;_stenoInputs[count++]=down;_stenoInputs[count++]=up;
        }
        if(count>0)
        {
            uint sent=SendInput((uint)count,_stenoInputs,Marshal.SizeOf<Input>());
            if(sent!=count)
            {if((sent&1)!=0){_singleInput[0]=_stenoInputs[sent];_=SendInput(1,_singleInput,Marshal.SizeOf<Input>());}CancelStenoText();StenoConnection?.ReportOutputError();return;}
        }
        if(_stenoDeletes==0 && _stenoTextIndex==_stenoText.Length)
        {
            _stenoText=null;
            if(_stenoPending.TryDequeue(out var next))DispatchSteno(next);
        }
    }
}
