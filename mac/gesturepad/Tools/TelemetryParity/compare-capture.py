#!/usr/bin/env python3
"""Read-only v5 capture/native-reference comparison. Originals are never modified."""
import argparse,collections,hashlib,json,math,pathlib,struct,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parent
STATES=['notTouching','starting','hovering','making','touching','breaking','lingering','leaving']
def frames(path):
    data=path.read_bytes()
    if len(data)<20 or data[:8]!=b'ATPCAP01' or struct.unpack_from('<I',data,8)[0]!=5:
        raise ValueError('Expected v5 ATPCAP01 container')
    offset=20
    while offset<len(data):
        if offset+34>len(data):raise ValueError('Truncated record header')
        size=struct.unpack_from('<i',data,offset)[0]
        if size<0 or offset+34+size>len(data):raise ValueError('Invalid payload length')
        obj=json.loads(data[offset+34:offset+34+size]);offset+=34+size
        if obj.get('type')=='processedFrameRecord':yield obj['record']['frame']
def compare(path,oracle):
    rows=[];lines=[];skipped=0;versions=collections.Counter()
    for frame in frames(path):
        for contact in frame['rawTouches']:
            telemetry=contact.get('telemetry') or {};raw=telemetry.get('driverKit') or {}
            if raw.get('conversionVersion')!=2 or len(raw.get('contactBytes',[]))!=9:
                skipped+=1;continue
            versions[raw['conversionVersion']]+=1
            lines.append(f"{frame['deviceNumericID']} {telemetry['sourceFrame']} {telemetry['sourceTimestamp']:.17g} {int(raw['velocityAvailable'])} {bytes(raw['contactBytes']).hex()}")
            rows.append((frame,contact,telemetry))
    if not rows:raise ValueError('No conversionVersion2 raw contacts; record a new takeover capture with the updated app')
    result=subprocess.run([str(oracle),'--stream'],input='\n'.join(lines)+'\n',text=True,capture_output=True,check=True)
    expected=[json.loads(line) for line in result.stdout.splitlines()]
    if len(expected)!=len(rows):raise ValueError('Native oracle output count mismatch')
    mismatches=[];maximum=collections.defaultdict(float)
    for index,((frame,c,t),native) in enumerate(zip(rows,expected)):
        actual={'id':c['id'],'state':STATES.index(c['state']),'finger':t['fingerID'],'hand':t['handID'],
                'x':c['posX'],'y':c['posY'],'absoluteX':t['absoluteX'],'absoluteY':t['absoluteY'],
                'major':c['majorAxis'],'minor':c['minorAxis'],'total':c['total'],'pressure':c['pressure'],
                'angle':c['angle'],'density':c['density'],'vx':t['velocityX'],'vy':t['velocityY'],
                'avx':t['absoluteVelocityX'],'avy':t['absoluteVelocityY']}
        for key,value in actual.items():
            delta=abs(value-native[key]);maximum[key]=max(maximum[key],delta)
            tolerance=0 if key in ['id','state','finger','hand','pressure'] else 0.00002
            if not math.isfinite(delta) or delta>tolerance:
                mismatches.append(dict(contact=index,device=frame['deviceNumericID'],sequence=frame['sequence'],field=key,actual=value,native=native[key],delta=delta))
    return dict(capture=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),contactsCompared=len(rows),
                contactsSkipped=skipped,conversionVersions=dict(versions),mismatchCount=len(mismatches),maxAbsoluteError=dict(maximum),
                mismatches=mismatches[:100],scope='Same raw bytes and sensor timestamps through native unpack/fill/velocity functions. Safety-reset samples skip native velocity calculation; not a simultaneous native callback comparison.')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('capture',type=pathlib.Path);ap.add_argument('--out',type=pathlib.Path);args=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix='GesturePad-TelemetryParity-') as directory:
        binary=pathlib.Path(directory)/'native-reference'
        subprocess.run(['xcrun','clang',str(ROOT/'native-reference.c'),'-framework','CoreFoundation','-o',str(binary)],check=True)
        result=compare(args.capture.resolve(),binary)
    text=json.dumps(result,indent=2)+'\n'
    if args.out:args.out.write_text(text)
    print(text,end='')
    return 1 if result['mismatchCount'] else 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,subprocess.CalledProcessError) as error:raise SystemExit(str(error))
