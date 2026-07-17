import Foundation
import IOKit.ps
import MachO

struct SystemStats: Equatable {
    var cpuUsage: Double
    var pCoreAvg: Double
    var eCoreAvg: Double
    var memoryUsed: Double
    var memoryTotal: Double
    var memoryWired: Double
    var memoryActive: Double
    var memoryCompressed: Double
    var memoryInactive: Double
    var memoryFree: Double
    var swapUsed: Double
    var swapTotal: Double
    var diskUsed: Double
    var diskTotal: Double
    var batteryLevel: Double?
    var batteryCharging: Bool
    var thermalState: ProcessInfo.ThermalState
    var gpuUsage: Double

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var memoryPressure: Double {
        memoryTotal > 0 ? (memoryWired + memoryActive + memoryCompressed) / memoryTotal : 0
    }
    var diskFraction: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }
    var swapFraction: Double { swapTotal > 0 ? swapUsed / swapTotal : 0 }
}

private struct SwapUsage {
    var total: UInt64 = 0
    var avail: UInt64 = 0
    var used: UInt64 = 0
    var flags: UInt32 = 0
}

@MainActor
final class SystemMonitorManager: ObservableObject {
    @Published private(set) var stats = SystemStats(
        cpuUsage: 0, pCoreAvg: 0, eCoreAvg: 0,
        memoryUsed: 0, memoryTotal: 0,
        memoryWired: 0, memoryActive: 0, memoryCompressed: 0,
        memoryInactive: 0, memoryFree: 0,
        swapUsed: 0, swapTotal: 0,
        diskUsed: 0, diskTotal: 0,
        batteryLevel: nil, batteryCharging: false,
        thermalState: .nominal, gpuUsage: 0
    )

    let pCoreCount: Int
    let eCoreCount: Int

    private var timer: Timer?
    private var previousPerCoreTicks: [UInt32]?
    private var previousTotalTicks: UInt32?

    init() {
        var p = 0, e = 0
        var size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &p, &size, nil, 0) != 0 { p = 0 }
        size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &e, &size, nil, 0) != 0 { e = 0 }
        if p + e == 0 { p = ProcessInfo.processInfo.processorCount / 2 } // fallback
        self.pCoreCount = max(p, 1)
        self.eCoreCount = max(e, 0)
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    private func refresh() {
        let cpu = readCPU()
        let mem = readMemory()
        let disk = readDisk()
        let bat = readBattery()
        let gpu = readGPU()
        let swap = readSwap()
        let thermal = ProcessInfo.processInfo.thermalState
        stats = SystemStats(
            cpuUsage: cpu.overall,
            pCoreAvg: cpu.pAvg,
            eCoreAvg: cpu.eAvg,
            memoryUsed: mem.used,
            memoryTotal: mem.total,
            memoryWired: mem.wired,
            memoryActive: mem.active,
            memoryCompressed: mem.compressed,
            memoryInactive: mem.inactive,
            memoryFree: mem.free,
            swapUsed: swap.used,
            swapTotal: swap.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            batteryLevel: bat.level,
            batteryCharging: bat.charging,
            thermalState: thermal,
            gpuUsage: gpu
        )
    }

    // MARK: CPU

    private func readCPU() -> (overall: Double, pAvg: Double, eAvg: Double) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount)
        guard kr == KERN_SUCCESS, let info = cpuInfo else {
            return (stats.cpuUsage, stats.pCoreAvg, stats.eCoreAvg)
        }

        defer {
            let size = MemoryLayout<processor_cpu_load_info>.size * Int(numCPUs)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(size))
        }

        let count = Int(numCPUs)
        let loadInfo = UnsafeBufferPointer<processor_cpu_load_info>(
            start: UnsafePointer(OpaquePointer(info)),
            count: count
        )

        var totalTicks: UInt32 = 0
        var idleTicks: UInt32 = 0
        var perCoreBusy: [UInt32] = []
        for i in 0..<count {
            let cpu = loadInfo[i]
            let user = cpu.cpu_ticks.0
            let system = cpu.cpu_ticks.1
            let idle = cpu.cpu_ticks.2
            let nice = cpu.cpu_ticks.3
            let coreTotal = user &+ system &+ idle &+ nice
            totalTicks = totalTicks &+ coreTotal
            idleTicks = idleTicks &+ idle
            perCoreBusy.append(coreTotal &- idle)
        }

        let busyTotal = totalTicks &- idleTicks
        guard let prevTotal = previousTotalTicks, let prevBusy = previousPerCoreTicks, prevBusy.count == count else {
            previousTotalTicks = totalTicks
            previousPerCoreTicks = perCoreBusy
            return (stats.cpuUsage, stats.pCoreAvg, stats.eCoreAvg)
        }

        let totalDelta = Double(totalTicks &- prevTotal)
        guard totalDelta > 0 else { return (stats.cpuUsage, stats.pCoreAvg, stats.eCoreAvg) }

        let overallBusyDelta = Double(busyTotal &- prevBusy.reduce(0, +))
        let overall = min(overallBusyDelta / totalDelta, 1)

        // Per-core usage
        let pCores = min(pCoreCount, count)
        var pSum: Double = 0
        var eSum: Double = 0
        for i in 0..<count {
            let delta = Double(perCoreBusy[i] &- prevBusy[i])
            let usage = min(delta / totalDelta, 1)
            if i < pCores { pSum += usage } else { eSum += usage }
        }

        previousTotalTicks = totalTicks
        previousPerCoreTicks = perCoreBusy

        return (overall, pSum / Double(pCores), eSum / Double(max(eCoreCount, 1)))
    }

    // MARK: Memory

    private func readMemory() -> (used: Double, total: Double, wired: Double, active: Double, compressed: Double, inactive: Double, free: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else {
            return (stats.memoryUsed, total, stats.memoryWired, stats.memoryActive, stats.memoryCompressed, stats.memoryInactive, stats.memoryFree)
        }

        let pageSize = Double(vm_page_size)
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let inactive = Double(vmStats.inactive_count) * pageSize
        let free_ = Double(vmStats.free_count) * pageSize
        let used = active + wired + compressed
        return (used, total, wired, active, compressed, inactive, free_)
    }

    // MARK: Swap

    private func readSwap() -> (used: Double, total: Double) {
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.size
        var mib = [CTL_VM, 5] // VM_SWAPUSAGE
        let err = sysctl(&mib, UInt32(mib.count), &usage, &size, nil, 0)
        guard err == 0 else { return (stats.swapUsed, stats.swapTotal) }
        return (Double(usage.used), Double(usage.total))
    }

    // MARK: Disk

    private func readDisk() -> (used: Double, total: Double) {
        let path = "/"
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber
        else { return (stats.diskUsed, stats.diskTotal) }
        let totalBytes = total.doubleValue
        let freeBytes = free.doubleValue
        return (totalBytes - freeBytes, totalBytes)
    }

    // MARK: Battery

    private func readBattery() -> (level: Double?, charging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return (nil, false) }

        let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let level = max > 0 ? Double(current) / Double(max) : 1
        return plugged ? (nil, false) : (level, charging)
    }

    // MARK: GPU

    private func readGPU() -> Double {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("AGXAccelerator")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return stats.gpuUsage }
        defer { IOObjectRelease(iterator) }

        var total: Double = 0
        var count: Int = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let props = IORegistryEntryCreateCFProperty(entry, "GPU Utilization %" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                var raw: UInt32 = 0
                (props as NSData).getBytes(&raw, length: MemoryLayout<UInt32>.size)
                total += min(Double(raw) / 100.0, 1.0)
                count += 1
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return count > 0 ? total / Double(count) : 0
    }
}
