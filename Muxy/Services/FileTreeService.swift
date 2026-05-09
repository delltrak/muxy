import Foundation

struct FileTreeEntry: Hashable {
    let name: String
    let absolutePath: String
    let relativePath: String
    let isDirectory: Bool
    let isIgnored: Bool
}

enum FileTreeService {
    static func loadChildren(of directoryAbsolutePath: String, repoRoot: String) async -> [FileTreeEntry] {
        await GitProcessRunner.offMain {
            loadChildrenSync(of: directoryAbsolutePath, repoRoot: repoRoot)
        }
    }

    private static func loadChildrenSync(of directoryAbsolutePath: String, repoRoot: String) -> [FileTreeEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directoryAbsolutePath) else {
            return []
        }

        let classification = classifyNames(in: directoryAbsolutePath, repoRoot: repoRoot, candidates: contents)
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot

        var entries: [FileTreeEntry] = []
        entries.reserveCapacity(classification.visible.count)

        for name in classification.visible {
            if name == "." || name == ".." { continue }
            let absolute = directoryAbsolutePath.hasSuffix("/")
                ? directoryAbsolutePath + name
                : directoryAbsolutePath + "/" + name

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: absolute, isDirectory: &isDir) else { continue }

            let relative: String = if absolute.hasPrefix(normalizedRoot + "/") {
                String(absolute.dropFirst(normalizedRoot.count + 1))
            } else {
                name
            }

            entries.append(FileTreeEntry(
                name: name,
                absolutePath: absolute,
                relativePath: relative,
                isDirectory: isDir.boolValue,
                isIgnored: classification.ignored.contains(name)
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return entries
    }

    private struct NameClassification {
        let visible: [String]
        let ignored: Set<String>
    }

    private static func classifyNames(
        in directoryAbsolutePath: String,
        repoRoot: String,
        candidates: [String]
    ) -> NameClassification {
        let isRepoChild = isInsideRepo(path: directoryAbsolutePath, repoRoot: repoRoot)
        guard isRepoChild else {
            return NameClassification(visible: candidates, ignored: [])
        }

        let ignored = ignoredNames(
            directoryAbsolutePath: directoryAbsolutePath,
            repoRoot: repoRoot,
            candidates: candidates
        )
        let visible = candidates.filter { $0 != ".git" }
        return NameClassification(visible: visible, ignored: ignored)
    }

    private static func isInsideRepo(path: String, repoRoot: String) -> Bool {
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot
        return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
    }

    private static func ignoredNames(
        directoryAbsolutePath: String,
        repoRoot: String,
        candidates: [String]
    ) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let ignoredSet = GitIgnoreCache.shared.ignoredPaths(repoRoot: repoRoot)
        guard !ignoredSet.isEmpty else { return [] }

        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot
        let prefix: String
        if directoryAbsolutePath == normalizedRoot {
            prefix = ""
        } else if directoryAbsolutePath.hasPrefix(normalizedRoot + "/") {
            prefix = String(directoryAbsolutePath.dropFirst(normalizedRoot.count + 1)) + "/"
        } else {
            return []
        }

        var result: Set<String> = []
        for name in candidates {
            let relative = prefix + name
            if ignoredSet.contains(relative) || ignoredSet.contains(relative + "/") {
                result.insert(name)
            }
        }
        return result
    }
}

final class GitIgnoreCache: @unchecked Sendable {
    static let shared = GitIgnoreCache()

    private struct CachedEntry {
        let ignored: Set<String>
        let signature: Signature
    }

    private struct Signature: Equatable {
        let gitignoreModification: Date?
        let gitignoreSize: Int64
    }

    private let lock = NSLock()
    private var cache: [String: CachedEntry] = [:]
    private var watcherTokens: [String: FileSystemWatcherToken] = [:]

    private init() {}

    func ignoredPaths(repoRoot: String) -> Set<String> {
        let normalizedRoot = Self.normalize(repoRoot)
        let signature = computeSignature(repoRoot: normalizedRoot)

        lock.lock()
        let cached = cache[normalizedRoot]
        lock.unlock()

        if let cached, cached.signature == signature {
            return cached.ignored
        }

        let computed = computeIgnoredPaths(repoRoot: normalizedRoot)

        lock.lock()
        cache[normalizedRoot] = CachedEntry(ignored: computed, signature: signature)
        installWatcherIfNeeded(repoRoot: normalizedRoot)
        lock.unlock()

        return computed
    }

    func invalidate(repoRoot: String) {
        let normalizedRoot = Self.normalize(repoRoot)
        lock.lock()
        cache.removeValue(forKey: normalizedRoot)
        lock.unlock()
    }

    private func installWatcherIfNeeded(repoRoot: String) {
        guard watcherTokens[repoRoot] == nil else { return }
        let token = SharedFileSystemWatcher.shared.subscribe(path: repoRoot) { [weak self] in
            self?.invalidate(repoRoot: repoRoot)
        }
        watcherTokens[repoRoot] = token
    }

    private func computeSignature(repoRoot: String) -> Signature {
        let path = repoRoot + "/.gitignore"
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modification = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return Signature(gitignoreModification: modification, gitignoreSize: size)
    }

    private func computeIgnoredPaths(repoRoot: String) -> Set<String> {
        guard let gitPath = GitProcessRunner.resolveExecutable("git") else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = [
            "-C", repoRoot,
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
            "--directory",
            "-z",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return []
        }

        let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        _ = try? stderrPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        return parseNullSeparated(outData)
    }

    private func parseNullSeparated(_ data: Data) -> Set<String> {
        var result: Set<String> = []
        var current = Data()
        for byte in data {
            if byte == 0 {
                if let entry = String(data: current, encoding: .utf8), !entry.isEmpty {
                    result.insert(entry)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty, let entry = String(data: current, encoding: .utf8) {
            result.insert(entry)
        }
        return result
    }

    private static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
