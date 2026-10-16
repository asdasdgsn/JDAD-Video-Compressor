import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConverterCore
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var dragOver = false
    @State private var presetName = ""
    @State private var savingPreset = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sourcePanel.frame(minWidth: 240, idealWidth: 270, maxWidth: 340)
                VStack(spacing: 0) {
                    PreviewView(media: model.active, model: model).frame(minHeight: 240, idealHeight: 320)
                    Divider()
                    QueueView(queue: model.queue, model: model).frame(minHeight: 230)
                }.frame(minWidth: 430)
                SettingsView(model: model).frame(minWidth: 300, idealWidth: 320, maxWidth: 370)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Picker("Language", selection: $model.language) { Text("中文").tag("zh"); Text("EN").tag("en") }.frame(width: 90)
                Button { savingPreset = true } label: { Label(model.t("保存预设","Save preset"), systemImage: "slider.horizontal.3") }
            }
        }
        .alert(model.t("提示","Notice"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert(model.t("保存处理预设","Save preset"), isPresented: $savingPreset) {
            TextField(model.t("预设名称","Preset name"), text: $presetName)
            Button(model.t("保存","Save")) { if !presetName.trimmingCharacters(in: .whitespaces).isEmpty { model.queue.savePreset(name: presetName, settings: model.settings); presetName = "" } }
            Button(model.t("取消","Cancel"), role: .cancel) {}
        }
    }
    var header: some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.13)); Image(systemName: "play.rectangle.on.rectangle.fill").font(.system(size: 24)).foregroundStyle(Color.accentColor) }.frame(width: 48,height: 48)
            VStack(alignment: .leading, spacing: 3) { Text("FrameShift").font(.system(size: 21, weight: .semibold, design: .rounded)); Text(model.t("映转 · 本地视频工作台","Your local media workbench")).foregroundStyle(.secondary).font(.caption) }
            Spacer()
            HStack(spacing: 6) { Circle().fill(model.engineReady ? Color.green : Color.orange).frame(width: 6,height: 6); Text(model.t(model.engineReady ? "本地引擎就绪" : "正在检查引擎",model.engineReady ? "Engine ready" : "Checking engine")).font(.caption).foregroundStyle(.secondary) }
            Button { model.chooseFiles() } label: { Label(model.t("添加文件","Add files"),systemImage: "plus") }.controlSize(.large).disabled(model.importing)
            Button { model.enqueue() } label: { Label(model.t("开始处理","Start processing"),systemImage: "play.fill").padding(.horizontal,8) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.files.isEmpty || !model.engineReady || model.importing)
        }.padding(.horizontal,22).padding(.vertical,16)
    }
    var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(model.t("源文件","SOURCES")).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Text("\(model.files.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }.padding(16)
            if model.files.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 34,weight: .light)).foregroundStyle(Color.accentColor)
                    Text(model.t("将视频拖到这里","Drop media here")).font(.headline)
                    Text(model.t("视频与音频均可添加\n所有处理都在本机完成","Add video or audio\nProcessed entirely on your Mac")).multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
                    Button(model.t("选择文件…","Browse files…")) { model.chooseFiles() }
                }.frame(maxWidth: .infinity,maxHeight: .infinity).padding(20)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.files) { file in
                        HStack(alignment: .top,spacing: 9) {
                            Image(systemName: file.hasVideo ? "film" : "waveform").foregroundStyle(Color.accentColor).frame(width: 24).padding(.top,3)
                            VStack(alignment: .leading,spacing: 4) {
                                Text(file.url.lastPathComponent).font(.system(size:12,weight:.medium)).lineLimit(2)
                                Text(file.hasVideo ? "\(file.displayWidth) × \(file.displayHeight) · \(durationText(file.duration))" : durationText(file.duration)).font(.caption2).foregroundStyle(.secondary)
                                Text([file.videoCodec,file.audioCodec].compactMap{$0}.joined(separator:" / ").uppercased()).font(.system(size:9,design:.monospaced)).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical,6).tag(file.id)
                        .contextMenu {
                            Button(model.t("上移","Move up")) { model.move(id:file.id,direction:-1) }
                            Button(model.t("下移","Move down")) { model.move(id:file.id,direction:1) }
                            Button(model.t("在 Finder 中显示","Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                            Divider(); Button(model.t("移除","Remove"),role:.destructive) { model.remove(id:file.id) }
                        }
                    }
                }.listStyle(.sidebar)
            }
            if model.importing { ProgressView(model.t("正在读取媒体…","Reading media…")).controlSize(.small).padding() }
            Divider()
            HStack { Toggle(model.t("按列表顺序合并","Merge in list order"),isOn:$model.settings.merge).toggleStyle(.checkbox); Spacer() }.padding(14)
            Text(model.t("右键文件可调整合并顺序","Right-click a file to reorder")).font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14).padding(.bottom,12)
        }
        .background(dragOver ? Color.accentColor.opacity(0.08) : Color(nsColor:.controlBackgroundColor).opacity(0.4))
        .onDrop(of:[UTType.fileURL],isTargeted:$dragOver) { providers in
            for p in providers { _ = p.loadObject(ofClass: URL.self) { url,_ in if let url { Task { @MainActor in model.importFiles([url]) } } } }; return true
        }
    }
    var footer: some View {
        HStack(spacing:10) {
            Image(systemName:"folder").foregroundStyle(.secondary)
            Text(model.t("输出至","OUTPUT")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(model.outputDirectory.path).font(.caption).lineLimit(1).truncationMode(.middle)
            Button(model.t("更改…","Change…")) { model.chooseOutput() }.controlSize(.small)
            Spacer()
            Text(model.t("原文件始终保留 · 不覆盖同名文件","Originals preserved · No overwriting")).font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal,20).padding(.vertical,12)
    }
}
func durationText(_ seconds:Double) -> String { guard seconds.isFinite && seconds > 0 else { return "—" }; let value = Int(seconds); return String(format:"%02d:%02d",value/60,value%60) }
