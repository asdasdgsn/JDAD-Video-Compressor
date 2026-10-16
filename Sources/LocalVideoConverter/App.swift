import SwiftUI
import AppKit
import ConverterCore
import Combine
@main struct FrameShiftApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("JDAD视频压缩工具") {
            MainView(model: model)
                .frame(minWidth: 1120, minHeight: 750)
                .onAppear { delegate.model = model }
        }.windowStyle(.titleBar).defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { Button(model.t("添加文件…","Add files…")) { model.chooseFiles() }.keyboardShortcut("o") }
            CommandGroup(after: .appInfo) { Button(model.t("第三方许可","Third-party licenses")) { model.showLicenses() } }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.queue.running == true {
            let alert = NSAlert(); alert.messageText = model?.t("转换仍在进行","Conversion in progress") ?? "Conversion in progress"
            alert.informativeText = model?.t("退出会取消当前任务并清理未完成文件。","Quitting cancels the current task and removes incomplete output.") ?? ""
            alert.addButton(withTitle: model?.t("退出","Quit") ?? "Quit"); alert.addButton(withTitle: model?.t("继续转换","Keep converting") ?? "Keep converting")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        if let model {
            Task { @MainActor in await model.queue.stopAndWait(); await ProcessCapture.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@MainActor final class AppModel: ObservableObject {
    @Published var files: [MediaInfo] = []
    @Published var selection: String?
    @Published var settings = ConversionSettings()
    @Published var outputDirectory: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    @Published var importing = false
    @Published var error: String?
    @Published var capabilities: EngineCapabilities?
    @Published var engineReady = false
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published var selectedPreset: UUID?
    let queue = QueueStore()
    private var queueSubscription: AnyCancellable?
    private var pendingImports: [URL] = []
    var active: MediaInfo? { files.first { $0.id == selection } }
    init() {
        language = UserDefaults.standard.string(forKey: "language") ?? "zh"
        if let path = UserDefaults.standard.string(forKey: "outputDirectory"), FileManager.default.fileExists(atPath: path) { outputDirectory = URL(fileURLWithPath: path) }
        queueSubscription = queue.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        Task {
            do { capabilities = try await EngineCapabilities.load(); engineReady = true }
            catch { self.error = error.localizedDescription }
        }
    }
    func t(_ zh: String, _ en: String) -> String { language == "zh" ? zh : en }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = t("选择视频或音频文件","Choose video or audio files")
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }
    func importFiles(_ urls: [URL]) {
        pendingImports.append(contentsOf: urls)
        guard !importing else { return }; importing = true
        Task {
            var failures: [String] = []
            while !pendingImports.isEmpty {
                let url = pendingImports.removeFirst()
                if files.contains(where: { $0.url == url }) { continue }
                do { let media = try await MediaProbe.inspect(url: url); files.append(media); if selection == nil { selection = media.id } }
                catch { failures.append(url.lastPathComponent+": "+error.localizedDescription) }
            }
            importing = false
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    func chooseOutput() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.directoryURL = outputDirectory
        if p.runModal() == .OK, let url = p.url { outputDirectory = url; UserDefaults.standard.set(url.path, forKey: "outputDirectory") }
    }
    func remove(id: String) { files.removeAll { $0.id == id }; if selection == id { selection = files.first?.id } }
    func move(id: String, direction: Int) {
        guard let i = files.firstIndex(where: { $0.id == id }), files.indices.contains(i+direction) else { return }
        files.swapAt(i, i+direction)
    }
    func enqueue() {
        do {
            if let name = settings.requiredEncoder, capabilities?.supports(name) != true { throw MediaError.message(t("当前引擎不支持编码器：","Encoder unavailable: ")+name) }
            try queue.enqueue(inputs: files, settings: settings, directory: outputDirectory); queue.start()
        } catch { self.error = error.localizedDescription }
    }
    func snapshot() {
        guard let media = active, media.hasVideo else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = media.url.deletingPathExtension().lastPathComponent+"-snapshot.png"; panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
            defer { try? FileManager.default.removeItem(at: temp) }
            do {
                _ = try await ProcessCapture.run(executable: EnginePaths.tool("ffmpeg"), arguments: ["-hide_banner","-v","error","-nostdin","-ss",String(settings.start),"-i",media.url.path,"-map","0:V:0","-frames:v","1",temp.path])
                let data = try Data(contentsOf: temp); try data.write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { self.error = error.localizedDescription }
        }
    }
    func showLicenses() {
        if let path = Bundle.main.resourceURL?.appendingPathComponent("LICENSES"), FileManager.default.fileExists(atPath: path.path) { NSWorkspace.shared.open(path) }
    }
}
