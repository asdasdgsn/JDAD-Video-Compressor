import Foundation
import Combine
@MainActor public final class QueueStore: ObservableObject {
    @Published public var items: [QueueItem] = []
    @Published public var presets: [SavedPreset] = []
    @Published public var running = false
    @Published public var notice = ""
    private let persistence: JSONStore
    private var runner: EngineRunner?
    private var worker: Task<Void,Never>?
    private var currentID: UUID?
    public init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FrameShift")
        persistence = JSONStore(directory: root)
        let history: [QueueItem] = persistence.load(file: "history.json", fallback: [])
        items = history.map { $0.recovered() }
        presets = persistence.load(file: "presets.json", fallback: [])
        notice = persistence.diagnostics.joined(separator: "\n")
    }
    public func enqueue(inputs: [MediaInfo], settings: ConversionSettings, directory: URL) throws {
        guard !inputs.isEmpty else { throw MediaError.message("请先添加文件 / Add files first") }
        guard FileManager.default.isWritableFile(atPath: directory.path) else { throw MediaError.message("输出目录不可写 / Output folder is not writable") }
        let groups = settings.merge ? [inputs] : inputs.map { [$0] }
        var pending: [QueueItem] = []
        for group in groups {
            let base = (group.count > 1 ? "Merged" : group[0].url.deletingPathExtension().lastPathComponent)+"-FrameShift"
            var out = OutputAllocator.unique(directory: directory, name: base, extension: settings.format.rawValue)
            var suffix = 2
            while (items+pending).contains(where: { $0.output == out && ($0.status == .waiting || $0.status == .running) }) {
                out = OutputAllocator.unique(directory: directory, name: base+"-\(suffix)", extension: settings.format.rawValue); suffix += 1
            }
            let plan = try CommandBuilder.build(inputs: group, settings: settings, output: out)
            if let dir = plan.temporaryDirectory { try? FileManager.default.removeItem(at: dir) }
            pending.append(QueueItem(inputs: group, settings: settings, output: out))
        }
        items += pending; persist()
    }
    public func start() {
        guard !running else { return }; running = true
        worker = Task { [weak self] in
            guard let self else { return }
            while let index = self.items.firstIndex(where: { $0.status == .waiting }) {
                let id = self.items[index].id
                self.currentID = id; self.items[index].status = .running; self.items[index].started = Date(); self.persist()
                let item = self.items[index]
                let engine = EngineRunner(); self.runner = engine
                let tempDir = item.output.deletingLastPathComponent().appendingPathComponent(".FrameShift-"+UUID().uuidString)
                let tempOutput = tempDir.appendingPathComponent("output."+item.settings.format.rawValue)
                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let space = try FileManager.default.attributesOfFileSystem(forPath: tempDir.path)
                    if let available = space[.systemFreeSize] as? NSNumber, available.int64Value < 128*1024*1024 { throw MediaError.message("磁盘剩余空间不足 128 MB / Insufficient disk space") }
                    let plan = try CommandBuilder.build(inputs: item.inputs, settings: item.settings, output: tempOutput)
                    try await engine.run(plan: plan) { [weak self] value in Task { @MainActor in self?.update(id: id) { $0.progress = value } } }
                    if self.items.first(where: { $0.id == id })?.status == .cancelled { throw CancellationError() }
                    // moveItem refuses to replace an existing destination.
                    try FileManager.default.moveItem(at: tempOutput, to: item.output)
                    self.update(id: id) { $0.status = .completed; $0.progress = 1; $0.finished = Date() }
                } catch is CancellationError {
                    self.update(id: id) { $0.status = .cancelled; $0.finished = Date() }
                } catch {
                    self.update(id: id) { $0.status = .failed; $0.error = error.localizedDescription; $0.finished = Date() }
                }
                try? FileManager.default.removeItem(at: tempDir)
                self.runner = nil; self.currentID = nil; self.persist()
                if Task.isCancelled { break }
            }
            self.running = false; self.worker = nil
        }
    }
    private func update(id: UUID, change: (inout QueueItem) -> Void) { if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) } }
    public func cancelCurrent() {
        guard let id = currentID else { return }
        update(id: id) { $0.status = .cancelled }; runner?.cancel(); persist()
    }
    public func cancelWaiting(id: UUID) { update(id: id) { if $0.status == .waiting { $0.status = .cancelled } }; persist() }
    public func retry(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), ![QueueStatus.running,.waiting].contains(items[i].status) else { return }
        let old = items[i]
        let directory = old.output.deletingLastPathComponent()
        let base = old.output.deletingPathExtension().lastPathComponent
        var out = OutputAllocator.unique(directory: directory, name: base, extension: old.settings.format.rawValue)
        var index = 2
        while items.contains(where: { $0.output == out && ($0.status == .waiting || $0.status == .running) }) {
            out = OutputAllocator.unique(directory: directory, name: base+"-\(index)", extension: old.settings.format.rawValue); index += 1
        }
        items.append(QueueItem(inputs: old.inputs, settings: old.settings, output: out)); persist(); start()
    }
    public func clearFinished() { items.removeAll { $0.status != .running && $0.status != .waiting }; persist() }
    public func savePreset(name: String, settings: ConversionSettings) { presets.append(SavedPreset(name: name, settings: settings)); persist() }
    public func deletePreset(id: UUID) { presets.removeAll { $0.id == id }; persist() }
    public func shutdown() { worker?.cancel(); cancelCurrent(); for i in items.indices where items[i].status == .waiting { items[i].status = .interrupted }; persist() }
    public func stopAndWait() async { let active = worker; shutdown(); await active?.value }
    private func persist() {
        do { try persistence.save(Array(items.suffix(500)), file: "history.json"); try persistence.save(presets, file: "presets.json") }
        catch { notice = error.localizedDescription }
    }
}
