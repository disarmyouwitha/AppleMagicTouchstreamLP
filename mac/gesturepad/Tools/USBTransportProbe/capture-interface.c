// Explicit 15s exclusive USB-interface capture. No driver detach, reset or mode writes.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
static volatile sig_atomic_t interrupted=0;
static void stop(int sig) { (void)sig; interrupted=1; }
static double uptime(void) {
    mach_timebase_info_data_t t; mach_timebase_info(&t);
    return (double)mach_absolute_time()*t.numer/t.denom/1e9;
}
static long number(io_service_t s, CFStringRef key) {
    CFTypeRef p=IORegistryEntryCreateCFProperty(s,key,kCFAllocatorDefault,0);long v=-1;
    if(p && CFGetTypeID(p)==CFNumberGetTypeID()) CFNumberGetValue(p,kCFNumberLongType,&v);
    if(p) CFRelease(p);return v;
}
static int rightPad(io_service_t s) {
    if(number(s,CFSTR("idVendor"))!=0x05ac || number(s,CFSTR("idProduct"))!=0x0324 || number(s,CFSTR("bInterfaceNumber"))!=1) return 0;
    CFTypeRef p=IORegistryEntryCreateCFProperty(s,CFSTR("USB Serial Number"),kCFAllocatorDefault,0);
    int ok=p && CFGetTypeID(p)==CFStringGetTypeID() && CFEqual(p,CFSTR("J84HMA00H0B0000501"));
    if(p) CFRelease(p);return ok;
}
struct Packet { double time; unsigned length; unsigned char bytes[4096]; };
static struct {
    IOUSBInterfaceInterface300 **usb; UInt8 pipe; int active;
    unsigned char buffer[4096]; struct Packet packets[2048];
    unsigned count,dropped; IOReturn error;
} capture;
static void completed(void *context, IOReturn result, void *arg0);
static void queueRead(void) {
    IOReturn r=(*capture.usb)->ReadPipeAsync(capture.usb,capture.pipe,capture.buffer,sizeof(capture.buffer),completed,NULL);
    if(r) { capture.error=r;capture.active=0; }
}
static void completed(void *context, IOReturn result, void *arg0) {
    (void)context;
    if(!capture.active) return;
    if(result) { capture.error=result;capture.active=0;return; }
    unsigned long length=(uintptr_t)arg0;
    if(length>sizeof(capture.buffer)) { capture.error=kIOReturnOverrun;capture.active=0;return; }
    if(capture.count<2048) {
        struct Packet *p=&capture.packets[capture.count++];
        p->time=uptime();p->length=(unsigned)length;memcpy(p->bytes,capture.buffer,length);
    } else capture.dropped++;
    queueRead();
}
int main(int argc,char **argv) {
    if(argc!=2 || strcmp(argv[1],"--capture-right-usb")!=0) {
        fputs("Usage: USBInterfaceCapture --capture-right-usb\n",stderr);return 2;
    }
    signal(SIGINT,stop);signal(SIGTERM,stop);
    io_iterator_t it=0;
    IOReturn r=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&it);
    if(r) { printf("enumeration=0x%08x\n",r);return 1; }
    io_service_t service=0,s;
    while((s=IOIteratorNext(it))) { if(rightPad(s)) { service=s;break; } IOObjectRelease(s); }
    IOObjectRelease(it);
    if(!service) { puts("Exact right USB pad/interface not found; nothing opened.");return 1; }
    IOCFPlugInInterface **plugin=NULL;SInt32 score=0;
    r=IOCreatePlugInInterfaceForService(service,kIOUSBInterfaceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
    IOObjectRelease(service);
    if(r || !plugin) { printf("plugin=0x%08x\n",r);return 1; }
    HRESULT hr=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),(LPVOID*)&capture.usb);
    IODestroyPlugInInterface(plugin);
    if(hr || !capture.usb) { printf("query=0x%08x\n",(unsigned)hr);return 1; }
    r=(*capture.usb)->USBInterfaceOpenSeize(capture.usb);
    printf("USBInterfaceOpenSeize=0x%08x\n",r);fflush(stdout);
    if(r) { (*capture.usb)->Release(capture.usb);return 1; }
    CFRunLoopSourceRef source=NULL;
    r=(*capture.usb)->CreateInterfaceAsyncEventSource(capture.usb,&source);
    if(r==0 && source) {
        UInt8 pipes=0;(*capture.usb)->GetNumEndpoints(capture.usb,&pipes);
        for(UInt8 pipe=1;pipe<=pipes;pipe++) {
            UInt8 dir=0,num=0,type=0,interval=0;UInt16 max=0;
            r=(*capture.usb)->GetPipeProperties(capture.usb,pipe,&dir,&num,&type,&max,&interval);
            if(r==0 && dir==kUSBIn && num==3 && type==kUSBInterrupt && max==64) { capture.pipe=pipe;break; }
        }
        if(capture.pipe) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
            capture.active=1;double start=uptime();
            printf("Capturing endpoint83 for15s; startUptime=%.9f. Move one/two fingers. Ctrl-C releases early.\n",start);fflush(stdout);
            queueRead();
            while(capture.active && !interrupted && uptime()-start<15) CFRunLoopRunInMode(kCFRunLoopDefaultMode,.05,false);
            capture.active=0;
            (*capture.usb)->AbortPipe(capture.usb,capture.pipe);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,.05,false);
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
        } else puts("Expected endpoint83 not found; no pipe read.");
    } else printf("asyncSource=0x%08x\n",r);
    printf("USBInterfaceClose=0x%08x\n",(*capture.usb)->USBInterfaceClose(capture.usb));
    if(source) CFRelease(source);
    (*capture.usb)->Release(capture.usb);
    printf("reports=%u dropped=%u readError=0x%08x\n",capture.count,capture.dropped,capture.error);
    for(unsigned i=0;i<capture.count;i++) {
        struct Packet *p=&capture.packets[i];printf("packet uptime=%.9f length=%u hex=",p->time,p->length);
        for(unsigned j=0;j<p->length;j++) printf("%02x",p->bytes[j]);puts("");
    }
    return capture.error || !capture.pipe ? 1 : 0;
}
