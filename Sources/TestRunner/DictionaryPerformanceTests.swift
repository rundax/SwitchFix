import Foundation
import Dictionary
import Darwin.Mach

private func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let idx = Int(Double(sorted.count - 1) * p)
    return sorted[idx]
}

private func currentRSSBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

    let result = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                rebound,
                &count
            )
        }
    }

    guard result == KERN_SUCCESS else {
        return 0
    }

    return UInt64(info.resident_size)
}

func runDictionaryPerformanceSuites() {
    runSuite("Perf: Dictionary load + lookup") {
        let loader = DictionaryLoader.shared
        let validator = WordValidator.shared

        loader.resetForTesting()
        let rssBefore = currentRSSBytes()

        let loadStart = ContinuousClock.now
        _ = loader.bloomFilter(for: .ukrainian)
        let loadDuration = loadStart.duration(to: .now)

        let rssAfterLoad = currentRSSBytes()

        let samples = [
            "привіт", "світ", "подивимось", "працює", "тестування",
            "ghbdtn", "руддщ", "дуе", "андрей", "стрімкий"
        ]

        var timings: [Double] = []
        timings.reserveCapacity(500)

        for i in 0..<500 {
            let word = samples[i % samples.count]
            let start = ContinuousClock.now
            _ = validator.isExactWord(word, language: .ukrainian)
            let d = start.duration(to: .now)
            timings.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }

        let avg = timings.reduce(0, +) / Double(timings.count)
        let p95 = percentile(timings, 0.95)
        let p99 = percentile(timings, 0.99)

        let loadMs = Double(loadDuration.components.seconds) * 1000 + Double(loadDuration.components.attoseconds) / 1e15
        let rssBeforeMB = Double(rssBefore) / 1024.0 / 1024.0
        let rssAfterLoadMB = Double(rssAfterLoad) / 1024.0 / 1024.0
        let avgMs = String(format: "%.4f", avg)
        let p95Ms = String(format: "%.4f", p95)
        let p99Ms = String(format: "%.4f", p99)

        print("  load_ms: \(String(format: "%.2f", loadMs))")
        print("  rss_before_mb: \(String(format: "%.2f", rssBeforeMB))")
        print("  rss_after_load_mb: \(String(format: "%.2f", rssAfterLoadMB))")
        print("  exact_lookup_ms avg/p95/p99: \(avgMs)/\(p95Ms)/\(p99Ms)")

        assert(loadDuration.components.seconds < 60, "dictionary load should stay under 60s in test env")
    }
}
