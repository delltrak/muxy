import Foundation

final class SyntaxHighlighter: @unchecked Sendable {
    struct AppliedSpan {
        let range: NSRange
        let scope: SyntaxScope
    }

    struct LineTokens {
        let tokens: [TokenSpan]
        let endState: LineEndState
    }

    enum EditOutcome {
        case updated
        case cascade
    }

    let grammar: SyntaxGrammar
    private let tokenizer: SyntaxTokenizer
    private let lock = NSLock()
    private var cache: [LineTokens] = []

    static let longLineThreshold = 10000
    static let viewportTokenWindow = 5000

    init(grammar: SyntaxGrammar) {
        self.grammar = grammar
        self.tokenizer = SyntaxTokenizer(grammar: grammar)
    }

    func reset() {
        lock.lock()
        cache.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func invalidate(fromLine index: Int) {
        lock.lock()
        let target = max(0, index)
        if target < cache.count {
            cache.removeSubrange(target ..< cache.count)
        }
        lock.unlock()
    }

    func tokens(forLine line: Int) -> [TokenSpan]? {
        lock.lock()
        defer { lock.unlock() }
        guard cache.indices.contains(line) else { return nil }
        return cache[line].tokens
    }

    func lineStartState(at line: Int) -> LineEndState {
        lock.lock()
        defer { lock.unlock() }
        guard line > 0, line - 1 < cache.count else { return .normal }
        return cache[line - 1].endState
    }

    @MainActor
    func applyEdit(
        startLine: Int,
        oldLineCount: Int,
        newLineCount: Int,
        backingStore: TextBackingStore
    ) -> EditOutcome {
        let oldEndLine = startLine + oldLineCount
        let newEndLine = startLine + newLineCount

        lock.lock()
        let priorBoundaryState: LineEndState? = if oldEndLine >= 1, oldEndLine - 1 < cache.count {
            cache[oldEndLine - 1].endState
        } else {
            nil
        }

        if startLine < cache.count {
            let removeEnd = min(oldEndLine, cache.count)
            cache.removeSubrange(startLine ..< removeEnd)
        }

        var state: LineEndState = startLine == 0
            ? .normal
            : (startLine - 1 < cache.count ? cache[startLine - 1].endState : .normal)
        lock.unlock()

        let availableLines = max(0, backingStore.lineCount - startLine)
        let tokenizeCount = min(newLineCount, availableLines)
        var newEntries: [LineTokens] = []
        newEntries.reserveCapacity(tokenizeCount)
        for offset in 0 ..< tokenizeCount {
            let line = backingStore.line(at: startLine + offset)
            let result = tokenize(line: line, startState: state)
            newEntries.append(result)
            state = result.endState
        }

        lock.lock()
        defer { lock.unlock() }

        guard !newEntries.isEmpty || newLineCount == 0 else {
            if let priorBoundaryState, priorBoundaryState != state, newEndLine < cache.count {
                cache.removeSubrange(newEndLine ..< cache.count)
                return .cascade
            }
            return .updated
        }

        let insertIndex = min(startLine, cache.count)
        cache.insert(contentsOf: newEntries, at: insertIndex)

        let newBoundaryState = tokenizeCount > 0 ? state : priorBoundaryState ?? .normal
        let hasDownstream = newEndLine < cache.count
        let cascade: Bool = if let priorBoundaryState {
            priorBoundaryState != newBoundaryState
        } else {
            hasDownstream
        }

        if cascade, newEndLine < cache.count {
            cache.removeSubrange(newEndLine ..< cache.count)
        }

        return cascade ? .cascade : .updated
    }

    @MainActor
    func spans(
        in range: Range<Int>,
        lineStartOffsets: [Int],
        backingStore: TextBackingStore
    ) -> [AppliedSpan] {
        ensureCached(upTo: range.upperBound, backingStore: backingStore)
        lock.lock()
        defer { lock.unlock() }
        let upper = min(range.upperBound, cache.count)
        guard range.lowerBound < upper else { return [] }

        let offsetsCount = lineStartOffsets.count
        var spans: [AppliedSpan] = []
        spans.reserveCapacity((upper - range.lowerBound) * 8)

        for localIndex in 0 ..< (upper - range.lowerBound) {
            let globalLine = range.lowerBound + localIndex
            let lineOffset = localIndex < offsetsCount ? lineStartOffsets[localIndex] : 0
            for token in cache[globalLine].tokens {
                spans.append(AppliedSpan(
                    range: NSRange(location: lineOffset + token.location, length: token.length),
                    scope: token.scope
                ))
            }
        }
        return spans
    }

    @MainActor
    private func ensureCached(upTo target: Int, backingStore: TextBackingStore) {
        lock.lock()
        if cache.count > backingStore.lineCount {
            cache.removeSubrange(backingStore.lineCount ..< cache.count)
        }
        let limit = min(target, backingStore.lineCount)
        guard cache.count < limit else {
            lock.unlock()
            return
        }
        cache.reserveCapacity(limit)
        var state: LineEndState = cache.isEmpty ? .normal : cache[cache.count - 1].endState
        var index = cache.count
        lock.unlock()

        var pending: [LineTokens] = []
        pending.reserveCapacity(limit - index)
        while index < limit {
            let line = backingStore.line(at: index)
            let result = tokenize(line: line, startState: state)
            pending.append(result)
            state = result.endState
            index += 1
        }

        lock.lock()
        cache.append(contentsOf: pending)
        lock.unlock()
    }

    func trimCacheForViewport(centeredOn viewportLine: Int) {
        lock.lock()
        defer { lock.unlock() }
        let count = cache.count
        let window = Self.viewportTokenWindow
        guard count > window * 2 else { return }
        let start = max(0, viewportLine - window)
        let end = min(count, viewportLine + window)
        guard start > 0 || end < count else { return }
        if end < count {
            cache.removeSubrange(end ..< count)
        }
        if start > 0 {
            for index in 0 ..< start {
                cache[index] = LineTokens(tokens: [], endState: cache[index].endState)
            }
        }
    }

    private func tokenize(line: String, startState: LineEndState) -> LineTokens {
        if line.utf16.count > Self.longLineThreshold {
            return LineTokens(tokens: [], endState: startState)
        }
        let result = tokenizer.tokenize(line: line, startState: startState)
        return LineTokens(tokens: result.tokens, endState: result.endState)
    }
}
