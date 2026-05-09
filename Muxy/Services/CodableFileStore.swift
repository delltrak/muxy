import Foundation
import os

private let codableFileStoreLogger = Logger(subsystem: "app.muxy", category: "CodableFileStore")

struct CodableFileStoreOptions {
    var prettyPrinted: Bool = false
    var sortedKeys: Bool = false
    var filePermissions: Int?

    static let standard = Self()
    static let pretty = Self(prettyPrinted: true)
    static let prettySorted = Self(prettyPrinted: true, sortedKeys: true)
}

struct CodableFileStore<Value: Codable> {
    let fileURL: URL
    let options: CodableFileStoreOptions

    init(fileURL: URL, options: CodableFileStoreOptions = .standard) {
        self.fileURL = fileURL
        self.options = options
    }

    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let data = try encode(value)
        try CodableFileStorePersistence.write(data: data, to: fileURL, permissions: options.filePermissions)
    }

    func saveAsync(_ value: Value) {
        let url = fileURL
        let perms = options.filePermissions
        do {
            let data = try encode(value)
            CodableFileStorePersistence.queue.async {
                do {
                    try CodableFileStorePersistence.write(data: data, to: url, permissions: perms)
                } catch {
                    codableFileStoreLogger
                        .error("Failed async write to \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            codableFileStoreLogger
                .error("Failed async encode for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func encode(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if options.prettyPrinted { formatting.insert(.prettyPrinted) }
        if options.sortedKeys { formatting.insert(.sortedKeys) }
        encoder.outputFormatting = formatting
        return try encoder.encode(value)
    }
}

enum CodableFileStorePersistence {
    static let queue = DispatchQueue(label: "app.muxy.codable-file-store", qos: .utility)

    static func flush() {
        queue.sync(flags: .barrier) {}
    }

    static func write(data: Data, to fileURL: URL, permissions: Int?) throws {
        try data.write(to: fileURL, options: .atomic)
        guard let permissions else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: fileURL.path
        )
    }
}
