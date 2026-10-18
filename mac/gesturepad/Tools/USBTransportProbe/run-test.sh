#!/bin/zsh
set -euo pipefail
probe_dir=${0:A:h}
probe_binary=/tmp/GesturePad-USBTransportProbe
probe_trace=0
if [[ ${1:-} == --kernel-trace ]]; then
    probe_trace=1
    sudo -v
elif (( $# > 0 )); then
    print -u2 'Usage: run-test.sh [--kernel-trace]'
    exit 2
fi
clang -Wall -Wextra -Wno-deprecated-declarations "$probe_dir/main.c" -framework IOKit -framework CoreFoundation -o "$probe_binary"
print 'Waiting for a NEW right USB capture in GesturePad (up to 2 minutes).'
print 'Select RIGHT USB 0001:0002; leave the HID mode-request checkbox UNCHECKED.'
print 'Click “Capture one (15s)”, then move one and two fingers throughout.'
print 'The direct USB command will run about 2 seconds after capture starts.'
python3 - "$probe_binary" "$probe_trace" <<'PY'
import os,pathlib,subprocess,sys,time
marker=pathlib.Path('/tmp/GesturePad-active-usb-capture.txt')
def read():
    try: return marker.read_text()
    except FileNotFoundError: return ''
initial=read()
armed=time.time()
while time.time()-armed<120:
    value=read()
    if value and value!=initial:
        fields=value.splitlines()
        if len(fields)!=4 or fields[0]!='J84HMA00H0B0000501':
            raise SystemExit('Marker is not the expected right USB pad; no command sent.')
        age=time.time()-float(fields[2])
        if not 0<=age<3:
            raise SystemExit('Capture marker is stale; no command sent.')
        env=dict(os.environ,GESTUREPAD_CAPTURE_MARKER=value)
        log=pathlib.Path(f'/tmp/GesturePad-direct-usb-{time.time_ns()}.log')
        trace=None
        trace_file=None
        if sys.argv[2]=='1':
            trace_path=pathlib.Path(f'/tmp/GesturePad-usb-hid-seized-{time.time_ns()}.ndjson')
            trace_file=trace_path.open('w')
            trace=subprocess.Popen(['sudo','-n','/usr/bin/ktrace','trace','-T','18s','-f','S0x052d,S0x0523','--ndjson'],stdout=trace_file)
            time.sleep(.25)
            if trace.poll() is not None:
                trace_file.close()
                raise SystemExit('Kernel tracer stopped before the command; no USB command sent.')
        with log.open('w') as out:
            out.write('captureMarker='+repr(value)+'\n');out.flush()
            subprocess.run([sys.argv[1],'--send-multitouch'],env=env,stdout=out,stderr=subprocess.STDOUT,check=True)
        print(log.read_text())
        print(f'Saved: {log}')
        if trace is not None:
            print('Waiting for bounded kernel trace to finish...',flush=True)
            result=trace.wait()
            trace_file.close()
            print(f'Kernel trace exit={result}: {trace_path}')
        break
    time.sleep(.05)
else:
    raise SystemExit('No new eligible capture started; no command sent.')
PY
