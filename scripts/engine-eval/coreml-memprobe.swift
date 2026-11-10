// coreml-memprobe (#272): swiftc -O coreml-memprobe.swift -o memprobe
//   ./memprobe A.mlmodelc[,B.mlmodelc] all|cpu|cpugpu|cpuane
// Prints phys_footprint (what iOS jetsam counts) before load, after load, after one zero-input prediction.
import CoreML
import Foundation
func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}
let a = CommandLine.arguments
let cfg = MLModelConfiguration()
cfg.computeUnits = ["cpu": .cpuOnly, "cpugpu": .cpuAndGPU, "cpuane": .cpuAndNeuralEngine][a[2]] ?? .all
var out: [String: Any] = ["units": a[2], "before_mb": footprint()]
var models: [MLModel] = []
for p in a[1].split(separator: ",") { models.append(try MLModel(contentsOf: URL(fileURLWithPath: String(p)), configuration: cfg)) }
out["loaded_mb"] = footprint()
for m in models {
    var feats: [String: MLFeatureValue] = [:]
    for (n, d) in m.modelDescription.inputDescriptionsByName {
        guard let c = d.multiArrayConstraint else { continue }
        let arr = try MLMultiArray(shape: c.shape, dataType: c.dataType)
        for i in 0..<arr.count { arr[i] = 0 }
        feats[n] = MLFeatureValue(multiArray: arr)
    }
    _ = try m.prediction(from: MLDictionaryFeatureProvider(dictionary: feats))
}
out["predicted_mb"] = footprint()
var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
out["maxrss_mb"] = Double(ru.ru_maxrss) / 1_048_576
print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
