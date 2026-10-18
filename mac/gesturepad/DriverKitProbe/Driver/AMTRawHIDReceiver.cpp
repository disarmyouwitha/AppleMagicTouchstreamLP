#include "AMTRawHIDReceiver.h"
#include <DriverKit/IOLib.h>
#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOMemoryMap.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/OSString.h>
#include <os/log.h>
#include <time.h>

struct AMTRawHIDReceiver_IVars {
    IOHIDInterface *interface;
    OSAction *reportAction, *timerAction;
    IOTimerDispatchSource *timer;
    bool opened;
    uint64_t reports, bytes, malformed, mappingErrors;
    uint64_t lengths[65];
    uint8_t firstFull[64];
    uint32_t firstFullLength;
};
static uint64_t number(OSDictionary *p,const char *key) {
    auto n=OSDynamicCast(OSNumber,p->getObject(key)); return n?n->unsigned64BitValue():UINT64_MAX;
}
static bool stringIs(OSDictionary *p,const char *key,const char *expected) {
    auto s=OSDynamicCast(OSString,p->getObject(key)); return s && s->isEqualTo(expected);
}
static void put(OSDictionary *p,const char *key,uint64_t value) {
    auto n=OSNumber::withNumber(value,64);if(n) {p->setObject(key,n);n->release();}
}
bool AMTRawHIDReceiver::init() {
    if(!super::init()) return false;
    ivars=static_cast<AMTRawHIDReceiver_IVars*>(IOMallocZero(sizeof(AMTRawHIDReceiver_IVars))); return ivars!=nullptr;
}
void AMTRawHIDReceiver::free() {
    if(ivars) {
        OSSafeReleaseNULL(ivars->interface); OSSafeReleaseNULL(ivars->reportAction);
        OSSafeReleaseNULL(ivars->timerAction); OSSafeReleaseNULL(ivars->timer);
        IOFree(ivars,sizeof(AMTRawHIDReceiver_IVars));
    }
    super::free();
}
kern_return_t IMPL(AMTRawHIDReceiver, Start) {
    kern_return_t r=Start(provider,SUPERDISPATCH);if(r) return r;
    OSDictionary *properties=nullptr;
    r=provider->CopyProperties(&properties);
    if(r || !properties) return kIOReturnNotPermitted;
    bool allowed=number(properties,"VendorID")==1452 && number(properties,"ProductID")==804 &&
        number(properties,"PrimaryUsagePage")==1 && number(properties,"PrimaryUsage")==2 &&
        stringIs(properties,"Transport","USB") && stringIs(properties,"SerialNumber","J84HMA00H0B0000501");
    properties->release();if(!allowed) return kIOReturnNotPermitted;
    ivars->interface=OSDynamicCast(IOHIDInterface,provider);
    if(!ivars->interface) return kIOReturnBadArgument;
    ivars->interface->retain();
    r=CreateActionInputReport(0,&ivars->reportAction);if(r) return r;
    r=CreateActionExpired(0,&ivars->timerAction);if(r) return r;
    IODispatchQueue *queue=nullptr;
    r=CopyDispatchQueue(kIOServiceDefaultQueueName,&queue);if(r) return r;
    r=IOTimerDispatchSource::Create(queue,&ivars->timer);queue->release();if(r) return r;
    r=ivars->timer->SetHandler(ivars->timerAction);if(r) return r;
    r=ivars->timer->SetEnable(true);if(r) return r;
    // Ordinary interface open only. Do not combine with IOHIDDevice seizure.
    r=ivars->interface->Open(this,0,ivars->reportAction);
    if(r) {ivars->timer->Cancel(nullptr);return r;}
    ivars->opened=true;
    r=ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)+15ULL*1000000000ULL,0);
    if(r) {Finish("timer failure");return r;}
    os_log(OS_LOG_DEFAULT,"AMTRawHIDReceiver started15s receiver");
    return RegisterService();
}
void IMPL(AMTRawHIDReceiver, InputReport) {
    (void)timestamp;(void)action;
    if(!ivars->opened || type!=kIOHIDReportTypeInput) return;
    ivars->reports++;ivars->bytes+=reportLength;
    if(reportLength<=64) ivars->lengths[reportLength]++;
    if(reportID==2 && reportLength>=12 && reportLength<=64 && (reportLength-12)%9==0) {
        if(!ivars->firstFullLength) {
            IOMemoryMap *map=nullptr;
            auto r=report->CreateMapping(0,0,0,reportLength,0,&map);
            if(!r && map && map->GetLength()>=reportLength) {
                memcpy(ivars->firstFull,reinterpret_cast<void*>(map->GetAddress()),reportLength);
                ivars->firstFullLength=reportLength;
            } else ivars->mappingErrors++;
            OSSafeReleaseNULL(map);
        }
    } else ivars->malformed++;
    // Return shared buffers to the provider pool, not retained per packet.
    auto pool=OSDynamicCast(IOBufferMemoryDescriptor,report);
    if(pool) ivars->interface->AddReportToPool(pool);
}
void IMPL(AMTRawHIDReceiver, Expired) { (void)action;(void)time;Finish("15s complete"); }
void AMTRawHIDReceiver::Finish(const char *reason) {
    if(!ivars->opened) return;
    ivars->opened=false;
    auto closeResult=ivars->interface->Close(this,0);
    ivars->timer->SetEnable(false);
    auto p=OSDictionary::withCapacity(12);
    if(p) {
        put(p,"Reports",ivars->reports);put(p,"Bytes",ivars->bytes);
        put(p,"Reports8",ivars->lengths[8]);put(p,"Reports21",ivars->lengths[21]);
        put(p,"Reports30",ivars->lengths[30]);put(p,"Reports39",ivars->lengths[39]);
        put(p,"Reports48",ivars->lengths[48]);put(p,"FirstFullLength",ivars->firstFullLength);
        put(p,"Malformed",ivars->malformed);put(p,"MappingErrors",ivars->mappingErrors);
        put(p,"CloseResult",static_cast<uint32_t>(closeResult));SetProperties(p);p->release();
    }
    os_log(OS_LOG_DEFAULT,"AMTRawHIDReceiver finished %{public}s reports=%llu fullLength=%u close=%x",reason,ivars->reports,ivars->firstFullLength,closeResult);
}
kern_return_t IMPL(AMTRawHIDReceiver, Stop) {
    Finish("stop");if(ivars->timer) ivars->timer->Cancel(nullptr);
    return Stop(provider,SUPERDISPATCH);
}
