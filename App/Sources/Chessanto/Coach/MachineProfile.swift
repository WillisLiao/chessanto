import Foundation

/// Chip/RAM detection for the model picker (PLAN.md's Model Picker), via
/// `sysctl` per NEXT-SESSION-M6.md's verified fact 17.
enum MachineProfile {
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }

    static var physicalMemoryGB: Int {
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return Int(memSize / 1_073_741_824)
    }
}
