#include "AMTHandoffClient.h"
#include "AMTRawHIDReceiver.h"
#include <DriverKit/IOLib.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSString.h>
struct AMTHandoffClient_IVars { AMTRawHIDReceiver *receiver; };
bool AMTHandoffClient::init() {
    if(!super::init()) return false;
    ivars=static_cast<AMTHandoffClient_IVars*>(IOMallocZero(sizeof(*ivars)));
    return ivars!=nullptr;
}
void AMTHandoffClient::free() {
    if(ivars) { OSSafeReleaseNULL(ivars->receiver); IOFree(ivars,sizeof(*ivars)); }
    super::free();
}
kern_return_t IMPL(AMTHandoffClient, Start) {
    auto r=Start(provider,SUPERDISPATCH); if(r) return r;
    // Same-team default plus exact signed helper application identity.
    OSDictionary *entitlements=nullptr;
    r=CopyClientEntitlements(&entitlements);
    if(r || !entitlements) return kIOReturnNotPermitted;
    auto identity=OSDynamicCast(OSString,entitlements->getObject("com.apple.application-identifier"));
    bool allowed=identity && identity->isEqualTo("N9XQZJR4EP.ink.ranna.glasstokey.gesturepad.rawhidprobe");
    entitlements->release(); if(!allowed) return kIOReturnNotPermitted;
    ivars->receiver=OSDynamicCast(AMTRawHIDReceiver,provider);
    if(!ivars->receiver) return kIOReturnBadArgument;
    ivars->receiver->retain(); return kIOReturnSuccess;
}
kern_return_t AMTHandoffClient::ExternalMethod(uint64_t selector, IOUserClientMethodArguments *arguments,
    const IOUserClientMethodDispatch *dispatch, OSObject *target, void *reference) {
    (void)dispatch;(void)target;(void)reference;
    if(selector!=0 || !arguments || arguments->scalarInputCount!=1 ||
       arguments->scalarOutputCount!=0 || arguments->structureInput || arguments->structureOutput ||
       arguments->completion || !ivars->receiver) return kIOReturnBadArgument;
    auto operation=arguments->scalarInput[0];
    if(!((operation>=1 && operation<=7) || (operation>=16 && operation<48))) return kIOReturnBadArgument;
    return ivars->receiver->Handoff(arguments->scalarInput[0]);
}
