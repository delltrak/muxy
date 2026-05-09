import Foundation

enum GitCommitLogParser {
    static let fieldSeparator = "\u{1F}"
    static let recordSeparator = "\u{1E}"

    static let logFormat = [
        "%H", "%h", "%s", "%an", "%aI", "%D", "%P",
    ].joined(separator: fieldSeparator) + recordSeparator

    private static let fieldSeparatorChar = Character(fieldSeparator)
    private static let recordSeparatorChar = Character(recordSeparator)

    static func parseCommitLog(_ raw: String) -> [GitCommit] {
        let records = raw.split(separator: recordSeparatorChar, omittingEmptySubsequences: true)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        return records.compactMap { record in
            let trimmed = trimWhitespaceAndNewlines(record)
            let fields = trimmed
                .split(separator: fieldSeparatorChar, maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count >= 7 else { return nil }

            let dateString = fields[4]
            let date = dateFormatter.date(from: String(dateString)) ?? Date.distantPast
            let refs = parseRefs(fields[5])
            let parents = fields[6]
                .split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)

            return GitCommit(
                hash: String(fields[0]),
                shortHash: String(fields[1]),
                subject: String(fields[2]),
                authorName: String(fields[3]),
                authorDate: date,
                refs: refs,
                parentHashes: parents
            )
        }
    }

    static func parseRefs(_ raw: some StringProtocol) -> [GitRef] {
        guard !raw.isEmpty else { return [] }
        let slice = Substring(raw)
        return slice.split(separator: ",").compactMap { segment in
            let trimmed = trimWhitespace(segment)
            if trimmed == "HEAD" {
                return GitRef(name: "HEAD", kind: .head)
            }
            if let suffix = stripPrefix(trimmed, prefix: "HEAD -> ") {
                let branch = stripPrefix(suffix, prefix: "refs/heads/") ?? suffix
                return GitRef(name: String(branch), kind: .localBranch)
            }
            if let suffix = stripPrefix(trimmed, prefix: "tag: ") {
                let tag = stripPrefix(suffix, prefix: "refs/tags/") ?? suffix
                return GitRef(name: String(tag), kind: .tag)
            }
            if let suffix = stripPrefix(trimmed, prefix: "refs/heads/") {
                return GitRef(name: String(suffix), kind: .localBranch)
            }
            if let suffix = stripPrefix(trimmed, prefix: "refs/remotes/") {
                return GitRef(name: String(suffix), kind: .remoteBranch)
            }
            if let suffix = stripPrefix(trimmed, prefix: "refs/tags/") {
                return GitRef(name: String(suffix), kind: .tag)
            }
            return GitRef(name: String(trimmed), kind: .localBranch)
        }
    }

    private static func trimWhitespace(_ slice: Substring) -> Substring {
        var start = slice.startIndex
        var end = slice.endIndex
        while start < end, slice[start].isWhitespace {
            start = slice.index(after: start)
        }
        while end > start, slice[slice.index(before: end)].isWhitespace {
            end = slice.index(before: end)
        }
        return slice[start ..< end]
    }

    private static func trimWhitespaceAndNewlines(_ slice: Substring) -> Substring {
        var start = slice.startIndex
        var end = slice.endIndex
        while start < end, slice[start].isWhitespace || slice[start].isNewline {
            start = slice.index(after: start)
        }
        while end > start {
            let prev = slice.index(before: end)
            if slice[prev].isWhitespace || slice[prev].isNewline {
                end = prev
            } else {
                break
            }
        }
        return slice[start ..< end]
    }

    private static func stripPrefix(_ slice: Substring, prefix: String) -> Substring? {
        guard slice.hasPrefix(prefix) else { return nil }
        return slice.dropFirst(prefix.count)
    }
}
