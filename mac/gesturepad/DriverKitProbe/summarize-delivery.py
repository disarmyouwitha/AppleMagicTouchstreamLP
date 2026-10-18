#!/usr/bin/env python3
"""Read-only summary of per-provider HID activity vs dext report-delivery counters."""
import collections,json,pathlib,plistlib,sys
root=pathlib.Path(sys.argv[1]);nodes=plistlib.loads((root/'registry-after.plist').read_bytes());receivers=[]
def walk(n,path):
    if not isinstance(n,dict):return
    path=path+[n]
    if n.get('IOUserClass')=='AMTRawHIDReceiver':receivers.append(path)
    for child in n.get('IORegistryEntryChildren',[]):walk(child,path)
for n in nodes if isinstance(nodes,list) else [nodes]:walk(n,[])
events=[];bad=0
for line in (root/'delivery.ndjson').read_text().splitlines():
    if not line.strip():continue
    try:events.append(json.loads(line))
    except ValueError:bad+=1
summary={'parsedTraceEvents':len(events),'unparsedLines':bad,'receivers':[]}
for path in receivers:
    receiver=path[-1];interface=path[-2]
    provider=next((x for x in reversed(path[:-1]) if x.get('IOObjectClass')=='AppleUSBTopCaseHIDDriver'),{})
    rid=str(provider.get('IORegistryEntryID',''))
    count=sum(e.get('debugid')==0x0523003c and e.get('args',[''])[0]==rid for e in events)
    summary['receivers'].append({'physicalProviderRegistryID':rid,'physicalProviderHIDHandleReportEvents':count,
        'interfaceDebugState':interface.get('DebugState'),
        'receiver':{k:receiver.get(k) for k in ['ProbeBuild','Callbacks','ModeAttempted','ModeResult','Reports','Reports8','Reports21','Reports30','FirstFullLength','CloseResult']}})
summary['note']='HID_HandleReport tracepoints prove entry, not full processing or payload; counters may be absent if driver unloaded before final snapshot.'
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
