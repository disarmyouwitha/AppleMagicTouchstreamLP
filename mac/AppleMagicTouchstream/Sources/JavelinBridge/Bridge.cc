#include "include/JavelinBridge.h"
#include "Vendor/engine.h"
#include "Vendor/dictionary/dictionary.h"
#include "Vendor/system.h"
#include "Vendor/key.h"
#include <string>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <stdexcept>

// Host-only adapter. Firmware scripts and raw key commands are excluded by the
// dictionary loader; Unicode edits are returned to AMT's gated output queue.
struct HostEdit { size_t removed = 0; std::vector<uint32_t> text; };
static thread_local HostEdit *activeEdit = nullptr;
JavelinStaticAllocate<StenoEngine> StenoEngine::container;
void Key::Press(KeyCode) {}
void Key::Release(KeyCode) {}

bool StenoKeyCodeEmitter::Process(const StenoKeyCode *previous, size_t pn,
                                  const StenoKeyCode *next, size_t nn) const {
  while (pn && nn && previous->HasSameOutput(*next)) { ++previous; ++next; --pn; --nn; }
  if (!pn && !nn) return true;
  if (activeEdit) {
    for (size_t i=0; i<pn; ++i) if (!previous[i].IsRawKeyCode()) ++activeEdit->removed;
    Emit(next, nn);
  }
  return false;
}
void StenoKeyCodeEmitter::Emit(const StenoKeyCode *value, size_t count) const {
  if (!activeEdit) return;
  for (size_t i=0; i<count; ++i)
    if (!value[i].IsRawKeyCode()) activeEdit->text.push_back(value[i].ResolveOutputUnicode());
}

class HostDictionary final : public StenoDictionary {
 public:
  HostDictionary():StenoDictionary(1) {}
  std::unordered_map<std::string,std::string> entries;
  const char *GetName() const override { return "AMT dictionaries"; }
  StenoDictionaryLookupResult Lookup(const StenoDictionaryLookup &lookup) const override {
    auto found = entries.find(std::string(reinterpret_cast<const char *>(lookup.strokes),lookup.length*sizeof(StenoStroke)));
    return found == entries.end() ? StenoDictionaryLookupResult::CreateInvalid()
      : StenoDictionaryLookupResult::CreateStaticString(found->second.c_str());
  }
  bool Add(const char *outline, const char *translation) {
    std::vector<StenoStroke> strokes;
    std::string input(outline); size_t offset=0;
    if (input.empty() || input.size()>2048 || input.back()=='/') return false;
    do {
      auto end=input.find('/',offset);
      auto part=input.substr(offset,end-offset); StenoStroke stroke; if (!stroke.SetChecked(part.c_str())) return false;
      if (stroke.IsEmpty()) return false;
      strokes.push_back(stroke); if (end==std::string::npos) break; offset=end+1;
    } while (offset<input.size());
    if (strokes.empty() || strokes.size()>31) return false;
    maximumOutlineLength=std::max(maximumOutlineLength,strokes.size());
    entries.emplace(std::string(reinterpret_cast<const char *>(strokes.data()),strokes.size()*sizeof(StenoStroke)),translation);
    return true;
  }
};
// Conservative English spelling rules, expressed in Javelin's own pattern DSL.
// Longer dictionary outlines still take precedence over generated suffix forms.
static const StenoOrthographyRule rules[] = {
  {"^(.+[bcdfghjklmnpqrstvwxz])y \\^s$", "\\1ies"},
  {"^(.*[sxz]) \\^s$", "\\1es"},
  {"^(.*[cs]h) \\^s$", "\\1es"},
  {"^(.+)ie \\^ing$", "\\1ying"},
  {"^(.+)e \\^([aeiou].*)$", "\\1\\2"},
  {"^(.+[bcdfghjklmnpqrstvwxz])y \\^ed$", "\\1ied"},
};
static const StenoOrthography orthography = {{sizeof(rules)/sizeof(*rules),rules},{},0,{},{},{}};
static const StenoCompiledOrthography &HostOrthography() {
  // Javelin patterns are lifetime allocations. Compile once across dictionary reloads.
  static const StenoCompiledOrthography compiled{orthography};
  return compiled;
}
struct HostEngine {
  HostDictionary dictionary;
  StenoSystem system = {};
  StenoEngine engine{dictionary,&system,HostOrthography()};
  HostEdit edit;
};
extern "C" {
void *AMTJavelinCreate() { return new HostEngine; }
void AMTJavelinDestroy(void *p) { delete static_cast<HostEngine *>(p); }
int AMTJavelinAdd(void *p,const char *outline,const char *translation) { return static_cast<HostEngine *>(p)->dictionary.Add(outline,translation); }
int AMTJavelinCanonicalOutline(const char *input,char *output,size_t capacity) {
  std::string source(input), canonical; size_t offset=0;
  if (source.empty() || source.size()>2048 || source.back()=='/') return 0;
  size_t count=0;
  do {
    auto end=source.find('/',offset); auto part=source.substr(offset,end-offset);
    StenoStroke stroke; if (!stroke.SetChecked(part.c_str()) || ++count>31) return 0;
    char buffer[StenoStroke::MAX_STRING_LENGTH]; stroke.ToString(buffer);
    if (!canonical.empty()) canonical+='/'; canonical+=buffer;
    if (end==std::string::npos) break; offset=end+1;
  } while (offset<source.size());
  if (canonical.size()+1>capacity) return 0;
  memcpy(output,canonical.c_str(),canonical.size()+1); return 1;
}
void AMTJavelinReset(void *p) { auto &h=*static_cast<HostEngine *>(p); h.engine.ResetHostTranslation(); h.edit={}; }
int AMTJavelinProcess(void *p,uint32_t stroke) {
  auto &h=*static_cast<HostEngine *>(p); h.edit={}; activeEdit=&h.edit;
  try { if (stroke) h.engine.Process(StenoStroke(stroke)); }
  catch (...) { activeEdit=nullptr; h.edit={}; h.engine.ResetHostTranslation(); return 0; }
  activeEdit=nullptr; return 1;
}
size_t AMTJavelinDeleteCount(void *p) { return static_cast<HostEngine *>(p)->edit.removed; }
size_t AMTJavelinTextCount(void *p) { return static_cast<HostEngine *>(p)->edit.text.size(); }
uint32_t AMTJavelinTextAt(void *p,size_t i) { return static_cast<HostEngine *>(p)->edit.text.at(i); }
}

// Desktop implementations of the core's required HAL surface. Firmware-only
// entry points are inert; time/cache locking are real host implementations.
#include "Vendor/button_script.h"
#include "Vendor/hal/serial_port.h"
#include "Vendor/flash.h"
#include "Vendor/clock.h"
#include "Vendor/console.h"
#include <chrono>
#include <mutex>
static std::recursive_mutex cacheMutex;
void StenoCompiledOrthography::LockCache() { cacheMutex.lock(); }
void StenoCompiledOrthography::UnlockCache() { cacheMutex.unlock(); }
uint32_t Clock::GetMicroseconds() { return uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
uint32_t Clock::GetMilliseconds() { return uint32_t(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
void SerialPort::SendByte(uint8_t) {}
void ButtonScript::OnStenoKeyPressed() {}
void ButtonScript::OnStenoKeyReleased() {}
void ButtonScript::CancelStenoKeys(StenoKeyState) {}
void ButtonScript::CancelAllStenoKeys() {}
void Flash::EraseBlockInternal(const void *,size_t) {}
void Flash::WriteBlockInternal(const void *,const void *,size_t) {}
void ConsoleWriter::Write(const char *,size_t) {}
