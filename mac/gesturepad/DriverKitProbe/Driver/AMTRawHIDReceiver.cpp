#include "AMTRawHIDReceiver.h"
#include "MultitouchMode.h"
#include <DriverKit/IOLib.h>
#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOMemoryMap.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/OSString.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSBoolean.h>
#include <os/log.h>
#include <time.h>


// Wire layout v1, little-endian x86_64. Fixed ring keeps callback work bounded.
struct StreamRecord { uint64_t sequence, timestampNS; uint32_t length, reportID; uint8_t payload[148]; uint32_t reserved; };
static_assert(sizeof(StreamRecord)==176,"wire record size");
struct AMTRawHIDReceiver_IVars {
    IOHIDInterface *interface;
    OSAction *reportAction, *timerAction;
    IOTimerDispatchSource *timer;
    bool opened, modeAttempted, usb, stopping;
    char serial[128];
    uint64_t callbacks, started, sequence;
    StreamRecord ring[64];
    uint32_t modeResult;
    uint64_t reports, bytes, malformed, mappingErrors;
    uint64_t lengths[65];
    uint8_t firstFull[64];
    uint32_t firstFullLength;
    uint32_t firstReportID, firstReportLength;
    uint8_t firstReport[32];
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
    auto fail=[this,provider](kern_return_t error) {
        // Failed startup needs the same asynchronous drain as device removal.
        // Releasing a just-cancelled timer here races its cancellation callback.
        Stop_Impl(provider);
        return error;
    };
    OSDictionary *properties=nullptr;
    // A status-only service reports activation even with zero connected pads.
    // It exposes no user client and never opens a pad.
    if(!CopyProperties(&properties) && properties) {
        auto coordinator=OSDynamicCast(OSBoolean,properties->getObject("AMTCoordinator"));
        bool isCoordinator=coordinator == kOSBooleanTrue;
        properties->release();properties=nullptr;
        if(isCoordinator) {
            auto p=OSDictionary::withCapacity(2);
            if(!p) return fail(kIOReturnNoMemory);
            put(p,"StreamBuild",22);put(p,"StreamCoordinator",1);SetProperties(p);p->release();
            r=RegisterService();if(r) return fail(r);
            return kIOReturnSuccess;
        }
    }
    r=provider->CopyProperties(&properties);
    if(r || !properties) return fail(kIOReturnNotPermitted);
    ivars->usb=number(properties,"VendorID")==1452 && stringIs(properties,"Transport","USB");
    bool bluetooth=number(properties,"VendorID")==76 && stringIs(properties,"Transport","Bluetooth");
    auto serial=OSDynamicCast(OSString,properties->getObject("SerialNumber"));
    bool allowed=(ivars->usb || bluetooth) && number(properties,"ProductID")==804 &&
        number(properties,"PrimaryUsagePage")==1 && number(properties,"PrimaryUsage")==2 &&
        serial && serial->getLength()>0 && serial->getLength()<sizeof(ivars->serial);
    if(allowed) strlcpy(ivars->serial,serial->getCStringNoCopy(),sizeof(ivars->serial));
    properties->release();if(!allowed) return fail(kIOReturnNotPermitted);
    ivars->interface=OSDynamicCast(IOHIDInterface,provider);
    if(!ivars->interface) return fail(kIOReturnBadArgument);
    ivars->interface->retain();
    r=CreateActionInputReport(0,&ivars->reportAction);if(r) return fail(r);
    r=CreateActionExpired(0,&ivars->timerAction);if(r) return fail(r);
    IODispatchQueue *queue=nullptr;
    r=CopyDispatchQueue(kIOServiceDefaultQueueName,&queue);if(r) return fail(r);
    r=IOTimerDispatchSource::Create(queue,&ivars->timer);queue->release();if(r) return fail(r);
    r=ivars->timer->SetHandler(ivars->timerAction);if(r) return fail(r);
    r=ivars->timer->SetEnable(true);if(r) return fail(r);
    // A report pool must exist before delivery; seed it before Open.
    for(unsigned i=0;i<4;i++) {
        IOBufferMemoryDescriptor *pool=nullptr;
        r=IOBufferMemoryDescriptor::Create(kIOMemoryDirectionOutIn,4096,0,&pool);
        if(r) return fail(r);
        r=pool->SetLength(4096);
        if(!r) r=ivars->interface->AddReportToPool(pool);
        pool->release();if(r) return fail(r);
    }
    // Ordinary interface open only. Do not combine with IOHIDDevice seizure.
    r=ivars->interface->Open(this,0,ivars->reportAction);
    if(r) return fail(r);
    ivars->opened=true;
    auto now=clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    ivars->started=now;
    r=ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,now+16000000ULL,0);
    if(r) return fail(r);
    os_log(OS_LOG_DEFAULT,"AMTRawHIDReceiver build22 started continuous integrated stream receiver");
    r=RegisterService();
    if(r) return fail(r);
    return r;
}
void IMPL(AMTRawHIDReceiver, InputReport) {
    (void)timestamp;(void)action;
    ivars->callbacks++;
    if(!ivars->opened || type!=kIOHIDReportTypeInput) return;
    ivars->reports++;ivars->bytes+=reportLength;
    if(reportLength<=64) ivars->lengths[reportLength]++;
    if(!ivars->firstReportLength && reportLength>0) {
        auto length=reportLength<32?reportLength:32;
        IOMemoryMap *sample=nullptr;
        auto result=report->CreateMapping(0,0,0,length,0,&sample);
        if(!result && sample && sample->GetLength()>=length) {
            memcpy(ivars->firstReport,reinterpret_cast<void*>(sample->GetAddress()),length);
            ivars->firstReportID=reportID;ivars->firstReportLength=length;
        }
        OSSafeReleaseNULL(sample);
    }
    bool full=(reportID==2 && ivars->usb && reportLength>=12 && reportLength<=147 && (reportLength-12)%9==0) ||
        (reportID==0x31 && !ivars->usb && reportLength>=4 && reportLength<=139 && (reportLength-4)%9==0);
    if(full) {
        IOMemoryMap *map=nullptr;
        auto r=report->CreateMapping(0,0,0,reportLength,0,&map);
        if(!r && map && map->GetLength()>=reportLength) {
            auto &record=ivars->ring[ivars->sequence%64];
            record.sequence=++ivars->sequence;
            record.timestampNS=clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
            record.length=reportLength;record.reportID=reportID;
            memcpy(record.payload,reinterpret_cast<void*>(map->GetAddress()),reportLength);
            if(!ivars->firstFullLength && reportLength<=64) {
                memcpy(ivars->firstFull,record.payload,reportLength);ivars->firstFullLength=reportLength;
            }
        } else ivars->mappingErrors++;
        OSSafeReleaseNULL(map);
    } else ivars->malformed++;
    // Return shared buffers to the provider pool, not retained per packet.
    auto pool=OSDynamicCast(IOBufferMemoryDescriptor,report);
    if(pool) ivars->interface->AddReportToPool(pool);
}
void IMPL(AMTRawHIDReceiver, Expired) {
    (void)action;(void)time;
    if(!ivars->opened) return;
    auto now=clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    if(!ivars->modeAttempted && now-ivars->started>=2000000000ULL && (ivars->usb || ivars->sequence==0)) {
        ivars->modeAttempted=true;
        IOBufferMemoryDescriptor *command=nullptr;IOMemoryMap *map=nullptr;
        // Bluetooth's macOS keyhole transport adds F1. Do not include that
        // prefix in the payload, or the device receives F1 F1 02 01.
        const auto mode=AMTMultitouchMode(ivars->usb);
        const uint32_t length=sizeof(mode.payload);
        auto result=IOBufferMemoryDescriptor::Create(kIOMemoryDirectionOutIn,length,0,&command);
        if(!result) result=command->SetLength(length);
        if(!result) result=command->CreateMapping(0,0,0,length,0,&map);
        if(!result && map && map->GetLength()>=length) {
            auto bytes=reinterpret_cast<uint8_t*>(map->GetAddress());
            memcpy(bytes,mode.payload,length);
            result=ivars->interface->SetReport(command,kIOHIDReportTypeFeature,mode.reportID,0);
        } else if(!result) result=kIOReturnNoMemory;
        ivars->modeResult=static_cast<uint32_t>(result);
        OSSafeReleaseNULL(map);OSSafeReleaseNULL(command);
    }
    Publish();
    auto r=ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,now+16000000ULL,0);
    if(r) Finish("stream timer failed");
}
void AMTRawHIDReceiver::Publish() {
    auto p=OSDictionary::withCapacity(10);if(!p) return;
    put(p,"StreamBuild",22);put(p,"StreamSession",ivars->started);put(p,"StreamOpened",ivars->opened);
    auto transport=OSString::withCString(ivars->usb?"USB":"Bluetooth");
    if(transport) {p->setObject("StreamTransport",transport);transport->release();}
    put(p,"StreamSequence",ivars->sequence);put(p,"StreamReports",ivars->reports);
    put(p,"StreamModeAttempted",ivars->modeAttempted);put(p,"StreamModeResult",ivars->modeResult);
    put(p,"StreamFirstReportID",ivars->firstReportID);put(p,"StreamFirstReportLength",ivars->firstReportLength);
    if(ivars->firstReportLength) {
        auto sample=OSData::withBytes(ivars->firstReport,ivars->firstReportLength);
        if(sample) {p->setObject("StreamFirstReport",sample);sample->release();}
    }
    put(p,"StreamMalformed",ivars->malformed);put(p,"StreamMappingErrors",ivars->mappingErrors);
    auto serial=OSString::withCString(ivars->serial);
    if(serial) {p->setObject("StreamSerial",serial);serial->release();}
    auto data=OSData::withBytes(ivars->ring,sizeof(ivars->ring));
    if(data) {p->setObject("StreamBatch",data);data->release();}
    SetProperties(p);p->release();
}
void AMTRawHIDReceiver::Finish(const char *reason) {
    if(!ivars->opened) return;
    ivars->opened=false;
    auto closeResult=ivars->interface->Close(this,0);
    ivars->timer->SetEnable(false);
    Publish();
    auto p=OSDictionary::withCapacity(12);
    if(p) {
        put(p,"ProbeBuild",22);put(p,"Callbacks",ivars->callbacks);put(p,"ModeAttempted",ivars->modeAttempted);
        put(p,"ModeResult",ivars->modeResult);put(p,"Reports",ivars->reports);put(p,"Bytes",ivars->bytes);
        put(p,"Reports13",ivars->lengths[13]);put(p,"Reports22",ivars->lengths[22]);
        put(p,"Reports31",ivars->lengths[31]);put(p,"Reports40",ivars->lengths[40]);
        put(p,"Reports8",ivars->lengths[8]);put(p,"Reports21",ivars->lengths[21]);
        put(p,"Reports30",ivars->lengths[30]);put(p,"Reports39",ivars->lengths[39]);
        put(p,"Reports48",ivars->lengths[48]);put(p,"FirstFullLength",ivars->firstFullLength);
        put(p,"Malformed",ivars->malformed);put(p,"MappingErrors",ivars->mappingErrors);
        put(p,"CloseResult",static_cast<uint32_t>(closeResult));
        if(ivars->firstFullLength) {
            auto data=OSData::withBytes(ivars->firstFull,ivars->firstFullLength);
            if(data) {p->setObject("FirstFullReport",data);data->release();}
        }
        SetProperties(p);p->release();
    }
    os_log(OS_LOG_DEFAULT,"AMTRawHIDReceiver finished %{public}s reports=%llu fullLength=%u close=%x",reason,ivars->reports,ivars->firstFullLength,closeResult);
}
kern_return_t IMPL(AMTRawHIDReceiver, Stop) {
    if(ivars->stopping) return kIOReturnSuccess;
    ivars->stopping=true;
    Finish("stop");
    if(ivars->timer) ivars->timer->SetEnable(false);
    // Do not acknowledge Stop until every source/action has drained. DriverKit's
    // timer Cancel handler dereferences the timer before calling our completion;
    // calling super immediately can finalize/free it before that handler runs.
    // Retain this receiver (and therefore its timer/actions) across the entire
    // drain, including startup failures and physical Bluetooth disconnection.
    retain();
    provider->retain();
    auto complete=^{
        os_log(OS_LOG_DEFAULT,"AMT receiver cancellation drained: usb=%d",ivars->usb);
        Stop(provider,SUPERDISPATCH);
        provider->release();
        release();
    };
    auto cancelReports=^{
        if(ivars->reportAction) ivars->reportAction->Cancel(complete);
        else complete();
    };
    auto cancelActions=^{
        if(ivars->timerAction) ivars->timerAction->Cancel(cancelReports);
        else cancelReports();
    };
    if(ivars->timer) {
        auto result=ivars->timer->Cancel(cancelActions);
        // A failed cancellation cannot safely proceed to destruction.
        if(result) os_log(OS_LOG_DEFAULT,"AMT timer cancellation failed: %x",result);
        return result;
    }
    cancelActions();
    return kIOReturnSuccess;
}
