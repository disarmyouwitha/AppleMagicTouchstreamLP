import pathlib,plistlib,sys
app,dext=map(pathlib.Path,sys.argv[1:])
base='ink.ranna.glasstokey.gesturepad.rawhidprobe'
def write(p,v):
 if 'IOKitPersonalities' in v:
  for personality in v['IOKitPersonalities'].values():
   personality['IOUserServerOneProcess']=True
 p.write_bytes(plistlib.dumps(v,sort_keys=True))
write(app/'Contents/Info.plist',dict(CFBundleIdentifier=base,CFBundleExecutable='GesturePadRawHIDProbe',CFBundleName='GesturePad Driver Service',CFBundleDisplayName='GesturePad',LSUIElement=True,CFBundlePackageType='APPL',CFBundleVersion='22',CFBundleShortVersionString='0.22',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True))
write(dext/'Info.plist',dict(CFBundleIdentifier=base+'.driver',CFBundleExecutable='AMTRawHIDReceiver',CFBundleName='AMT Raw HID Receiver',CFBundlePackageType='DEXT',CFBundleVersion='22',CFBundleShortVersionString='0.22',CFBundleSupportedPlatforms=['DriverKit'],OSMinimumDriverKitVersion='20.0',OSBundleUsageDescription='Temporarily receive raw contact reports from all connected supported USB and Bluetooth Magic Trackpads until released by GesturePad.',IOKitPersonalities={'Session coordinator':dict(CFBundleIdentifier=base+'.driver',IOProviderClass='IOUserResources',IOResourceMatch='IOKit',IOMatchCategory=base+'.driver.coordinator',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=base+'.driver',AMTCoordinator=True),'Magic Trackpad2 USB receiver':dict(CFBundleIdentifier=base+'.driver',IOProviderClass='IOHIDInterface',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=base+'.driver',IOProbeScore=1000,VendorID=1452,ProductID=804,PrimaryUsagePage=1,PrimaryUsage=2,Transport='USB'),'Magic Trackpad2 Bluetooth receiver':dict(CFBundleIdentifier=base+'.driver',IOProviderClass='IOHIDInterface',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=base+'.driver',IOProbeScore=1000,VendorID=76,ProductID=804,PrimaryUsagePage=1,PrimaryUsage=2,Transport='Bluetooth')}))
write(pathlib.Path(__file__).parent/'Driver/Driver.entitlements',{'com.apple.developer.driverkit':True,'com.apple.developer.driverkit.transport.hid':True})
write(pathlib.Path(__file__).parent/'Host/Host.entitlements',{'com.apple.developer.system-extension.install':True})
