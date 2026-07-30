import Foundation
import IOKit.ps
import Darwin
import Defaults

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

    /// Badge / collapsed load metric.
    func load(for mode: SystemLoadBadgeMetric) -> Double {
        switch mode {
        case .max: return max(cpuUsage, memoryPressure)
        case .cpu: return cpuUsage
        case .memory: return memoryPressure
        }
    }
}

struct TopProcess: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpuFraction: Double
    var id: Int32 { pid }
}

enum SystemLoadBadgeMetric: String, Defaults.Serializable, CaseIterable, Identifiable {
    case max, cpu, memory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .max: return "Max of CPU & Memory"
        case .cpu: return "CPU"
        case .memory: return "Memory pressure"
        }
    }
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
    @Published private(set) var topProcesses: [TopProcess] = []

    let pCoreCount: Int
    let eCoreCount: Int
    let logicalCPUCount: Int

    private var timer: Timer?
    /// Per-core cumulative busy ticks (user+system+nice).
    private var previousPerCoreBusy: [UInt32]?
    /// Per-core cumulative total ticks (busy+idle).
    private var previousPerCoreTotal: [UInt32]?
    /// pid → total CPU time in ns (user+system).
    private var previousProcessCPU: [Int32: UInt64] = [:]
    private var previousProcessSample: Date?

    init() {
        var p = 0, e = 0
        var size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &p, &size, nil, 0) != 0 { p = 0 }
        size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &e, &size, nil, 0) != 0 { e = 0 }
        if p + e == 0 { p = ProcessInfo.processInfo.processorCount / 2 }
        self.pCoreCount = max(p, 1)
        self.eCoreCount = max(e, 0)
        self.logicalCPUCount = max(ProcessInfo.processInfo.processorCount, 1)
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
        topProcesses = readTopProcesses()
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

        var perCoreBusy: [UInt32] = []
        var perCoreTotal: [UInt32] = []
        perCoreBusy.reserveCapacity(count)
        perCoreTotal.reserveCapacity(count)

        for i in 0..<count {
            let cpu = loadInfo[i]
            let user = cpu.cpu_ticks.0
            let system = cpu.cpu_ticks.1
            let idle = cpu.cpu_ticks.2
            let nice = cpu.cpu_ticks.3
            let coreTotal = user &+ system &+ idle &+ nice
            let coreBusy = user &+ system &+ nice
            perCoreTotal.append(coreTotal)
            perCoreBusy.append(coreBusy)
        }

        guard let prevBusy = previousPerCoreBusy,
              let prevTotal = previousPerCoreTotal,
              prevBusy.count == count,
              prevTotal.count == count
        else {
            previousPerCoreBusy = perCoreBusy
            previousPerCoreTotal = perCoreTotal
            return (stats.cpuUsage, stats.pCoreAvg, stats.eCoreAvg)
        }

        // Each core's usage = busyΔ / totalΔ for that core (not / sum of all cores).
        var usages = [Double](repeating: 0, count: count)
        var busySum: Double = 0
        var totalSum: Double = 0
        for i in 0..<count {
            let tDelta = Double(perCoreTotal[i] &- prevTotal[i])
            let bDelta = Double(perCoreBusy[i] &- prevBusy[i])
            totalSum += tDelta
            busySum += bDelta
            usages[i] = tDelta > 0 ? min(max(bDelta / tDelta, 0), 1) : 0
        }

        previousPerCoreBusy = perCoreBusy
        previousPerCoreTotal = perCoreTotal

        let overall = totalSum > 0 ? min(max(busySum / totalSum, 0), 1) : stats.cpuUsage
        let pCores = min(pCoreCount, count)
        let pAvg = pCores > 0 ? usages.prefix(pCores).reduce(0, +) / Double(pCores) : 0
        let eCount = count - pCores
        let eAvg = eCount > 0 ? usages.suffix(eCount).reduce(0, +) / Double(eCount) : 0

        return (overall, pAvg, eAvg)
    }

    // MARK: Top processes

    private func readTopProcesses() -> [TopProcess] {
        let now = Date()
        let pids = listPIDs()
        var current: [Int32: UInt64] = [:]
        var names: [Int32: String] = [:]
        current.reserveCapacity(pids.count)

        for pid in pids {
            guard let total = processCPUTime(pid) else { continue }
            current[pid] = total
            if let n = processName(pid) { names[pid] = n }
        }

        defer {
            previousProcessCPU = current
            previousProcessSample = now
        }

        guard let prevDate = previousProcessSample, !previousProcessCPU.isEmpty else {
            return topProcesses
        }

        let elapsed = now.timeIntervalSince(prevDate)
        guard elapsed > 0.2 else { return topProcesses }

        let ncpu = Double(logicalCPUCount)
        var ranked: [TopProcess] = []
        ranked.reserveCapacity(16)

        for (pid, total) in current {
            guard let prev = previousProcessCPU[pid] else { continue }
            let delta = total >= prev ? total - prev : 0
            // Fraction of full machine capacity (all cores).
            let fraction = min(Double(delta) / (elapsed * 1_000_000_000) / ncpu, 1)
            guard fraction >= 0.005 else { continue }
            let name = names[pid] ?? "pid \(pid)"
            ranked.append(TopProcess(pid: pid, name: name, cpuFraction: fraction))
        }

        ranked.sort { $0.cpuFraction > $1.cpuFraction }
        return Array(ranked.prefix(5))
    }

    private func listPIDs() -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bytes))
        guard filled > 0 else { return [] }
        let n = Int(filled) / MemoryLayout<Int32>.size
        return pids.prefix(n).filter { $0 > 0 }
    }

    private func processCPUTime(_ pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info.pti_total_user &+ info.pti_total_system
    }

    private func processName(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(cString: buf)
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
