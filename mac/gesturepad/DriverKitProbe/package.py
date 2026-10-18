import pathlib,plistlib,sys
app,dext=map(pathlib.Path,sys.argv[1:])
base='ink.ranna.glasstokey.gesturepad.rawhidprobe'
def write(p,v):p.write_bytes(plistlib.dumps(v,sort_keys=True))
write(app/'Contents/Info.plist',dict(CFBundleIdentifier=base,CFBundleExecutable='GesturePadRawHIDProbe',CFBundleName='GesturePad Raw HID Probe',CFBundlePackageType='APPL',CFBundleVersion='4',CFBundleShortVersionString='0.4',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True))
write(dext/'Info.plist',dict(CFBundleIdentifier=base+'.driver',CFBundleExecutable='AMTRawHIDReceiver',CFBundleName='AMT Raw HID Receiver',CFBundlePackageType='DEXT',CFBundleVersion='4',CFBundleShortVersionString='0.4',CFBundleSupportedPlatforms=['DriverKit'],OSMinimumDriverKitVersion='20.0',OSBundleUsageDescription='Temporarily receive raw contact reports from the selected left Bluetooth Magic Trackpad for a 15-second GesturePad diagnostic.',IOKitPersonalities={'Left Bluetooth trackpad receiver':dict(CFBundleIdentifier=base+'.driver',IOProviderClass='IOHIDInterface',IOClass='IOUserService',IOUserClass='AMTRawHIDReceiver',IOUserServerName=base+'.driver',IOProbeScore=1000,VendorID=76,ProductID=804,PrimaryUsagePage=1,PrimaryUsage=2,Transport='Bluetooth',SerialNumber='D0:C0:50:D4:75:6C')}))
write(pathlib.Path(__file__).parent/'Driver/Driver.entitlements',{'com.apple.developer.driverkit':True,'com.apple.developer.driverkit.transport.hid':True})
write(pathlib.Path(__file__).parent/'Host/Host.entitlements',{'com.apple.developer.system-extension.install':True})
