import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "MuxyConfig")

@MainActor @Observable
final class MuxyConfig {
    static let shared = MuxyConfig()

    let ghosttyConfigURL: URL

    private static let ghosttyConfigFilename = "ghostty.conf"
    private static let systemGhosttyConfigPath = NSHomeDirectory() + "/.config/ghostty/config"

    private init() {
        let dir = MuxyFileStorage.appSupportDirectory()
        ghosttyConfigURL = dir.appendingPathComponent(Self.ghosttyConfigFilename)
        seedFromSystemGhosttyIfNeeded()
    }

    var ghosttyConfigPath: String {
        ghosttyConfigURL.path
    }

    func readGhosttyConfig() -> String {
        (try? String(contentsOf: ghosttyConfigURL, encoding: .utf8)) ?? ""
    }

    func writeGhosttyConfig(_ content: String) throws {
        let data = Data(content.utf8)
        try data.write(to: ghosttyConfigURL, options: .atomic)
        Self.restrictFilePermissions(ghosttyConfigURL)
    }

    func updateConfigValue(_ key: String, value: String) {
        let entry = "\(key) = \(value)"
        var lines = readGhosttyConfig().components(separatedBy: "\n")
        lines.removeAll { isConfigLine($0, matchingKey: key) }
        if lines.last?.isEmpty == false { lines.append("") }
        lines.append(entry)
        do {
            try writeGhosttyConfig(lines.joined(separator: "\n"))
        } catch {
            logger.error("Failed to write config: \(error)")
        }
    }

    func applyThemeValue(_ value: String) {
        let entry = "theme = \(value)"
        var lines = readGhosttyConfig().components(separatedBy: "\n")
        let colorKeys: Set = [
            "theme",
            "background",
            "foreground",
            "cursor-color",
            "cursor-text",
            "selection-background",
            "selection-foreground",
            "palette",
        ]
        lines.removeAll { line in
            colorKeys.contains { isConfigLine(line, matchingKey: $0) }
        }
        if lines.last?.isEmpty == false { lines.append("") }
        lines.append(entry)
        do {
            try writeGhosttyConfig(lines.joined(separator: "\n"))
        } catch {
            logger.error("Failed to write config: \(error)")
        }
    }

    private func isConfigLine(_ line: String, matchingKey key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key) else { return false }
        let after = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return after.hasPrefix("=")
    }

    func configValue(for key: String) -> String? {
        let lines = readGhosttyConfig().components(separatedBy: .newlines)
        guard let index = findConfigLineIndex(for: key, in: lines) else { return nil }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let afterKey = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return afterKey.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private func findConfigLineIndex(for key: String, in lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let afterKey = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard afterKey.hasPrefix("=") else { continue }
            return i
        }
        return nil
    }

    private func seedFromSystemGhosttyIfNeeded() {
        guard !FileManager.default.fileExists(atPath: ghosttyConfigURL.path) else { return }

        guard FileManager.default.fileExists(atPath: Self.systemGhosttyConfigPath),
              let systemContent = try? String(contentsOfFile: Self.systemGhosttyConfigPath, encoding: .utf8)
        else {
            try? writeGhosttyConfig("")
            return
        }

        try? writeGhosttyConfig(systemContent)
    }

    private static func restrictFilePermissions(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: FilePermissions.privateFile],
            ofItemAtPath: url.path
        )
    }
}
