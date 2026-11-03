// Read-only snapshot using the same service/ancestor/HIDParameters precedence as
// InstalledPointerCurveReader and InstalledScrollCurveReader. No device is opened.
// swift export.swift /path/to/mac-motion.json
import Foundation
import IOKit

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message+"\n").utf8)); exit(1) }
func fixed(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber else { return nil }
    var raw = n.int64Value
    if raw >= 0x80000000 && raw <= 0xffffffff { raw -= 0x100000000 }
    return Double(raw)/65536
}
func curves(_ value: Any?) -> [[String:Double]] {
    guard let entries = value as? [[String:Any]], !entries.isEmpty else { fail("Missing acceleration curves") }
    return entries.map { entry in
        guard let index = fixed(entry["HIDAccelIndex"]) else { fail("Missing curve index") }
        var result = ["index": index]
        for key in ["HIDAccelGainLinear","HIDAccelGainParabolic","HIDAccelGainCubic","HIDAccelGainQuartic","HIDAccelTangentSpeedLinear","HIDAccelTangentSpeedParabolicRoot"] {
            result[key] = fixed(entry[key]) ?? 0
        }
        return result
    }
}
let prefs = UserDefaults.standard.persistentDomain(forName:"ink.ranna.applemagictouchstream") ?? [:]
let handData = prefs["AppleMagicTouchstream.handGestureBindings.v1"] as? Data
let hands = handData.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
let globalNatural = UserDefaults.standard.persistentDomain(forName:UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool ?? true
let system = IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOHIDSystem"))
let params = system == 0 ? [:] : IORegistryEntryCreateCFProperty(system,"HIDParameters" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any] ?? [:]
if system != 0 { IOObjectRelease(system) }
var iterator:io_iterator_t = 0
 guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleMultitouchDevice"),&iterator) == KERN_SUCCESS else { fail("Cannot enumerate trackpads") }
var devices:[[String:Any]] = []
while case let service = IOIteratorNext(iterator), service != 0 {
    defer { IOObjectRelease(service) }
    func own(_ key:String)->Any? { IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
    guard let id = (own("Multitouch ID") as? NSNumber)?.uint64Value,
          let vid = own("VendorID") as? NSNumber, [0x004c,0x05ac].contains(vid.intValue),
          (own("ProductID") as? NSNumber)?.intValue == 0x0324 else { continue }
    guard let side = ["left","right"].first(where:{ (prefs["GlassToKey.\($0)DeviceID"] as? String).flatMap(UInt64.init) == id || (prefs["GlassToKey.\($0)DeviceID"] as? NSNumber)?.uint64Value == id }) else { continue }
    func property(_ key:String)->Any? {
        IORegistryEntrySearchCFProperty(service,kIOServicePlane,key as CFString,kCFAllocatorDefault,IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }
    func scroll(_ key:String)->Any? { property(key) ?? params[key] }
    guard let acceleration = fixed(property("HIDTrackpadAcceleration") ?? params["HIDTrackpadAcceleration"]),
          let resolution = fixed(property("HIDPointerResolution")) else { fail("Missing selected \(side) pointer profile") }
    let multiplier = fixed(property("HIDPointerAccelerationMultiplier")) ?? 1
    let pointer:[String:Any] = ["device_id":"Captured Mac \(side)","resolution":resolution,"algorithm_rate":67,"report_rate":(property("HIDPointerReportRate") as? NSNumber)?.doubleValue ?? 0,"fixed_multiplier":multiplier == 0 ? 1 : multiplier,"acceleration":acceleration,"curves":curves(property("HIDUserPointerAccelCurves") ?? property("HIDAccelCurves"))]
    let type = scroll("HIDScrollAccelerationType") as? String ?? "HIDTrackpadScrollAcceleration"
    guard let index = fixed(scroll(type) ?? scroll("HIDMouseScrollAcceleration") ?? scroll("HIDScrollAcceleration")) else { fail("Missing scroll index") }
    let scrollCurves = curves(scroll("HIDUserScrollAccelCurves") ?? scroll("HIDScrollAccelCurves"))
    let rawRate = fixed(scroll("HIDScrollReportRate")) ?? 67
    func axis(_ key:String)->[String:Any] {
        guard let resolution = fixed(scroll(key) ?? scroll("HIDScrollResolution")) else { fail("Missing scroll resolution") }
        return ["resolution":resolution,"algorithm_rate":rawRate == 0 ? 67 : rawRate,"acceleration":index,"curves":scrollCurves]
    }
    let hand = hands[side] as? [String:Any] ?? [:]
    devices.append(["side":side,"pointer":pointer,"scroll":["horizontal":axis("HIDScrollResolutionX"),"vertical":axis("HIDScrollResolutionY"),"natural":hand["naturalScrolling"] as? Bool ?? globalNatural],"pointerSensitivity":hand["pointerSensitivity"] as? Double ?? 1,"scrollSensitivity":hand["scrollSensitivity"] as? Double ?? 1])
}
IOObjectRelease(iterator)
guard Set(devices.compactMap{$0["side"] as? String}) == Set(["left","right"]) else { fail("Both saved selected Magic Trackpads must be connected; refusing partial export") }
let snapshot:[String:Any] = ["schema":"amt.mac-motion.v1","capturedAt":ISO8601DateFormatter().string(from:Date()),"source":"Mac AMT live-reader precedence; selected Magic Trackpads; identifying metadata omitted","devices":devices.sorted{($0["side"] as! String) < ($1["side"] as! String)}]
guard CommandLine.arguments.count == 2 else { fail("Usage: swift export.swift output.json") }
try JSONSerialization.data(withJSONObject:snapshot,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
print("Saved pointer + scroll profiles for both selected pads")
