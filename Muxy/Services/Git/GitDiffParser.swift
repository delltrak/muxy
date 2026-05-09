import Foundation

struct ParsedDiffRows {
    let rows: [DiffDisplayRow]
    let additions: Int
    let deletions: Int
}

enum GitDiffParser {
    static func parseRows(_ patch: String) -> ParsedDiffRows {
        var rows: [DiffDisplayRow] = []
        var oldLineNumber = 0
        var newLineNumber = 0
        var inHunk = false
        var additions = 0
        var deletions = 0

        for rawLine in patch.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if rawLine.hasPrefix("@@") {
                inHunk = true
                let (oldStart, newStart) = parseHunkHeader(rawLine)
                oldLineNumber = oldStart
                newLineNumber = newStart
                rows.append(DiffDisplayRow(
                    kind: .hunk,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    oldText: nil,
                    newText: nil,
                    text: String(rawLine)
                ))
                continue
            }

            guard inHunk else { continue }

            guard let prefix = rawLine.first else { continue }

            switch prefix {
            case " ":
                let content = String(rawLine.dropFirst())
                rows.append(DiffDisplayRow(
                    kind: .context,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: newLineNumber,
                    oldText: content,
                    newText: content,
                    text: String(rawLine)
                ))
                oldLineNumber += 1
                newLineNumber += 1
            case "-":
                let content = String(rawLine.dropFirst())
                rows.append(DiffDisplayRow(
                    kind: .deletion,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    oldText: content,
                    newText: nil,
                    text: String(rawLine)
                ))
                oldLineNumber += 1
                deletions += 1
            case "+":
                let content = String(rawLine.dropFirst())
                rows.append(DiffDisplayRow(
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    oldText: nil,
                    newText: content,
                    text: String(rawLine)
                ))
                newLineNumber += 1
                additions += 1
            default:
                continue
            }
        }

        return ParsedDiffRows(rows: rows, additions: additions, deletions: deletions)
    }

    static func collapseContextRows(_ rows: [DiffDisplayRow]) -> [DiffDisplayRow] {
        var output: [DiffDisplayRow] = []
        var index = 0
        let leadingContext = 3
        let trailingContext = 3
        let collapseThreshold = 12

        while index < rows.count {
            let row = rows[index]
            if row.kind != .context {
                output.append(row)
                index += 1
                continue
            }

            var end = index
            while end < rows.count, rows[end].kind == .context {
                end += 1
            }
            let runLength = end - index

            if runLength <= collapseThreshold {
                output.append(contentsOf: rows[index ..< end])
            } else {
                let startKeepEnd = index + leadingContext
                let endKeepStart = end - trailingContext
                output.append(contentsOf: rows[index ..< startKeepEnd])
                output.append(DiffDisplayRow(
                    kind: .collapsed,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    oldText: nil,
                    newText: nil,
                    text: "\(runLength - leadingContext - trailingContext) unmodified lines"
                ))
                output.append(contentsOf: rows[endKeepStart ..< end])
            }
            index = end
        }

        return output
    }

    static func parseHunkHeader(_ line: some StringProtocol) -> (Int, Int) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return (0, 0) }

        let oldNumber = parseHunkNumber(parts[1])
        let newNumber = parseHunkNumber(parts[2])
        return (oldNumber, newNumber)
    }

    static func parseHunkNumber(_ token: some StringProtocol) -> Int {
        var slice = Substring(token)
        while let first = slice.first, first == "-" || first == "+" || first == "," {
            slice = slice.dropFirst()
        }
        guard let start = slice.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return 0
        }
        return Int(start) ?? 0
    }
}
