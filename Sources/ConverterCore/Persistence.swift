import Foundation
public final class JSONStore: @unchecked Sendable {
    public let directory: URL
    public private(set) var diagnostics: [String] = []
    public init(directory: URL) { self.directory = directory }
    public func save<T: Encodable>(_ value: T, file: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(value).write(to: directory.appendingPathComponent(file), options: .atomic)
    }
    public func load<T: Decodable>(file: String, fallback: T) -> T {
        let url = directory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch { diagnostics.append("\(file): \(error.localizedDescription)"); return fallback }
    }
}
public enum OutputAllocator {
    public static func unique(directory: URL, name: String, extension ext: String) -> URL {
        var index = 1
        while true {
            let suffix = index == 1 ? "" : "-\(index)"
            let candidate = directory.appendingPathComponent(name+suffix).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
public enum QueueStatus: String, Codable, Sendable { case waiting, running, completed, failed, cancelled, interrupted }
public struct QueueItem: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var inputs: [MediaInfo]
    public var settings: ConversionSettings
    public var output: URL
    public var status: QueueStatus = .waiting
    public var progress: Double = 0
    public var error: String = ""
    public var created = Date()
    public var started: Date?
    public var finished: Date?
    public var title: String { inputs.count > 1 ? "\(inputs.count) clips → \(output.lastPathComponent)" : inputs.first?.url.lastPathComponent ?? output.lastPathComponent }
    public init(inputs: [MediaInfo], settings: ConversionSettings, output: URL) { self.inputs = inputs; self.settings = settings; self.output = output }
    public func recovered() -> QueueItem {
        var copy = self
        if status == .running || status == .waiting { copy.status = .interrupted; copy.error = "上次会话已结束，可重试 / Previous session ended; retry available" }
        return copy
    }
}
public enum ProgressParser {
    public static func fraction(line: String, duration: Double) -> Double? {
        guard duration > 0, line.hasPrefix("out_time_us="), let value = Double(line.dropFirst(12)), value.isFinite else { return nil }
        return max(0,min(0.99,value / 1_000_000 / duration))
    }
}
