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

public enum TrialClassification: String, Codable, Equatable, Sendable {
    case truePositive = "TP"
    case falseNegativeNoAction = "FN_no_action"
    case falseNegativeWrongRepair = "FN_wrong_repair"
    case falseNegativeUnsafeMutation = "FN_unsafe_mutation"
    case trueNegative = "TN"
    case textDamageFP = "FP_text_damage"
    case layoutOnlyFP = "FP_layout_only"
    case unsupported = "unsupported"
    case error = "error"
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

public struct BenchmarkScoreReport: Codable, Equatable, Sendable {
    public let totalTrials: Int
    public let nPositive: Int
    public let nNegative: Int
    public let nPreserve: Int
    public let nAbstain: Int

    public let truePositives: Int
    public let fnNoAction: Int
    public let fnWrongRepair: Int
    public let fnUnsafeMutation: Int
    public let falseNegatives: Int

    public let trueNegatives: Int
    public let textDamageFPs: Int
    public let layoutOnlyFPs: Int
    public let totalFPs: Int

    public let recall: ScoredMetric
    public let precision: ScoredMetric
    public let textDamageFPRate: ScoredMetric
    public let layoutOnlyFPRate: ScoredMetric
    public let totalFPRate: ScoredMetric

    public let directionBreakdown: [String: DirectionScoreSummary]
    public let categoryBreakdown: [String: CategoryScoreSummary]
}

public struct DirectionScoreSummary: Codable, Equatable, Sendable {
    public let direction: String
    public let total: Int
    public let tp: Int
    public let fn: Int
    public let tn: Int
    public let textFP: Int
    public let layoutFP: Int
    public let recall: Double?
    public let textDamageFPRate: Double?
}

public struct CategoryScoreSummary: Codable, Equatable, Sendable {
    public let category: String
    public let total: Int
    public let tp: Int
    public let fn: Int
    public let tn: Int
    public let fp: Int
}

public enum Scorer {
    public static func score(trials: [Trial], results: [TrialResult]) -> BenchmarkScoreReport {
        var resultsMap: [String: TrialResult] = [:]
        for r in results {
            resultsMap[r.trialID] = r
        }

        var tp = 0
        var fnNoAction = 0
        var fnWrongRepair = 0
        var fnUnsafeMutation = 0
        var tn = 0
        var textFP = 0
        var layoutFP = 0

        var nPositive = 0
        var nPreserve = 0
        var nAbstain = 0

        var dirStats: [String: (total: Int, tp: Int, fn: Int, tn: Int, textFP: Int, layoutFP: Int, nPos: Int, nNeg: Int)] = [:]
        var catStats: [String: (total: Int, tp: Int, fn: Int, tn: Int, fp: Int)] = [:]

        for trial in trials {
            guard let res = resultsMap[trial.id] else { continue }

            let direction: String
            if trial.initial.language == "en" {
                direction = "EN -> UK"
            } else {
                direction = "UK -> EN"
            }

            var d = dirStats[direction] ?? (0, 0, 0, 0, 0, 0, 0, 0)
            d.total += 1

            var c = catStats[trial.category] ?? (0, 0, 0, 0, 0)
            c.total += 1

            if trial.label == "repair" {
                nPositive += 1
                d.nPos += 1

                let hasActions = !res.actions.isEmpty
                let textMatches = (res.finalText == trial.expected.text)
                let sourceMatches = (res.finalSourceID == trial.expected.sourceID)

                if textMatches && sourceMatches {
                    tp += 1
                    d.tp += 1
                    c.tp += 1
                } else if !hasActions {
                    fnNoAction += 1
                    d.fn += 1
                    c.fn += 1
                } else if res.finalText != trial.expected.text {
                    fnWrongRepair += 1
                    d.fn += 1
                    c.fn += 1
                } else {
                    fnUnsafeMutation += 1
                    d.fn += 1
                    c.fn += 1
                }
            } else {
                if trial.label == "preserve" {
                    nPreserve += 1
                } else {
                    nAbstain += 1
                }
                d.nNeg += 1

                let hasTextMutation = res.actions.contains { $0.type == "replaceSuffix" } || res.finalText != trial.expected.text
                let hasSourceSwitch = res.actions.contains { $0.type == "switchSource" } || res.finalSourceID != trial.expected.sourceID

                if hasTextMutation {
                    textFP += 1
                    d.textFP += 1
                    c.fp += 1
                } else if hasSourceSwitch {
                    layoutFP += 1
                    d.layoutFP += 1
                    c.fp += 1
                } else {
                    tn += 1
                    d.tn += 1
                    c.tn += 1
                }
            }

            dirStats[direction] = d
            catStats[trial.category] = c
        }

        let fnTotal = fnNoAction + fnWrongRepair + fnUnsafeMutation
        let nNegative = nPreserve + nAbstain
        let totalFPs = textFP + layoutFP
        let totalTrials = nPositive + nNegative

        let recallMetric = ScoredMetric(count: tp, total: nPositive)
        let totalRepairAttempts = tp + totalFPs + fnWrongRepair
        let precisionMetric = ScoredMetric(count: tp, total: totalRepairAttempts)
        let textDamageFPMetric = ScoredMetric(count: textFP, total: nNegative)
        let layoutOnlyFPMetric = ScoredMetric(count: layoutFP, total: nNegative)
        let totalFPMetric = ScoredMetric(count: totalFPs, total: nNegative)

        var directionSummaries: [String: DirectionScoreSummary] = [:]
        for (k, v) in dirStats {
            let rec = v.nPos > 0 ? Double(v.tp) / Double(v.nPos) : nil
            let fpRate = v.nNeg > 0 ? Double(v.textFP) / Double(v.nNeg) : nil
            directionSummaries[k] = DirectionScoreSummary(
                direction: k,
                total: v.total,
                tp: v.tp,
                fn: v.fn,
                tn: v.tn,
                textFP: v.textFP,
                layoutFP: v.layoutFP,
                recall: rec,
                textDamageFPRate: fpRate
            )
        }

        var categorySummaries: [String: CategoryScoreSummary] = [:]
        for (k, v) in catStats {
            categorySummaries[k] = CategoryScoreSummary(
                category: k,
                total: v.total,
                tp: v.tp,
                fn: v.fn,
                tn: v.tn,
                fp: v.fp
            )
        }

        return BenchmarkScoreReport(
            totalTrials: totalTrials,
            nPositive: nPositive,
            nNegative: nNegative,
            nPreserve: nPreserve,
            nAbstain: nAbstain,
            truePositives: tp,
            fnNoAction: fnNoAction,
            fnWrongRepair: fnWrongRepair,
            fnUnsafeMutation: fnUnsafeMutation,
            falseNegatives: fnTotal,
            trueNegatives: tn,
            textDamageFPs: textFP,
            layoutOnlyFPs: layoutFP,
            totalFPs: totalFPs,
            recall: recallMetric,
            precision: precisionMetric,
            textDamageFPRate: textDamageFPMetric,
            layoutOnlyFPRate: layoutOnlyFPMetric,
            totalFPRate: totalFPMetric,
            directionBreakdown: directionSummaries,
            categoryBreakdown: categorySummaries
        )
    }

    public static func renderMarkdown(report: BenchmarkScoreReport, split: String, adapter: String) -> String {
        var lines: [String] = []
        lines.append("## Layout Reliability Benchmark Report")
        lines.append("")
        lines.append("- **Adapter**: `\(adapter)`")
        lines.append("- **Split**: `\(split)`")
        lines.append("- **Total Trials**: \(report.totalTrials) (\(report.nPositive) positive, \(report.nNegative) negative [\(report.nPreserve) preserve, \(report.nAbstain) abstain])")
        lines.append("")

        lines.append("### Primary Metrics")
        lines.append("")
        lines.append("| Metric | Count / Denominator | Rate | Wilson 95% CI |")
        lines.append("| --- | --- | --- | --- |")

        let recallRateStr = report.recall.rate.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A"
        let recallCIStr = report.recall.interval?.formatted ?? "N/A"
        lines.append("| **Recall** (TP / N_positive) | \(report.truePositives) / \(report.nPositive) | \(recallRateStr) | \(recallCIStr) |")

        let precRateStr = report.precision.rate.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A"
        let precCIStr = report.precision.interval?.formatted ?? "N/A"
        lines.append("| **Precision** (TP / attempts) | \(report.truePositives) / \(report.precision.total) | \(precRateStr) | \(precCIStr) |")

        let textFPRateStr = report.textDamageFPRate.rate.map { String(format: "%.2f%%", $0 * 100) } ?? "N/A"
        let textFPCIStr = report.textDamageFPRate.interval?.formatted ?? "N/A"
        lines.append("| **Text-Damage FP** (damage / N_neg) | \(report.textDamageFPs) / \(report.nNegative) | \(textFPRateStr) | \(textFPCIStr) |")

        let layoutFPRateStr = report.layoutOnlyFPRate.rate.map { String(format: "%.2f%%", $0 * 100) } ?? "N/A"
        let layoutFPCIStr = report.layoutOnlyFPRate.interval?.formatted ?? "N/A"
        lines.append("| **Layout-Only FP** (switch / N_neg) | \(report.layoutOnlyFPs) / \(report.nNegative) | \(layoutFPRateStr) | \(layoutFPCIStr) |")

        let totalFPRateStr = report.totalFPRate.rate.map { String(format: "%.2f%%", $0 * 100) } ?? "N/A"
        let totalFPCIStr = report.totalFPRate.interval?.formatted ?? "N/A"
        lines.append("| **Union Intervention FP** | \(report.totalFPs) / \(report.nNegative) | \(totalFPRateStr) | \(totalFPCIStr) |")

        lines.append("")
        lines.append("### Outcomes Breakdown")
        lines.append("")
        lines.append("- **True Positives (TP)**: \(report.truePositives)")
        lines.append("- **False Negatives (FN)**: \(report.falseNegatives) (No action: \(report.fnNoAction), Wrong repair: \(report.fnWrongRepair), Unsafe: \(report.fnUnsafeMutation))")
        lines.append("- **True Negatives (TN)**: \(report.trueNegatives)")
        lines.append("- **Text-Damage False Positives**: \(report.textDamageFPs)")
        lines.append("- **Layout-Only False Positives**: \(report.layoutOnlyFPs)")

        lines.append("")
        lines.append("### Direction Breakdown")
        lines.append("")
        lines.append("| Direction | Trials | TP | FN | TN | Text FP | Layout FP | Recall | Text-Damage FP |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")

        for dir in report.directionBreakdown.keys.sorted() {
            guard let d = report.directionBreakdown[dir] else { continue }
            let recStr = d.recall.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A"
            let fpStr = d.textDamageFPRate.map { String(format: "%.2f%%", $0 * 100) } ?? "N/A"
            lines.append("| \(d.direction) | \(d.total) | \(d.tp) | \(d.fn) | \(d.tn) | \(d.textFP) | \(d.layoutFP) | \(recStr) | \(fpStr) |")
        }

        return lines.joined(separator: "\n")
    }
}
