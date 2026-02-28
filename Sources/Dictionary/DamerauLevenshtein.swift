import Foundation

enum DamerauLevenshtein {
    struct Workspace {
        var prev2: [Int] = []
        var prev1: [Int] = []
        var current: [Int] = []

        mutating func ensureCapacity(_ size: Int) {
            if prev2.count < size {
                prev2 = Array(repeating: 0, count: size)
                prev1 = Array(repeating: 0, count: size)
                current = Array(repeating: 0, count: size)
            }
        }
    }

    static func distance(
        _ a: String,
        _ b: String,
        maxDistance: Int,
        workspace: inout Workspace
    ) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count

        if abs(n - m) > maxDistance { return maxDistance + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        let rowSize = m + 1
        workspace.ensureCapacity(rowSize)

        for j in 0...m {
            workspace.prev1[j] = j
            workspace.prev2[j] = j
        }

        for i in 1...n {
            workspace.current[0] = i
            var minRowValue = workspace.current[0]

            for j in 1...m {
                let cost = (aChars[i - 1] == bChars[j - 1]) ? 0 : 1
                var value = min(
                    workspace.prev1[j] + 1,
                    workspace.current[j - 1] + 1,
                    workspace.prev1[j - 1] + cost
                )

                if i > 1,
                   j > 1,
                   aChars[i - 1] == bChars[j - 2],
                   aChars[i - 2] == bChars[j - 1] {
                    value = min(value, workspace.prev2[j - 2] + 1)
                }

                workspace.current[j] = value
                if value < minRowValue {
                    minRowValue = value
                }
            }

            if minRowValue > maxDistance {
                return maxDistance + 1
            }

            swap(&workspace.prev2, &workspace.prev1)
            swap(&workspace.prev1, &workspace.current)
        }

        return workspace.prev1[m]
    }
}
