import Foundation

public struct WilsonScoreInterval: Codable, Equatable, Sendable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    public static func compute(successes: Int, total: Int, z: Double = 1.95996) -> WilsonScoreInterval? {
        guard total > 0, successes >= 0, successes <= total else { return nil }
        let n = Double(total)
        let k = Double(successes)
        let z2 = z * z
        let p = k / n
        let denominator = 1.0 + z2 / n
        let center = (p + z2 / (2.0 * n)) / denominator
        let spread = (z * sqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n))) / denominator
        let lower = max(0.0, center - spread)
        let upper = min(1.0, center + spread)
        return WilsonScoreInterval(lower: lower, upper: upper)
    }

    public var formatted: String {
        let l = String(format: "%.1f%%", lower * 100)
        let u = String(format: "%.1f%%", upper * 100)
        return "[\(l), \(u)]"
    }
}

/// Per-trial outcome. Unsupported trials leave every quality denominator; errors and missing
/// observations stay in them as failures, so they can never count as correct preservation.
public enum TrialOutcome: String, Codable, Equatable, Sendable {
    case truePositive = "TP"
    case fnNoAction = "FN_no_action"
    case fnWrongRepair = "FN_wrong_repair"
    case fnWrongSource = "FN_wrong_source"
    case fnUnsafeMutation = "FN_unsafe_mutation"
    case fnTransientDamage = "FN_transient_damage"
    case fnError = "FN_error"
    case trueNegative = "TN"
    case textDamageFP = "FP_text_damage"
    case layoutOnlyFP = "FP_layout_only"
    case negativeError = "NEG_error"
    case unsupported = "unsupported"

    public var isPassing: Bool {
        self == .truePositive || self == .trueNegative
    }
}

public struct ScoredMetric: Codable, Equatable, Sendable {
    public let count: Int
    public let total: Int
    public let rate: Double?
    public let interval: WilsonScoreInterval?

    public init(count: Int, total: Int, z: Double = 1.95996) {
        self.count = count
        self.total = total
        if total > 0 {
            self.rate = Double(count) / Double(total)
            self.interval = WilsonScoreInterval.compute(successes: count, total: total, z: z)
        } else {
            self.rate = nil
            self.interval = nil
        }
    }
}

public struct OutcomeTally: Codable, Equatable, Sendable {
    public var total = 0
    public var nPositive = 0
    public var nNegative = 0
    public var tp = 0
    public var fn = 0
    public var tn = 0
    public var textFP = 0
    public var layoutFP = 0
    public var errors = 0
    public var unsupported = 0

    public var recall: Double? { nPositive > 0 ? Double(tp) / Double(nPositive) : nil }
    public var textDamageFPRate: Double? { nNegative > 0 ? Double(textFP) / Double(nNegative) : nil }

    mutating func add(_ outcome: TrialOutcome, positive: Bool) {
        total += 1
        if outcome == .unsupported {
            unsupported += 1
            return
        }
        if positive { nPositive += 1 } else { nNegative += 1 }
        switch outcome {
        case .truePositive: tp += 1
        case .fnError, .negativeError: errors += 1; if positive { fn += 1 }
        case .fnNoAction, .fnWrongRepair, .fnWrongSource, .fnUnsafeMutation, .fnTransientDamage: fn += 1
        case .trueNegative: tn += 1
        case .textDamageFP: textFP += 1
        case .layoutOnlyFP: layoutFP += 1
        case .unsupported: break
        }
    }
}

public struct BenchmarkScoreReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    /// Trials requested, including unsupported ones.
    public let totalTrials: Int
    public let groupCount: Int
    /// No error or missing observation; a quality gate requires this.
    public let complete: Bool
    public let completedTrials: Int
    public let unsupportedTrials: Int
    public let errorTrials: Int
    public let missingTrials: Int
    public let coverage: ScoredMetric

    public let nPositive: Int
    public let nNegative: Int
    public let nPreserve: Int
    public let nAbstain: Int

    public let truePositives: Int
    public let fnNoAction: Int
    public let fnWrongRepair: Int
    public let fnWrongSource: Int
    public let fnUnsafeMutation: Int
    public let fnTransientDamage: Int
    public let fnError: Int
    public let falseNegatives: Int
    public let trueNegatives: Int
    public let textDamageFPs: Int
    public let layoutOnlyFPs: Int
    public let totalFPs: Int
    /// Negative trials with any unauthorized source change, with or without text damage.
    public let unauthorizedSourceChanges: Int
    public let repairAttempts: Int

    public let recall: ScoredMetric
    public let precision: ScoredMetric
    public let textDamageFPRate: ScoredMetric
    public let layoutOnlyFPRate: ScoredMetric
    public let totalFPRate: ScoredMetric
    public let unauthorizedSourceChangeRate: ScoredMetric

    public let directionBreakdown: [String: OutcomeTally]
    public let categoryBreakdown: [String: OutcomeTally]
    /// Diagnostic reason codes across all results (mapping rejections, cancellations, mismatches).
    public let reasonCodeCounts: [String: Int]
    public let trialOutcomes: [String: TrialOutcome]
}

public enum Scorer {
    public static func classify(trial: Trial, result: TrialResult?) -> TrialOutcome {
        let positive = trial.label == "repair"
        guard let result else { return positive ? .fnError : .negativeError }
        switch result.status {
        case "ok": break
        case "unsupported": return .unsupported
        default: return positive ? .fnError : .negativeError
        }

        let observed = Dictionary(result.checkpoints.map { ($0.afterEvent, $0) }, uniquingKeysWith: { _, last in last })
        let checkpointsMatch = trial.expected.checkpoints.allSatisfy { expected in
            guard let seen = observed[expected.afterEvent] else { return false }
            return seen.text == expected.text && seen.language == expected.language
        }
        let prefixIntact = result.finalText.hasPrefix(trial.initial.text)
        let textMatches = result.finalText == trial.expected.text
        let sourceMatches = result.finalSourceID == trial.expected.sourceID
        let replaced = result.actions.contains { $0.type == "replaceSuffix" }
        let switched = result.actions.contains { $0.type == "switchSource" } || !sourceMatches

        if positive {
            let allowed = Set(trial.expected.allowedAutomaticActions)
            let actionsAllowed = result.actions.allSatisfy { allowed.contains($0.type) }
            if textMatches && sourceMatches && checkpointsMatch && actionsAllowed && prefixIntact {
                return .truePositive
            }
            if result.actions.isEmpty { return .fnNoAction }
            if !actionsAllowed || !prefixIntact { return .fnUnsafeMutation }
            if !textMatches { return .fnWrongRepair }
            if !sourceMatches { return .fnWrongSource }
            return .fnTransientDamage
        }

        // Any replacement counts as damage on a negative trial, even one later undone.
        if replaced || !textMatches || !checkpointsMatch || !prefixIntact {
            return .textDamageFP
        }
        return switched ? .layoutOnlyFP : .trueNegative
    }

    public static func score(trials: [Trial], results: [TrialResult]) -> BenchmarkScoreReport {
        var resultsMap: [String: TrialResult] = [:]
        for r in results {
            resultsMap[r.trialID] = r
        }

        var all = OutcomeTally()
        var nPreserve = 0
        var nAbstain = 0
        var completed = 0
        var missing = 0
        var unauthorizedSourceChanges = 0
        var attempts = 0
        var fnCounts: [TrialOutcome: Int] = [:]
        var directions: [String: OutcomeTally] = [:]
        var categories: [String: OutcomeTally] = [:]
        var reasonCounts: [String: Int] = [:]
        var outcomes: [String: TrialOutcome] = [:]

        for trial in trials {
            let result = resultsMap[trial.id]
            if result == nil { missing += 1 }
            if result?.status == "ok" { completed += 1 }
            for code in result?.reasonCodes ?? [] {
                reasonCounts[code, default: 0] += 1
            }

            let positive = trial.label == "repair"
            let outcome = classify(trial: trial, result: result)
            outcomes[trial.id] = outcome
            all.add(outcome, positive: positive)
            fnCounts[outcome, default: 0] += 1

            let direction = trial.initial.language == "en" ? "EN -> UK" : "UK -> EN"
            directions[direction, default: OutcomeTally()].add(outcome, positive: positive)
            categories[trial.category, default: OutcomeTally()].add(outcome, positive: positive)

            guard outcome != .unsupported else { continue }
            if !positive {
                if trial.label == "preserve" { nPreserve += 1 } else { nAbstain += 1 }
                if let result, result.status == "ok",
                   result.actions.contains(where: { $0.type == "switchSource" }) || result.finalSourceID != trial.expected.sourceID {
                    unauthorizedSourceChanges += 1
                }
            }
            if positive, let result, result.status == "ok", !result.actions.isEmpty {
                attempts += 1
            }
        }

        let totalFPs = all.textFP + all.layoutFP
        attempts += totalFPs

        return BenchmarkScoreReport(
            schemaVersion: 2,
            totalTrials: trials.count,
            groupCount: Set(trials.map(\.groupID)).count,
            complete: all.errors == 0 && missing == 0,
            completedTrials: completed,
            unsupportedTrials: all.unsupported,
            errorTrials: all.errors - missing,
            missingTrials: missing,
            coverage: ScoredMetric(count: completed, total: trials.count),
            nPositive: all.nPositive,
            nNegative: all.nNegative,
            nPreserve: nPreserve,
            nAbstain: nAbstain,
            truePositives: all.tp,
            fnNoAction: fnCounts[.fnNoAction, default: 0],
            fnWrongRepair: fnCounts[.fnWrongRepair, default: 0],
            fnWrongSource: fnCounts[.fnWrongSource, default: 0],
            fnUnsafeMutation: fnCounts[.fnUnsafeMutation, default: 0],
            fnTransientDamage: fnCounts[.fnTransientDamage, default: 0],
            fnError: fnCounts[.fnError, default: 0],
            falseNegatives: all.fn,
            trueNegatives: all.tn,
            textDamageFPs: all.textFP,
            layoutOnlyFPs: all.layoutFP,
            totalFPs: totalFPs,
            unauthorizedSourceChanges: unauthorizedSourceChanges,
            repairAttempts: attempts,
            recall: ScoredMetric(count: all.tp, total: all.nPositive),
            precision: ScoredMetric(count: all.tp, total: attempts),
            textDamageFPRate: ScoredMetric(count: all.textFP, total: all.nNegative),
            layoutOnlyFPRate: ScoredMetric(count: all.layoutFP, total: all.nNegative),
            totalFPRate: ScoredMetric(count: totalFPs, total: all.nNegative),
            unauthorizedSourceChangeRate: ScoredMetric(count: unauthorizedSourceChanges, total: all.nNegative),
            directionBreakdown: directions,
            categoryBreakdown: categories,
            reasonCodeCounts: reasonCounts,
            trialOutcomes: outcomes
        )
    }

    static func percent(_ value: Double?, digits: Int = 1) -> String {
        value.map { String(format: "%.\(digits)f%%", $0 * 100) } ?? "N/A"
    }

    static func metric(_ m: ScoredMetric, digits: Int = 1) -> String {
        "\(m.count) / \(m.total) | \(percent(m.rate, digits: digits)) | \(m.interval?.formatted ?? "N/A")"
    }

    public static func renderMarkdown(report: BenchmarkScoreReport, split: String, adapter: String) -> String {
        var lines: [String] = []
        lines.append("## Layout Reliability Benchmark Report")
        lines.append("")
        lines.append("- **Adapter**: `\(adapter)`")
        lines.append("- **Split**: `\(split)`")
        lines.append("- **Status**: \(report.complete ? "complete" : "INCOMPLETE — errors or missing observations; no quality gate may pass")")
        lines.append("- **Trials**: \(report.totalTrials) in \(report.groupCount) groups (\(report.nPositive) positive, \(report.nNegative) negative [\(report.nPreserve) preserve, \(report.nAbstain) abstain])")
        lines.append("- **Coverage**: \(report.completedTrials) completed, \(report.unsupportedTrials) unsupported, \(report.errorTrials) errors, \(report.missingTrials) missing")
        lines.append("")
        lines.append("### Primary Metrics")
        lines.append("")
        lines.append("| Metric | Count / Denominator | Rate | Wilson 95% CI |")
        lines.append("| --- | --- | --- | --- |")
        lines.append("| **Recall** (TP / N_positive) | \(metric(report.recall)) |")
        lines.append("| **Precision** (TP / trials with automatic attempts) | \(metric(report.precision)) |")
        lines.append("| **Text-Damage FP** (damage / N_negative) | \(metric(report.textDamageFPRate, digits: 2)) |")
        lines.append("| **Layout-Only FP** (switch without damage / N_negative) | \(metric(report.layoutOnlyFPRate, digits: 2)) |")
        lines.append("| **Union Intervention FP** | \(metric(report.totalFPRate, digits: 2)) |")
        lines.append("| **Any Unauthorized Source Change** | \(metric(report.unauthorizedSourceChangeRate, digits: 2)) |")
        lines.append("")
        lines.append("### Outcomes")
        lines.append("")
        lines.append("- **TP**: \(report.truePositives); **TN**: \(report.trueNegatives)")
        lines.append("- **FN**: \(report.falseNegatives) (no action \(report.fnNoAction), wrong repair \(report.fnWrongRepair), wrong source \(report.fnWrongSource), unsafe mutation \(report.fnUnsafeMutation), transient damage or too late \(report.fnTransientDamage), error \(report.fnError))")
        lines.append("- **FP**: text damage \(report.textDamageFPs), layout only \(report.layoutOnlyFPs)")
        lines.append("")
        lines.append("### Direction Breakdown")
        lines.append("")
        lines.append("| Direction | Trials | TP | FN | TN | Text FP | Layout FP | Errors | Unsupported | Recall | Text-Damage FP |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for dir in report.directionBreakdown.keys.sorted() {
            guard let d = report.directionBreakdown[dir] else { continue }
            lines.append("| \(dir) | \(d.total) | \(d.tp) | \(d.fn) | \(d.tn) | \(d.textFP) | \(d.layoutFP) | \(d.errors) | \(d.unsupported) | \(percent(d.recall)) | \(percent(d.textDamageFPRate, digits: 2)) |")
        }
        if !report.reasonCodeCounts.isEmpty {
            lines.append("")
            lines.append("### Reason Codes")
            lines.append("")
            lines.append("| Code | Trials |")
            lines.append("| --- | --- |")
            for code in report.reasonCodeCounts.keys.sorted() {
                lines.append("| `\(code)` | \(report.reasonCodeCounts[code] ?? 0) |")
            }
        }
        return lines.joined(separator: "\n")
    }
}
