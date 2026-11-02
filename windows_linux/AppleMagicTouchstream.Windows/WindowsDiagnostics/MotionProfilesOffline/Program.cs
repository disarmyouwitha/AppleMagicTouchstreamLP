using System.Runtime.InteropServices;
using AppleMagicTouchstream;
MacMotionTests.Run();
ShapeGestureParityTests.Run();
WindowsAbsolutePointerTests.Run();
RewriteParityTests.Run();
if(!HandGestureTests.Run(out var failure))throw new Exception(failure);
StenoPointerTests.Run();StenoTests.Run();
Console.WriteLine("Existing hand-gesture regressions and STENO actor integration passed (WPF-only tests excluded).");
Console.WriteLine("Mac motion tests passed: scroll golden vectors, axis history, settings, drag, STENO, momentum and cross-pad braking. No native input used.");

if(Environment.GetEnvironmentVariable("AMT_JAVELIN_LIBRARY") is {} library)
{
    NativeLibrary.SetDllImportResolver(typeof(WindowsJavelin).Assembly,(name,_,_)=>name=="AMTJavelin" ? NativeLibrary.Load(library):IntPtr.Zero);
    JavelinParityTests.Run();StenoTransportParityTests.Run();
}
