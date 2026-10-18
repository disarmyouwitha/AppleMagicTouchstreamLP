// Read-only research oracle, pinned to framework UUID B172DB85-9E88-3A4E-AB6E-B458FD373A58.
// Never part of the shipped app. No report writes, device opens/start, seizure or security changes.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
static int readself(uintptr_t address,void *out,size_t n){mach_vm_size_t done=0;return mach_vm_read_overwrite(mach_task_self(),address,n,(mach_vm_address_t)out,&done)==0&&done==n;}
int main(int argc,char **argv){
 void*h=dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_NOW);
 if(!h)return 2;
 Dl_info image;if(!dladdr(dlsym(h,"MTDeviceCreateList"),&image))return 2;
 uintptr_t base=(uintptr_t)image.dli_fbase;
 const struct mach_header_64*mh=(void*)base;const uint8_t*lc=(void*)(mh+1);
 const uint8_t expected[16]={0xb1,0x72,0xdb,0x85,0x9e,0x88,0x3a,0x4e,0xab,0x6e,0xb4,0x58,0xfd,0x37,0x3a,0x58};int verified=0;
 for(unsigned i=0;i<mh->ncmds;i++){const struct load_command*c=(void*)lc;if(c->cmd==LC_UUID)verified=!memcmp(((const struct uuid_command*)c)->uuid,expected,16);lc+=c->cmdsize;}
 if(!verified){fprintf(stderr,"Unsupported framework UUID; refusing private offsets.\n");return 3;}
 unsigned(*unpack)(void*,const void*,unsigned)=(void*)(base+0xe7b4);
 int(*density)(int,int,int,int,int)=(void*)(base+0x1ac59);
 // Assert entry prefixes as well as UUID before any private research call.
 const uint8_t unpackStart[]={0x48,0x85,0xff,0x0f,0x94,0xc0};
 if(memcmp((void*)unpack,unpackStart,sizeof(unpackStart))){fprintf(stderr,"Unexpected native entry bytes.\n");return 3;}
 if(argc==2 && strcmp(argv[1],"--stream")==0) {
  typedef struct {int frame;double timestamp;int id,state,finger,hand;float pos[4],total,pressure,angle,major,minor,absolute[4];int field14,field15;float density;} Touch;
  _Static_assert(sizeof(Touch)==96,"MTTouch layout");
  void(*fill)(const int16_t*,Touch*,const void*,uint64_t,unsigned char,double)=(void*)(base+0x16628);
  void(*velocity)(Touch*,void*,double)=(void*)(base+0x164fe);
  const int16_t bounds[4]={7869,-7356,9956,-174};
  Touch previous[2][16]={0};unsigned long long deviceIDs[2]={0};
  unsigned long long device,seq;double stamp;int useVelocity;char hex[19];
  while(scanf("%llu %llu %lf %d %18s",&device,&seq,&stamp,&useVelocity,hex)==5) {
   if(strlen(hex)!=18)return 5;
   uint8_t raw[9];for(int k=0;k<9;k++){unsigned v;if(sscanf(hex+k*2,"%2x",&v)!=1)return 5;raw[k]=v;}
   int slot=0;if(deviceIDs[0]!=device && deviceIDs[0]!=0)slot=1;
   if(deviceIDs[slot]!=device){deviceIDs[slot]=device;memset(previous[slot],0,sizeof(previous[slot]));}
   uint8_t decoded[20]={0},binary[30]={0};if(unpack(decoded,raw,9)!=8)return 5;
   int id=decoded[10];binary[0]=id;binary[1]=decoded[15];binary[2]=decoded[14];binary[3]=1;
   memcpy(binary+4,decoded,4);if(decoded[16])memset(binary+8,255,4);
   memcpy(binary+12,decoded+4,4);memcpy(binary+16,decoded+12,2);memcpy(binary+18,decoded+8,2);memcpy(binary+26,decoded+18,2);
   int16_t a,b,t;memcpy(&a,decoded+4,2);memcpy(&b,decoded+6,2);memcpy(&t,decoded+8,2);
   uint16_t d=density(t,a,b,600,430);memcpy(binary+20,&d,2);
   Touch*out=&previous[slot][id];if(useVelocity)velocity(out,binary,stamp);else memset(binary+8,0,4);
   fill(bounds,out,binary,seq,0,stamp);
   printf("{\"id\":%d,\"state\":%d,\"finger\":%d,\"hand\":%d,\"x\":%.9g,\"y\":%.9g,\"absoluteX\":%.9g,\"absoluteY\":%.9g,\"major\":%.9g,\"minor\":%.9g,\"total\":%.9g,\"pressure\":%.9g,\"angle\":%.9g,\"density\":%.9g,\"vx\":%.9g,\"vy\":%.9g,\"avx\":%.9g,\"avy\":%.9g}\n",out->id,out->state,out->finger,out->hand,out->pos[0],out->pos[1],out->absolute[0],out->absolute[1],out->major,out->minor,out->total,out->pressure,out->angle,out->density,out->pos[2],out->pos[3],out->absolute[2],out->absolute[3]);
   if(out->state==0||out->state==7)memset(out,0,sizeof(*out));
  }
  return ferror(stdin)?5:0;
 }
 printf("{\"frameworkUUID\":\"B172DB85-9E88-3A4E-AB6E-B458FD373A58\",\"scalars\":[");
 for(unsigned v=0;v<256;v++){
  uint8_t in[9]={0,0,0,0x88,v,v,v,v,0x80},out[20]={0};
  if(unpack(out,in,9)!=8)return 4;
  uint16_t a,b,t,p;memcpy(&a,out+4,2);memcpy(&b,out+6,2);memcpy(&t,out+8,2);memcpy(&p,out+18,2);
  printf("%s[%u,%u,%u,%u,%u]",v?",":"",v,a,b,t,p);
 }
 printf("],\"devices\":[");
 CFArrayRef(*list)(void)=dlsym(h,"MTDeviceCreateList");int(*getID)(void*,uint64_t*)=dlsym(h,"MTDeviceGetDeviceID");int(*dims)(void*,int*,int*)=dlsym(h,"MTDeviceGetSensorSurfaceDimensions");
 CFArrayRef devices=list();
 for(CFIndex i=0;devices&&i<CFArrayGetCount(devices);i++){
  void*device=(void*)CFArrayGetValueAtIndex(devices,i);
  // Initialize only this process's algorithm state; no MTDeviceStart or HID open.
  void(*initialize)(void*)=(void*)(base+0x4599);
  fflush(stdout);int saved=dup(STDOUT_FILENO),sink=open("/dev/null",O_WRONLY);dup2(sink,STDOUT_FILENO);
  initialize(device);fflush(stdout);dup2(saved,STDOUT_FILENO);close(saved);close(sink);int w=0,height=0;uint64_t id=0;dims(device,&w,&height);getID(device,&id);
  uintptr_t state=0;int16_t min=0,bias=0,bounds[4]={0};
  readself((uintptr_t)device+0x98,&state,sizeof(state));
  int has=state&&readself(state+0x1d6,&min,2)&&readself(state+0x1d8,&bias,2)&&readself(state+0x178,bounds,8);
  printf("%s{\"device\":%llu,\"width\":%d,\"height\":%d,\"hasState\":%s,\"densityMin\":%d,\"densityBias\":%d,\"bounds\":[%d,%d,%d,%d]}",i?",":"",id,w,height,has?"true":"false",min,bias,bounds[0],bounds[1],bounds[2],bounds[3]);
 }
 if(devices)CFRelease(devices);
 // Separate bounded oracle grid; no zero denominator.
 printf("],\"densitySamples\":[");int first=1;
 for(int t=0;t<=2048;t+=256)for(int a=100;a<=1500;a+=200)for(int b=100;b<=1500;b+=200){
  printf("%s[%d,%d,%d,%d]",first?"":",",t,a,b,density(t,a,b,600,430));first=0;
 }
 printf("],\"fillSamples\":[");
 typedef struct {int frame;double timestamp;int id,state,finger,hand;float pos[4],total,pressure,angle,major,minor,absolute[4];int field14,field15;float density;} Touch;
 _Static_assert(sizeof(Touch)==96,"MTTouch layout");
 void(*fill)(const int16_t*,Touch*,const void*,uint64_t,unsigned char,double)=(void*)(base+0x16628);
 const int16_t bounds[4]={7869,-7356,9956,-174};
 for(int v=0;v<256;v++) {
  int x=(v*29)%8192-4096,y=(v*37)%8192-4096;
  unsigned ux=x&8191,uy=y&8191;
  uint8_t raw[9]={ux&255,(ux>>8)|((uy&7)<<5),(uy>>3)&255,(uy>>11)|((v%8)<<2)|((v%8)<<5),v,255-v,(v*17)%256,(v*31)%256,(v%16)|((v%8)<<5)};
  uint8_t decoded[20]={0},binary[30]={0};unpack(decoded,raw,9);
  binary[0]=decoded[10];binary[1]=decoded[15];binary[2]=decoded[14];binary[3]=1;
  memcpy(binary+4,decoded,4);memcpy(binary+12,decoded+4,4);memcpy(binary+16,decoded+12,2);memcpy(binary+18,decoded+8,2);memcpy(binary+26,decoded+18,2);
  int16_t a,b,t;memcpy(&a,decoded+4,2);memcpy(&b,decoded+6,2);memcpy(&t,decoded+8,2);
  uint16_t d=density(t,a,b,600,430);memcpy(binary+20,&d,2);
  Touch touch={0};fill(bounds,&touch,binary,42,0,12.345);
  printf("%s{\"raw\":[",v?",":"");for(int k=0;k<9;k++)printf("%s%d",k?",":"",raw[k]);
  printf("],\"state\":%d,\"finger\":%d,\"hand\":%d,\"x\":%.9g,\"y\":%.9g,\"absoluteX\":%.9g,\"absoluteY\":%.9g,\"major\":%.9g,\"minor\":%.9g,\"total\":%.9g,\"pressure\":%.9g,\"angle\":%.9g,\"density\":%.9g}",touch.state,touch.finger,touch.hand,touch.pos[0],touch.pos[1],touch.absolute[0],touch.absolute[1],touch.major,touch.minor,touch.total,touch.pressure,touch.angle,touch.density);
 }
 printf("],\"velocitySamples\":[");
 void(*velocity)(Touch*,void*,double)=(void*)(base+0x164fe);
 int sample=0;
 for(int state=0;state<8;state++)for(int extra=0;extra<2;extra++)for(int trial=0;trial<6;trial++) {
  Touch previous={0};uint8_t binary[30]={0};binary[1]=4;binary[3]=1;
  int16_t oldX=1000,oldY=6000;memcpy(binary+4,&oldX,2);memcpy(binary+6,&oldY,2);
  fill(bounds,&previous,binary,1,0,1.0);
  const int dx[6]={0,14,-80,1000,7190,-9000},dy[6]={0,-12,92,-2000,-9000,6000};
  int x=(oldX+dx[trial])/2,y=(oldY+dy[trial]-5000)/2;
  unsigned ux=x&8191,uy=y&8191;
  uint8_t raw[9]={ux&255,(ux>>8)|((uy&7)<<5),(uy>>3)&255,(uy>>11)|(2<<2)|(state<<5),80,90,18,25,1|(extra<<4)|(4<<5)};
  uint8_t decoded[20]={0};unpack(decoded,raw,9);
  memset(binary,0,30);binary[0]=1;binary[1]=state;binary[2]=2;binary[3]=1;
  memcpy(binary+4,decoded,4);if(extra)memset(binary+8,255,4);
  memcpy(binary+12,decoded+4,4);memcpy(binary+16,decoded+12,2);memcpy(binary+18,decoded+8,2);memcpy(binary+26,decoded+18,2);
  velocity(&previous,binary,1.01);Touch out=previous;fill(bounds,&out,binary,2,0,1.01);
  printf("%s{\"raw\":[",sample++?",":"");for(int k=0;k<9;k++)printf("%s%d",k?",":"",raw[k]);
  printf("],\"state\":%d,\"vx\":%.9g,\"vy\":%.9g,\"avx\":%.9g,\"avy\":%.9g}",out.state,out.pos[2],out.pos[3],out.absolute[2],out.absolute[3]);
 }
 printf("]}\n");
}
