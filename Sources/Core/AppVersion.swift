import Foundation

/// 版本号比较：支持 `v0.3.0`、`0.3`、`0.3.0-beta` 等常见 tag。
/// 只比较数字段；数字相同的情况下，正式版高于预发布版。
struct AppVersion: Comparable {

    let numbers: [Int]
    let prerelease: String?

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(where: { $0.isNumber }) else {
            return nil
        }

        let text = String(trimmed[start...])
        let pieces = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces[0]

        var parsed: [Int] = []
        for piece in core.split(separator: ".") {
            let digits = piece.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else {
                return nil
            }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }

        numbers = parsed
        prerelease = pieces.count > 1 && !pieces[1].isEmpty ? String(pieces[1]) : nil
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return 0
        case (nil, _):
            return 1
        case (_, nil):
            return -1
        case let (left?, right?):
            if left == right { return 0 }
            return left < right ? -1 : 1
        }
    }
}
