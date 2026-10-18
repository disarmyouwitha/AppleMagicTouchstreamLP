#!/usr/bin/env python3
"""Validate Apple-issued profiles, then sign the already-built local prototype.
Never installs or activates a driver, changes SIP, or requests account credentials.
"""
import argparse,datetime,fnmatch,hashlib,pathlib,plistlib,re,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parent
BASE='ink.ranna.glasstokey.gesturepad.rawhidprobe'
def installed_identities():
    output=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
    return set(re.findall(r'\b[0-9A-F]{40}\b',output))
def load_profile(path,bundle,required):
    raw=subprocess.check_output(['security','cms','-D','-i',str(path)],stderr=subprocess.DEVNULL)
    profile=plistlib.loads(raw); ent=profile.get('Entitlements',{})
    expiry=profile.get('ExpirationDate')
    if not expiry or expiry<datetime.datetime.utcnow():raise ValueError(f'{path.name}: expired/missing expiration')
    teams=profile.get('TeamIdentifier',[])
    if len(teams)!=1:raise ValueError(f'{path.name}: ambiguous team')
    team=teams[0]
    key='com.apple.application-identifier' if 'com.apple.application-identifier' in ent else 'application-identifier'
    pattern=ent.get(key,'')
    if not fnmatch.fnmatchcase(team+'.'+bundle,pattern):raise ValueError(f'{path.name}: does not authorize {bundle}')
    for entitlement in required:
        if ent.get(entitlement) is not True:raise ValueError(f'{path.name}: missing {entitlement}')
    requested={k:True for k in required}
    requested[key]=team+'.'+bundle
    requested['com.apple.developer.team-identifier']=team
    if ent.get('get-task-allow') is True:requested['get-task-allow']=True
    certs={hashlib.sha1(c).hexdigest().upper() for c in profile.get('DeveloperCertificates',[])}
    return team,certs,requested

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--driver-profile',type=pathlib.Path);parser.add_argument('--host-profile',type=pathlib.Path);args=parser.parse_args()
    if not args.driver_profile or not args.host_profile:
        locations=[pathlib.Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles',pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles',ROOT/'profiles']
        profiles=[f for folder in locations if folder.exists() for f in folder.iterdir() if f.suffix in ['.provisionprofile','.mobileprovision']]
        print(f'Installed signing identities: {len(installed_identities())}; provisioning profiles in standard/local folders: {len(profiles)}')
        print('Required profiles:')
        print(BASE+'.driver: com.apple.developer.driverkit + com.apple.developer.driverkit.transport.hid')
        print(BASE+': com.apple.developer.system-extension.install')
        print('Supply --driver-profile FILE --host-profile FILE. No signing/install/activation performed.')
        return 2
    driver=load_profile(args.driver_profile,BASE+'.driver',['com.apple.developer.driverkit','com.apple.developer.driverkit.transport.hid'])
    host=load_profile(args.host_profile,BASE,['com.apple.developer.system-extension.install'])
    if driver[0]!=host[0]:raise ValueError('Driver and host profiles must authorize the same team')
    common=driver[1]&host[1]&installed_identities()
    if not common:raise ValueError('No installed signing identity is authorized by BOTH profiles')
    identity=sorted(common)[0]
    app=ROOT/'build/GesturePadRawHIDProbe.app'
    dext=app/'Contents/Library/SystemExtensions'/f'{BASE}.driver.dext'
    if not (dext/'AMTRawHIDReceiver').exists() or not (app/'Contents/MacOS/GesturePadRawHIDProbe').exists():raise ValueError('Build prototype first')
    for target,profile,result,name in [(dext,args.driver_profile,driver,'driver'),(app,args.host_profile,host,'host')]:
        destination=target/'embedded.provisionprofile' if name=='driver' else target/'Contents/embedded.provisionprofile'
        shutil.copyfile(profile,destination)
        ent=ROOT/f'build/{name}-approved.entitlements';ent.write_bytes(plistlib.dumps(result[2]))
        subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--entitlements',str(ent),str(target)],check=True)
        subprocess.run(['codesign','--verify','--strict','--verbose=2',str(target)],check=True)
    print(f'Signed and verified local prototype: {app}\nNot installed or activated.')
    return 0
if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,subprocess.CalledProcessError) as error:print(str(error),file=sys.stderr);sys.exit(1)
