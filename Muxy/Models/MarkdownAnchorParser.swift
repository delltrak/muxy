import Foundation

enum MarkdownAnchorParser {
    static func parseAnchors(in markdown: String) -> [MarkdownSyncAnchor] {
        let lines = splitLines(markdown)
        guard !lines.isEmpty else { return [] }

        var anchors: [MarkdownSyncAnchor] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = trimWhitespaceAndNewlines(line)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(in: trimmed) {
                let endIndex = findFenceEnd(for: fence, lines: lines, startIndex: index)
                anchors.append(makeAnchor(kind: fence.kind, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
                index = endIndex + 1
                continue
            }

            if isHeading(trimmed) {
                anchors.append(makeAnchor(kind: .heading, startIndex: index, endIndex: index, ordinal: anchors.count))
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                anchors.append(makeAnchor(kind: .thematicBreak, startIndex: index, endIndex: index, ordinal: anchors.count))
                index += 1
                continue
            }

            if isTableHeader(lines: lines, index: index) {
                let endIndex = consumeTable(lines: lines, startIndex: index)
                anchors.append(makeAnchor(kind: .table, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
                index = endIndex + 1
                continue
            }

            if isStandaloneImage(trimmed) {
                anchors.append(makeAnchor(kind: .image, startIndex: index, endIndex: index, ordinal: anchors.count))
                index += 1
                continue
            }

            if isHTMLBlockStart(trimmed) {
                let endIndex = consumeHTMLBlock(lines: lines, startIndex: index)
                anchors.append(makeAnchor(kind: .htmlBlock, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
                index = endIndex + 1
                continue
            }

            if isBlockquote(trimmed) {
                let endIndex = consumeBlockquote(lines: lines, startIndex: index)
                anchors.append(makeAnchor(kind: .blockquote, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
                index = endIndex + 1
                continue
            }

            if isListStart(trimmed) {
                let endIndex = consumeList(lines: lines, startIndex: index)
                anchors.append(makeAnchor(kind: .list, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
                index = endIndex + 1
                continue
            }

            let endIndex = consumeParagraph(lines: lines, startIndex: index)
            anchors.append(makeAnchor(kind: .paragraph, startIndex: index, endIndex: endIndex, ordinal: anchors.count))
            index = endIndex + 1
        }

        return anchors
    }

    private struct FenceStart {
        let marker: Character
        let count: Int
        let kind: MarkdownSyncAnchorKind
    }

    private static func splitLines(_ markdown: String) -> [Substring] {
        var lines: [Substring] = []
        var lineStart = markdown.startIndex
        var index = markdown.startIndex
        let endIndex = markdown.endIndex

        while index < endIndex {
            let character = markdown[index]
            if character == "\n" {
                lines.append(markdown[lineStart ..< index])
                index = markdown.index(after: index)
                lineStart = index
                continue
            }
            if character == "\r" {
                lines.append(markdown[lineStart ..< index])
                let next = markdown.index(after: index)
                if next < endIndex, markdown[next] == "\n" {
                    index = markdown.index(after: next)
                } else {
                    index = next
                }
                lineStart = index
                continue
            }
            index = markdown.index(after: index)
        }
        lines.append(markdown[lineStart ..< endIndex])
        return lines
    }

    private static func makeAnchor(kind: MarkdownSyncAnchorKind, startIndex: Int, endIndex: Int, ordinal: Int) -> MarkdownSyncAnchor {
        MarkdownSyncAnchor(
            id: "anchor-\(kind.rawValue)-\(ordinal + 1)",
            kind: kind,
            startLine: startIndex + 1,
            endLine: endIndex + 1
        )
    }

    private static func fenceStart(in trimmed: Substring) -> FenceStart? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let markerCount = trimmed.prefix { $0 == marker }.count
        guard markerCount >= 3 else { return nil }
        let rest = trimWhitespace(trimmed.dropFirst(markerCount))
        let infoToken = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        let kind: MarkdownSyncAnchorKind = if let infoToken, infoToken.lowercased() == "mermaid" {
            .mermaid
        } else {
            .fencedCode
        }
        return FenceStart(marker: marker, count: markerCount, kind: kind)
    }

    private static func findFenceEnd(for fence: FenceStart, lines: [Substring], startIndex: Int) -> Int {
        guard startIndex + 1 < lines.count else { return startIndex }
        for candidate in (startIndex + 1) ..< lines.count {
            let trimmed = trimWhitespace(lines[candidate])
            let prefixCount = trimmed.prefix { $0 == fence.marker }.count
            if prefixCount >= fence.count, trimWhitespace(trimmed.dropFirst(prefixCount)).isEmpty {
                return candidate
            }
        }
        return lines.count - 1
    }

    private static func isHeading(_ trimmed: Substring) -> Bool {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(hashes) else { return false }
        guard trimmed.count > hashes else { return false }
        let next = trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)]
        return next.isWhitespace
    }

    private static func isThematicBreak(_ trimmed: Substring) -> Bool {
        guard let first = trimmed.first(where: { !$0.isWhitespace }), first == "-" || first == "*" || first == "_" else {
            return false
        }
        var nonSpaceCount = 0
        for character in trimmed {
            if character == " " { continue }
            if character != first { return false }
            nonSpaceCount += 1
        }
        return nonSpaceCount >= 3
    }

    private static func isTableHeader(lines: [Substring], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = trimWhitespace(lines[index])
        let separator = trimWhitespace(lines[index + 1])
        guard header.contains("|") else { return false }
        return isTableSeparator(separator)
    }

    private static func isTableSeparator(_ trimmed: Substring) -> Bool {
        var hasPipe = false
        var hasDash = false
        for character in trimmed {
            if character == " " { continue }
            switch character {
            case "|": hasPipe = true
            case "-": hasDash = true
            case ":": break
            default: return false
            }
        }
        return hasPipe && hasDash
    }

    private static func consumeTable(lines: [Substring], startIndex: Int) -> Int {
        var index = startIndex + 2
        var last = startIndex + 1
        while index < lines.count {
            let trimmed = trimWhitespace(lines[index])
            if trimmed.isEmpty || !trimmed.contains("|") {
                break
            }
            last = index
            index += 1
        }
        return last
    }

    private static func isStandaloneImage(_ trimmed: Substring) -> Bool {
        guard trimmed.hasPrefix("!["), trimmed.contains("]("), trimmed.hasSuffix(")") else { return false }
        return !trimmed.contains(" ") || trimmed.first == "!"
    }

    private static func isHTMLBlockStart(_ trimmed: Substring) -> Bool {
        guard trimmed.hasPrefix("<"), !trimmed.hasPrefix("<!--") else { return false }
        return !trimmed.hasPrefix("<http")
    }

    private static func consumeHTMLBlock(lines: [Substring], startIndex: Int) -> Int {
        var index = startIndex
        var last = startIndex
        while index < lines.count {
            let trimmed = trimWhitespace(lines[index])
            if index > startIndex, trimmed.isEmpty {
                break
            }
            last = index
            index += 1
        }
        return last
    }

    private static func isBlockquote(_ trimmed: Substring) -> Bool {
        trimmed.hasPrefix(">")
    }

    private static func consumeBlockquote(lines: [Substring], startIndex: Int) -> Int {
        var index = startIndex
        var last = startIndex
        while index < lines.count {
            let trimmed = trimWhitespace(lines[index])
            if trimmed.isEmpty {
                last = index
                index += 1
                continue
            }
            guard isBlockquote(trimmed) else { break }
            last = index
            index += 1
        }
        return last
    }

    private static func isListStart(_ trimmed: Substring) -> Bool {
        unorderedListMarkerLength(in: trimmed) != nil || orderedListMarkerLength(in: trimmed) != nil
    }

    private static func unorderedListMarkerLength(in trimmed: Substring) -> Int? {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "+" else { return nil }
        guard trimmed.count > 1 else { return nil }
        let next = trimmed[trimmed.index(after: trimmed.startIndex)]
        return next.isWhitespace ? 1 : nil
    }

    private static func orderedListMarkerLength(in trimmed: Substring) -> Int? {
        var digits = 0
        for character in trimmed {
            if character.isNumber {
                digits += 1
                continue
            }
            guard digits > 0, character == "." || character == ")" else { return nil }
            let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: digits + 1)
            guard markerIndex < trimmed.endIndex else { return nil }
            return trimmed[markerIndex].isWhitespace ? digits + 1 : nil
        }
        return nil
    }

    private static func consumeList(lines: [Substring], startIndex: Int) -> Int {
        var index = startIndex + 1
        var last = startIndex
        while index < lines.count {
            let line = lines[index]
            let trimmed = trimWhitespace(line)
            if trimmed.isEmpty {
                break
            }
            if isListStart(trimmed) || isIndented(line) {
                last = index
                index += 1
                continue
            }
            break
        }
        return last
    }

    private static func isIndented(_ line: Substring) -> Bool {
        var count = 0
        for character in line {
            guard character == " " || character == "\t" else { break }
            count += 1
            if count >= 2 { return true }
        }
        return count >= 2
    }

    private static func consumeParagraph(lines: [Substring], startIndex: Int) -> Int {
        var index = startIndex + 1
        var last = startIndex
        while index < lines.count {
            let trimmed = trimWhitespace(lines[index])
            if trimmed.isEmpty || startsNewBlock(lines: lines, index: index) {
                break
            }
            last = index
            index += 1
        }
        return last
    }

    private static func startsNewBlock(lines: [Substring], index: Int) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = trimWhitespace(lines[index])
        if trimmed.isEmpty {
            return false
        }
        if fenceStart(in: trimmed) != nil {
            return true
        }
        return isHeading(trimmed)
            || isThematicBreak(trimmed)
            || isTableHeader(lines: lines, index: index)
            || isStandaloneImage(trimmed)
            || isHTMLBlockStart(trimmed)
            || isBlockquote(trimmed)
            || isListStart(trimmed)
    }

    private static func trimWhitespace(_ slice: Substring) -> Substring {
        var start = slice.startIndex
        var end = slice.endIndex
        while start < end, slice[start] == " " || slice[start] == "\t" {
            start = slice.index(after: start)
        }
        while end > start {
            let prev = slice.index(before: end)
            let character = slice[prev]
            if character == " " || character == "\t" {
                end = prev
            } else {
                break
            }
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
            let character = slice[prev]
            if character.isWhitespace || character.isNewline {
                end = prev
            } else {
                break
            }
        }
        return slice[start ..< end]
    }
}
