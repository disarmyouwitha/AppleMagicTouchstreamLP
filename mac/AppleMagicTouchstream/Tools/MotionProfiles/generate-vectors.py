#!/usr/bin/env python3
"""Generate portable regression vectors with Mac's actual pure production models.
No AMT process, device opening, input posting or system configuration changes.
Run from any directory; arguments: snapshot.json output-vectors.json.
"""
from pathlib import Path
import subprocess,sys,tempfile
root=Path(__file__).resolve().parents[2]
runtime=root/'AppleMagicTouchstream/AppleMagicTouchstream/Runtime'
pointer=(runtime/'PointerAcceleration.swift').read_text().split('/// Registry reads are control-path only.')[0].replace('import OpenMultitouchSupport','')
scroll=(runtime/'ScrollGesture.swift').read_text().split('/// Project travel along the assigned input direction')[0].replace('import OpenMultitouchSupport','')
harness=r'''
func decode(_ o:[String:Any]) throws -> ApplePointerAccelerationProfile {
    let curves=(o["curves"] as! [[String:Double]]).map { c in
        ApplePointerCurve(index:c["index"]!,linear:c["HIDAccelGainLinear"] ?? 0,parabolic:c["HIDAccelGainParabolic"] ?? 0,cubic:c["HIDAccelGainCubic"] ?? 0,quartic:c["HIDAccelGainQuartic"] ?? 0,tangentLinear:c["HIDAccelTangentSpeedLinear"] ?? 0,tangentRoot:c["HIDAccelTangentSpeedParabolicRoot"] ?? 0)
    }
    return try ApplePointerAccelerationProfile(resolution:o["resolution"] as! Double,reportRate:o["report_rate"] as? Double ?? 0,fixedMultiplier:o["fixed_multiplier"] as? Double ?? 1,acceleration:o["acceleration"] as! Double,curves:curves,algorithmRate:o["algorithm_rate"] as? Double ?? 67)
}
let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var results:[[String:Any]]=[]
for device in input["devices"] as! [[String:Any]] {
    let pointerProfile=try decode(device["pointer"] as! [String:Any])
    let scroll=device["scroll"] as! [String:Any]
    let profile=try AppleScrollProfile(horizontal:decode(scroll["horizontal"] as! [String:Any]),vertical:decode(scroll["vertical"] as! [String:Any]),natural:scroll["natural"] as! Bool)
    for sensitivity in [0.5,1.0,1.75] {
        var pointer=ApplePointerAccelerator(profile:pointerProfile), scrolling=FourFingerScrollEngine(profile:profile)
        var vectors:[[String:Any]]=[]
        var time=1.0
        let values:[Double]=[0,0.001,0.01,0.03,0.1,0.2,0.4,0.8,0.2,0.001,0,-0.001,-0.02,-0.2,-0.5,0.05]
        for (i,x) in (values+values).enumerated() {
            time += i == values.count ? 0.8 : [0.008,0.011,0.016,0.02][i%4]
            let y = i%3 == 0 ? 0 : -x*0.6
            let factor=pointerProfile.resolution/25.4*sensitivity
            let p=pointer.delta(time:time,counts:CGPoint(x:x*factor,y:y*factor))!
            let s=scrolling.process(time:time,millimetres:CGPoint(x:x,y:y),sensitivity:sensitivity)!
            vectors.append(["t":time,"x":x,"y":y,"pointerX":p.x,"pointerY":p.y,"scrollX":s.x,"scrollY":s.y])
        }
        results.append(["side":device["side"]!,"sensitivity":sensitivity,"vectors":vectors])
    }
}
let output:[String:Any] = ["note":"Generated with Mac production ApplePointerAccelerator and FourFingerScrollEngine; numerical parity, not hardware ground truth.","runs":results]
try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
'''
with tempfile.TemporaryDirectory(prefix='amt-motion-vectors-') as temp:
    source=Path(temp)/'main.swift'
    source.write_text(pointer+'\n'+scroll+'\n'+harness)
    subprocess.run(['swift',str(source),str(Path(sys.argv[1]).resolve()),str(Path(sys.argv[2]).resolve())],check=True)
