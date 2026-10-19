import json,pathlib,plistlib,sys
app,dext=map(pathlib.Path,sys.argv[1:])
config=json.loads((pathlib.Path(__file__).parent/'takeover-config.json').read_text())
base=config['helperBundleID']
def write(p,v):
 if 'IOKitPersonalities' in v:
  for personality in v['IOKitPersonalities'].values():
   personality['IOUserServerOneProcess']=True
 p.write_bytes(plistlib.dumps(v,sort_keys=True))
write(app/'Contents/Info.plist',dict(CFBundleIdentifier=base,CFBundleExecutable=config['helperExecutable'],CFBundleName='GlassToKey Driver Service',CFBundleDisplayName='GlassToKey',LSUIElement=True,CFBundlePackageType='APPL',CFBundleVersion=str(config['driverBuild']),CFBundleShortVersionString=config['driverVersion'],LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True))
write(dext/'Info.plist',dict(CFBundleIdentifier=config['driverBundleID'],CFBundleExecutable=config['driverExecutable'],CFBundleName='AMT Raw HID Receiver',CFBundlePackageType='DEXT',CFBundleVersion=str(config['driverBuild']),CFBundleShortVersionString=config['driverVersion'],CFBundleSupportedPlatforms=['DriverKit'],OSMinimumDriverKitVersion='20.0',OSBundleUsageDescription='Temporarily receive raw contact reports from all connected supported USB and Bluetooth Magic Trackpads until released by GlassToKey.',IOKitPersonalities={'Session coordinator':dict(CFBundleIdentifier=config['driverBundleID'],IOProviderClass='IOUserResources',IOResourceMatch='IOKit',IOMatchCategory=config['driverBundleID']+'.coordinator',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=config['driverBundleID'],AMTCoordinator=True),'Magic Trackpad2 USB receiver':dict(CFBundleIdentifier=config['driverBundleID'],IOProviderClass='IOHIDInterface',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=config['driverBundleID'],IOProbeScore=1000,VendorID=1452,ProductID=804,PrimaryUsagePage=1,PrimaryUsage=2,Transport='USB'),'Magic Trackpad2 Bluetooth receiver':dict(CFBundleIdentifier=config['driverBundleID'],IOProviderClass='IOHIDInterface',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=config['driverBundleID'],IOProbeScore=1000,VendorID=76,ProductID=804,PrimaryUsagePage=1,PrimaryUsage=2,Transport='Bluetooth')}))
write(pathlib.Path(__file__).parent/'Driver/Driver.entitlements',{'com.apple.developer.driverkit':True,'com.apple.developer.driverkit.transport.hid':True})
write(pathlib.Path(__file__).parent/'Host/Host.entitlements',{'com.apple.developer.system-extension.install':True})
