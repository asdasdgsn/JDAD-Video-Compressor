import Foundation
import Darwin
public final class EngineRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now()+2) { [weak self, weak p] in
                guard let self, let p else { return }
                self.lock.lock(); let owned = self.process === p; self.lock.unlock()
                if owned && p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
    }
    public func run(plan: CommandPlan, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await Task.detached(priority: .userInitiated) { [self] in try runBlocking(plan: plan, progress: progress) }.value
    }
    private func runBlocking(plan: CommandPlan, progress: @escaping @Sendable (Double) -> Void) throws {
            let p = Process(); p.executableURL = try EnginePaths.tool("ffmpeg"); p.arguments = plan.arguments
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            let stderr = LockedData()
            let drain = DispatchGroup()
            lock.lock(); process = p; let wasCancelled = cancelled; lock.unlock()
            defer {
                lock.lock(); process = nil; lock.unlock()
                if let dir = plan.temporaryDirectory { try? FileManager.default.removeItem(at: dir) }
            }
            if wasCancelled { throw CancellationError() }
            try p.run()
            drain.enter()
            DispatchQueue.global(qos: .utility).async {
                while true { let chunk = err.fileHandleForReading.availableData; if chunk.isEmpty { break }; stderr.append(chunk) }
                drain.leave()
            }
            lock.lock(); let stop = cancelled; lock.unlock()
            if stop && p.isRunning { p.terminate() }
            var buffer = Data()
            while true {
                let data = out.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let index = buffer.firstIndex(of: 10) {
                    let line = String(decoding: buffer[..<index], as: UTF8.self)
                    buffer.removeSubrange(...index)
                    if let value = ProgressParser.fraction(line: line, duration: plan.duration) { progress(value) }
                }
            }
            p.waitUntilExit(); drain.wait()
            lock.lock(); let didCancel = cancelled; lock.unlock()
            if didCancel { throw CancellationError() }
            let diagnostic = String(decoding: stderr.snapshot(), as: UTF8.self)
            guard p.terminationStatus == 0 else { throw MediaError.message(diagnostic.isEmpty ? "FFmpeg exit code \(p.terminationStatus)" : String(diagnostic.suffix(4000))) }
            progress(1)
    }
}
final class LockedData: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data()
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; data.append(chunk); if data.count > 65536 { data = data.suffix(65536) } }
    func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
