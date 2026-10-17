#!/usr/bin/env python3
"""Supplement Swift RewriteProbe with per-frame membership/label timelines.
Read-only ATPCAP v5 extraction; corroborates frame/active totals with Swift JSON.
No gesture decisions, physical finger truth, mm calibration or output generation.
"""
from pathlib import Path
import collections,hashlib,json,struct,subprocess
root=Path(__file__).resolve().parents[2];out=root/'RewriteValidation/reports-lifecycle-2026-10-17';out.mkdir(exist_ok=True)
names=['palm-held-cohorts','partial-lift-replacement','five-to-two-rearm','opposite-pad-held']
summary={}
for name in names:
 path=root/f'RewriteValidation/captures/{name}.atpcap';data=path.read_bytes();assert data[:8]==b'ATPCAP01'
 version,freq=struct.unpack_from('<iq',data,8);assert version==5 and freq>0
 offset=20;frames=[];first=None
 while offset<len(data):
  assert offset+34<=len(data);length,ticks,index=struct.unpack_from('<iqi',data,offset);assert length>=0;offset+=34
  assert offset+length<=len(data);payload=data[offset:offset+length];offset+=length
  if index!=-5:continue
  packet=json.loads(payload);assert packet['type']=='processedFrameRecord';record=packet['record'];f=record['frame']
  if first is None:first=ticks
  frames.append({'t':max(0,ticks-first)/freq,'device':f['deviceIndex'],'sequence':f['sequence'],'sourceTime':f['timestamp'],'contacts':[c for c in f['contacts'] if c['state'] in ['starting','making','touching']]})
 assert offset==len(data)
 result={'input_sha256':hashlib.sha256(data).hexdigest(),'version':version,'routes':{}}
 for device in [0,1]:
  cmd=[str(root/'build/SwiftPM/debug/RewriteProbe'),'--inspect',str(path),'--device-index',str(device)]
  p=subprocess.run(cmd,capture_output=True,text=True,check=True);(out/f'{name}-device-{device}.json').write_text(p.stdout);probe=json.loads(p.stdout)
  fs=[f for f in frames if f['device']==device]
  assert len(fs)==probe['frames'] and sum(len(f['contacts']) for f in fs)==probe['activeSamples']
  previous=set();transitions=[];hist=collections.Counter();runs=[];last_signature=None
  for f in fs:
   ids={c['id'] for c in f['contacts']};labels={c['id']:c.get('telemetry',{}).get('fingerID') for c in f['contacts']}
   hist.update(labels.values())
   if ids!=previous:
    transitions.append({'time':f['t'],'sourceTime':f['sourceTime'],'sequence':f['sequence'],'active':sorted(ids),'joined':sorted(ids-previous),'left':sorted(previous-ids),'labels':labels})
   sig=tuple(sorted(labels.items()))
   if sig!=last_signature:
    runs.append({'start':f['t'],'lastObserved':f['t'],'labels':labels,'samples':1});last_signature=sig
   else:runs[-1]['lastObserved']=f['t'];runs[-1]['samples']+=1
   previous=ids
  result['routes'][str(device)]={'frames':len(fs),'active_samples':probe['activeSamples'],'peak':probe['peakContacts'],'lifetimes':len(probe['lifetimes']),'identity_revisions':len(probe['identityRevisions']),'start_censored':sum(l['startCensored'] for l in probe['lifetimes']),'uncertain_lifetimes':sum(l['uncertain'] for l in probe['lifetimes']),'raw_label_histogram':dict(hist),'membership_transitions':transitions,'label_runs':runs,'quality':{k:probe[k] for k in ['gaps','timestampRegressions','invalidSamples','duplicateIDs','deviceChanges']}}
 summary[name]=result
(out/'lifecycle-timelines.json').write_text(json.dumps(summary,indent=2)+'\n')
for name,j in summary.items():
 print('\n'+name)
 for device,r in j['routes'].items():
  if not r['frames']:continue
  print('device',device,'histogram',r['raw_label_histogram'],'revisions',r['identity_revisions'],'start-censored',r['start_censored'])
  for e in r['membership_transitions']:print(f"  {e['time']:7.3f}s active={e['active']} +{e['joined']} -{e['left']}")
