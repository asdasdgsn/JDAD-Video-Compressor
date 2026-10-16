import Foundation
import Darwin
public struct MediaInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var duration: Double
    public var width: Int
    public var height: Int
    public var videoCodec: String?
    public var audioCodec: String?
    public var fps: Double
    public var rotation: Int
    public var sampleAspectRatio: Double?
    public var squareWidth: Int { max(2, Int((Double(width) * (sampleAspectRatio ?? 1)).rounded()) / 2 * 2) }
    public var sampleRate: Int
    public var channels: Int
    public var hasAudio: Bool { audioCodec != nil }
    public var hasVideo: Bool { videoCodec != nil }
    public var displayWidth: Int { abs(rotation) % 180 == 90 ? height : squareWidth }
    public var displayHeight: Int { abs(rotation) % 180 == 90 ? squareWidth : height }
    public init(url: URL, duration: Double, width: Int = 0, height: Int = 0, videoCodec: String? = nil, audioCodec: String? = nil, fps: Double = 0, rotation: Int = 0, sampleRate: Int = 0, channels: Int = 0, sampleAspectRatio: Double = 1) {
        self.url = url; self.duration = duration; self.width = width; self.height = height; self.videoCodec = videoCodec; self.audioCodec = audioCodec; self.fps = fps; self.rotation = rotation; self.sampleRate = sampleRate; self.channels = channels; self.sampleAspectRatio = sampleAspectRatio
    }
    public func compatible(with other: MediaInfo) -> Bool {
        videoCodec == other.videoCodec && audioCodec == other.audioCodec && width == other.width && height == other.height && abs(fps-other.fps) < 0.01 && sampleRate == other.sampleRate && channels == other.channels && rotation == other.rotation && abs((sampleAspectRatio ?? 1)-(other.sampleAspectRatio ?? 1)) < 0.0001
    }
}
public enum MediaError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public enum MediaProbe {
    public static func decode(_ data: Data, url: URL) throws -> MediaInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let streams = root["streams"] as? [[String: Any]] else { throw MediaError.message("无法读取媒体信息 / Invalid media metadata") }
        let video = streams.first { $0["codec_type"] as? String == "video" && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        guard video != nil || audio != nil else { throw MediaError.message("未找到视频或音轨 / No video or audio stream") }
        let format = root["format"] as? [String: Any] ?? [:]
        let duration = Double(format["duration"] as? String ?? video?["duration"] as? String ?? audio?["duration"] as? String ?? "0") ?? 0
        let parts = (video?["avg_frame_rate"] as? String ?? "0/1").split(separator: "/").compactMap { Double($0) }
        let fps = parts.count == 2 && parts[1] != 0 ? parts[0]/parts[1] : 0
        let side = video?["side_data_list"] as? [[String: Any]] ?? []
        let rotation = side.compactMap { $0["rotation"] as? Int }.first ?? Int((video?["tags"] as? [String: Any])?["rotate"] as? String ?? "0") ?? 0
        let sarParts = (video?["sample_aspect_ratio"] as? String ?? "1:1").split(separator: ":").compactMap { Double($0) }
        let sar = sarParts.count == 2 && sarParts[1] > 0 && sarParts[0] > 0 ? sarParts[0]/sarParts[1] : 1
        return MediaInfo(url: url, duration: duration.isFinite ? max(0,duration) : 0, width: video?["width"] as? Int ?? 0, height: video?["height"] as? Int ?? 0, videoCodec: video?["codec_name"] as? String, audioCodec: audio?["codec_name"] as? String, fps: fps, rotation: rotation, sampleRate: Int(audio?["sample_rate"] as? String ?? "0") ?? 0, channels: audio?["channels"] as? Int ?? 0, sampleAspectRatio: sar)
    }
    public static func inspect(url: URL) async throws -> MediaInfo {
        let data = try await ProcessCapture.run(executable: EnginePaths.tool("ffprobe"), arguments: ["-v","error","-show_streams","-show_format","-of","json",url.path])
        return try decode(data, url: url)
    }
}
public enum EnginePaths {
    public static func tool(_ name: String) throws -> URL {
        let env = ProcessInfo.processInfo.environment["FRAMESHIFT_ENGINE_DIR"]
        let candidates = [env.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }, Bundle.main.resourceURL?.appendingPathComponent("Engine/"+name), URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".engine/install/bin/"+name)].compactMap { $0 }
        guard let result = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw MediaError.message("处理引擎缺失，请重新安装应用 / Missing media engine: \(name)") }
        return result
    }
}
public enum ProcessCapture {
    private static let registry = CaptureRegistry()
    public static func run(executable: URL, arguments: [String]) async throws -> Data {
        try Task.checkCancellation()
        let session = CaptureSession()
        try registry.add(session)
        defer { registry.remove(session.id) }
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try session.run(executable: executable, arguments: arguments) }.value
        } onCancel: { session.cancel() }
    }
    /// Final application shutdown. New auxiliary work is refused after this call.
    public static func shutdown() async {
        registry.close()
        while registry.count > 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
    }
}
private final class CaptureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [UUID: CaptureSession] = [:]
    private var closing = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return sessions.count }
    func add(_ session: CaptureSession) throws { lock.lock(); defer { lock.unlock() }; if closing { throw CancellationError() }; sessions[session.id] = session }
    func remove(_ id: UUID) { lock.lock(); sessions[id] = nil; lock.unlock() }
    func close() { lock.lock(); closing = true; let active = Array(sessions.values); lock.unlock(); active.forEach { $0.cancel() } }
}
private final class CaptureSession: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now()+1) { [weak self, weak p] in
            guard let self, let p else { return }
            self.lock.lock(); let owned = self.process === p; self.lock.unlock()
            if owned && p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
    func run(executable: URL, arguments: [String]) throws -> Data {
        let p = Process(); p.executableURL = executable; p.arguments = arguments
        let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
        let errorData = LockedData()
        lock.lock(); process = p; let stopped = cancelled; lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        if stopped { throw CancellationError() }
        try p.run()
        let drain = DispatchGroup(); drain.enter()
        DispatchQueue.global(qos: .utility).async {
            while true { let chunk = err.fileHandleForReading.availableData; if chunk.isEmpty { break }; errorData.append(chunk) }
            drain.leave()
        }
        lock.lock(); let stopAfterLaunch = cancelled; lock.unlock()
        if stopAfterLaunch { cancel() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); drain.wait()
        lock.lock(); let didCancel = cancelled; lock.unlock()
        if didCancel { throw CancellationError() }
        let diagnostic = String(decoding: errorData.snapshot(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw MediaError.message(diagnostic.isEmpty ? "Media tool exited with code \(p.terminationStatus)" : String(diagnostic.suffix(2000))) }
        return data
    }
}
public struct EngineCapabilities: Sendable {
    public let encoders: Set<String>
    public func supports(_ name: String) -> Bool { encoders.contains(name) }
    public static func load() async throws -> EngineCapabilities {
        let d = try await ProcessCapture.run(executable: EnginePaths.tool("ffmpeg"), arguments: ["-hide_banner","-encoders"])
        let names = String(decoding: d, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            let cols: [Substring] = line.split(whereSeparator: { $0.isWhitespace }); guard cols.count > 1, cols[0].count == 6 else { return nil }; return String(cols[1])
        }
        return EngineCapabilities(encoders: Set(names))
    }
}
