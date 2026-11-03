#!/usr/bin/env python3
"""Rebuild the bundled Windows x64 DLL on a POSIX host using Zig 0.13.0 + CMake."""
import argparse, hashlib, json, os, pathlib, shlex, shutil, subprocess, tempfile

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args=parser.parse_args()
    zig=args.zig.resolve()
    if subprocess.check_output([str(zig),"version"],text=True).strip()!="0.13.0":
        parser.error("Use pinned Zig 0.13.0; compiler updates require native parity verification.")
    if os.name!="posix": parser.error("Use a POSIX build host, or the ClangCL CMake instructions.")
    root=pathlib.Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix="amt-javelin-build-") as folder:
        work=pathlib.Path(folder)
        wrappers={}
        for name,command in {"cxx":"c++ -target x86_64-windows-gnu","ar":"ar","ranlib":"ranlib"}.items():
            wrapper=work/name
            wrapper.write_text("#!/bin/sh\nexec "+shlex.quote(str(zig))+" "+command+' "$@"\n')
            wrapper.chmod(0o755);wrappers[name]=str(wrapper)
        toolchain=work/"toolchain.cmake"
        toolchain.write_text('set(CMAKE_SYSTEM_NAME Windows)\n'+"\n".join('set('+key+' "'+value+'")' for key,value in {
            "CMAKE_CXX_COMPILER":wrappers["cxx"],"CMAKE_AR":wrappers["ar"],"CMAKE_CXX_COMPILER_AR":wrappers["ar"],
            "CMAKE_RANLIB":wrappers["ranlib"],"CMAKE_RC_COMPILER":shutil.which("true"),"CMAKE_TRY_COMPILE_TARGET_TYPE":"STATIC_LIBRARY"}.items())+"\n")
        build=work/"build"
        subprocess.run(["cmake","-S",str(root),"-B",str(build),"-DCMAKE_BUILD_TYPE=Release","-DCMAKE_TOOLCHAIN_FILE="+str(toolchain)],check=True)
        subprocess.run(["cmake","--build",str(build),"--parallel","4"],check=True)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(build/"AMTJavelin.dll",args.output)
        print(json.dumps({"path":str(args.output),"bytes":args.output.stat().st_size,"sha256":hashlib.sha256(args.output.read_bytes()).hexdigest()}))
if __name__=="__main__":main()
