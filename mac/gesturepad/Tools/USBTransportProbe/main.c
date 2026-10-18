// Defaults to read-only. Explicit --send-multitouch sends one exact USB feature request.
// Never seizes, detaches, resets or changes configuration.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <mach/mach_time.h>
static long number(io_service_t s, CFStringRef key) {
    CFTypeRef p = IORegistryEntryCreateCFProperty(s,key,kCFAllocatorDefault,0);
    long v=-1;
    if(p && CFGetTypeID(p)==CFNumberGetTypeID()) CFNumberGetValue(p,kCFNumberLongType,&v);
    if(p) CFRelease(p);
    return v;
}
static void probeDevice(int sendMode) {
    unsigned matched=0;
    io_iterator_t it=0;
    if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostDevice"),&it)) return;
    io_service_t s;
    while((s=IOIteratorNext(it))) {
        if(number(s,CFSTR("idVendor"))!=0x05ac || number(s,CFSTR("idProduct"))!=0x0324) { IOObjectRelease(s); continue; }
        CFTypeRef serial=IORegistryEntryCreateCFProperty(s,CFSTR("USB Serial Number"),kCFAllocatorDefault,0);
        int expected=serial && CFGetTypeID(serial)==CFStringGetTypeID() && CFEqual(serial,CFSTR("J84HMA00H0B0000501"));
        if(serial) CFRelease(serial);
        if(sendMode && !expected) { puts("Refusing write: serial differs from the tested right USB pad."); IOObjectRelease(s); continue; }
        matched++;
        IOCFPlugInInterface **plugin=NULL; SInt32 score=0;
        IOReturn r=IOCreatePlugInInterfaceForService(s,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
        printf("devicePlugin=0x%08x\n",r);
        if(r==0 && plugin) {
            IOUSBDeviceInterface **usb=NULL;
            HRESULT hr=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),(LPVOID*)&usb);
            printf("deviceQuery=0x%08x\n",(unsigned)hr);
            if(hr==0 && usb) {
                r=(*usb)->USBDeviceOpen(usb);
                printf("ordinaryDeviceOpen=0x%08x\n",r);
                if(r==0) {
                    IOUSBConfigurationDescriptorPtr config=NULL;
                    IOReturn cr=(*usb)->GetConfigurationDescriptorPtr(usb,0,&config);
                    printf("configurationDescriptor=0x%08x\n",cr);
                    if(cr==0 && config) {
                        const unsigned char *raw=(const unsigned char*)config;
                        unsigned total=raw[2]|(raw[3]<<8);
                        for(unsigned off=0;off+2<=total;) {
                            unsigned len=raw[off],type=raw[off+1];
                            if(len<2 || off+len>total) break;
                            if(type==4 && len>=9) printf("physicalInterface=%u alternate=%u endpoints=%u class=%02x subclass=%02x protocol=%02x\n",raw[off+2],raw[off+3],raw[off+4],raw[off+5],raw[off+6],raw[off+7]);
                            if(type==5 && len>=7) printf(" endpoint=%02x attributes=%02x maxPacket=%u interval=%u\n",raw[off+2],raw[off+3],raw[off+4]|(raw[off+5]<<8),raw[off+6]);
                            off+=len;
                        }
                    }
                    unsigned char bytes[4096]={0}; IOUSBDevRequest req={0};
                    req.bmRequestType=0x81; req.bRequest=6; req.wValue=0x2200;
                    req.wIndex=1; req.wLength=sizeof(bytes); req.pData=bytes;
                    r=(*usb)->DeviceRequest(usb,&req);
                    printf("deviceGetReportDescriptor=0x%08x bytes=%u\n",r,(unsigned)req.wLenDone);
                    if(r==0) { for(unsigned i=0;i<req.wLenDone && i<sizeof(bytes);i++) printf("%02x",bytes[i]); puts(""); }
                    if(!sendMode) {
                        unsigned char input[64]={0}; IOUSBDevRequestTO get={0};
                        get.bmRequestType=0xa1;get.bRequest=1;get.wValue=0x0102;
                        get.wIndex=1;get.wLength=sizeof(input);get.pData=input;
                        get.noDataTimeout=1000;get.completionTimeout=1000;
                        IOReturn gr=(*usb)->DeviceRequestTO(usb,&get);
                        printf("directGetInputReport02=0x%08x bytes=%u hex=",gr,(unsigned)get.wLenDone);
                        if(gr==0) for(unsigned j=0;j<get.wLenDone && j<sizeof(input);j++) printf("%02x",input[j]);
                        puts("");
                    }
                    if(sendMode && r==0 && req.wLenDone>=8 && bytes[0]==0x05 && bytes[1]==0x01 && bytes[2]==0x09 && bytes[3]==0x02) {
                        puts("Direct USB mode request in 2 seconds. No reset, detach, or interrupt-pipe access."); fflush(stdout);
                        sleep(2);
                        const char *expectedMarker=getenv("GESTUREPAD_CAPTURE_MARKER");
                        if(expectedMarker) {
                            char current[512]={0}; FILE *f=fopen("/tmp/GesturePad-active-usb-capture.txt","r");
                            if(f) { fread(current,1,sizeof(current)-1,f); fclose(f); }
                            if(strcmp(current,expectedMarker)!=0) {
                                puts("Capture ended or changed; direct USB command cancelled.");
                                (*usb)->USBDeviceClose(usb); (*usb)->Release(usb);
                                IODestroyPlugInInterface(plugin); IOObjectRelease(s); continue;
                            }
                        }
                        unsigned char mode[2]={0x02,0x01}; IOUSBDevRequestTO set={0};
                        set.bmRequestType=0x21; set.bRequest=0x09; set.wValue=0x0302;
                        set.wIndex=1; set.wLength=2; set.pData=mode;
                        set.noDataTimeout=1000; set.completionTimeout=1000;
                        struct timespec stamp; clock_gettime(CLOCK_REALTIME,&stamp);
                        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
                        printf("SET_REPORT uptime=%.9f\n",(double)mach_absolute_time()*tb.numer/tb.denom/1e9);
                        printf("SET_REPORT unix=%lld.%09ld interface=1 feature=02 bytes=0201\n",(long long)stamp.tv_sec,stamp.tv_nsec); fflush(stdout);
                        r=(*usb)->DeviceRequestTO(usb,&set);
                        printf("directUSBSetReport=0x%08x bytes=%u\n",r,(unsigned)set.wLenDone);
                    }
                    printf("deviceClose=0x%08x\n",(*usb)->USBDeviceClose(usb));
                }
                (*usb)->Release(usb);
            }
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if(!matched) puts("No eligible physical USB device found; no write sent.");
}
int main(int argc, char **argv) {
    int sendMode=argc==2 && strcmp(argv[1],"--send-multitouch")==0;
    if(argc>1 && !sendMode) { fputs("Usage: USBTransportProbe [--send-multitouch]\n",stderr); return 2; }
    probeDevice(sendMode);
    if(sendMode) return 0;
    io_iterator_t it=0;
    kern_return_t r=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&it);
    if(r) { printf("enumeration=0x%08x\n",r); return 1; }
    unsigned found=0; io_service_t s;
    while((s=IOIteratorNext(it))) {
        if(number(s,CFSTR("idVendor"))!=0x05ac || number(s,CFSTR("idProduct"))!=0x0324 || number(s,CFSTR("bInterfaceNumber"))!=1) { IOObjectRelease(s); continue; }
        found++;
        uint64_t rid=0; IORegistryEntryGetRegistryEntryID(s,&rid);
        printf("USB 05ac:0324 interface=1 registry=%llu\n",(unsigned long long)rid);
        IOCFPlugInInterface **plugin=NULL; SInt32 score=0;
        r=IOCreatePlugInInterfaceForService(s,kIOUSBInterfaceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
        printf("createPlugin=0x%08x\n",r);
        if(r==0 && plugin) {
            IOUSBInterfaceInterface **usb=NULL;
            HRESULT hr=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),(LPVOID*)&usb);
            printf("queryInterface=0x%08x\n",(unsigned)hr);
            if(hr==0 && usb) {
                r=(*usb)->USBInterfaceOpen(usb); // ordinary open only; NEVER OpenSeize
                printf("ordinaryOpen=0x%08x\n",r);
                if(r==0) {
                    unsigned char bytes[4096]={0};
                    IOUSBDevRequest req={0};
                    req.bmRequestType=0x81; req.bRequest=6; // GET_DESCRIPTOR, interface recipient
                    req.wValue=0x2200; req.wIndex=1; req.wLength=sizeof(bytes); req.pData=bytes;
                    r=(*usb)->ControlRequest(usb,0,&req);
                    printf("getReportDescriptor=0x%08x bytes=%u\n",r,(unsigned)req.wLenDone);
                    if(r==0) { for(unsigned i=0;i<req.wLenDone && i<sizeof(bytes);i++) printf("%02x",bytes[i]); puts(""); }
                    printf("close=0x%08x\n",(*usb)->USBInterfaceClose(usb));
                }
                (*usb)->Release(usb);
            }
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if(!found) puts("No matching USB trackpad interface connected.");
    return found ? 0 : 2;
}
