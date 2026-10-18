#!/usr/bin/env python3
"""Offline parser; retain only actual report length, excluding dump padding.
Decode USB trackpad2 layout from Linux drivers/hid/hid-magicmouse.c.
Tracking IDs are not anatomical finger labels.
"""
import argparse, collections, json, pathlib, re

def signed13(value):
    value &= 8191
    return value - 8192 if value & 4096 else value

def decode(data):
    if not data or data[0] != 2 or len(data) < 12 or (len(data)-12)%9:
        raise ValueError('Not a USB Trackpad2 ID02 12+9N packet')
    contacts=[]
    for off in range(12,len(data),9):
        t=data[off:off+9]
        contacts.append(dict(trackingID=t[8]&15,
            x=signed13(t[1]<<8 | t[0]),
            y=-signed13((t[3]<<16 | t[2]<<8 | t[1])>>5),
            size=t[6], pressure=t[7], major=t[4], minor=t[5],
            orientation=(t[8]>>5)-4, state=t[3]&192, down=(t[3]&192)==128))
    return dict(clickBits=data[1],contacts=contacts)

def parse(text):
    if re.search(r'dtrace:.*(?:error|failed)|invalid address|drops on CPU',text,re.I):
        raise ValueError('Trace contains an error/drop diagnostic; inspect before decoding')
    result=[]
    for m in re.finditer(r'REPORT ([^\n]+)\n(.*?)(?=REPORT |END reports=|\Z)',text,re.S):
        meta=dict(re.findall(r'(\w+)=([^ ]+)',m[1]));length=int(meta['length']);data=bytearray()
        for line in m[2].splitlines():
            row=re.match(r'^\s*([0-9a-f]+): (.*)',line)
            if row:
                if int(row[1],16)!=len(data):raise ValueError('Nonsequential memory dump')
                data.extend(bytes.fromhex(row[2][:47]))
        if len(data)<length:raise ValueError('Truncated memory dump')
        payload=bytes(data[:length])
        record=dict(traceTimestampNs=int(meta.get('trace_timestamp_ns',meta.get('uptime_ns'))),
            registryID=int(meta['rid']),length=length,payloadHex=payload.hex(),**decode(payload))
        if 'unix_ns' in meta:record['unixNs']=int(meta['unix_ns'])
        result.append(record)
    end=re.search(r'END reports=(\d+)',text)
    if not end or len(result)!=int(end[1]):raise ValueError('Missing END or mismatched report count')
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('input',type=pathlib.Path);ap.add_argument('output',type=pathlib.Path);args=ap.parse_args()
    reports=parse(args.input.read_text())
    counts=collections.Counter(len(r['contacts']) for r in reports)
    summary=dict(reports=len(reports),contactCountHistogram=dict(counts),
        source='https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c',
        note='First capture trace timestamp label uptime_ns was not independently aligned to system uptime; treat as opaque monotonic trace time.')
    args.output.write_text(json.dumps(dict(format='GesturePad.OriginalUSBReports',version=1,summary=summary,reports=reports),indent=2)+'\n')
    print(json.dumps(summary,indent=2))
