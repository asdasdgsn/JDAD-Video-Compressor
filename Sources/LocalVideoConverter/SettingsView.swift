import SwiftUI
import ConverterCore
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var presetManager = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack { Text(model.t("处理设置","PROCESSING")).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button { model.settings = .init() } label:{ Image(systemName:"arrow.counterclockwise") }.buttonStyle(.plain).help(model.t("重置","Reset")) }
                presetPicker
                section(model.t("输出格式","OUTPUT FORMAT")) {
                    Picker(model.t("容器","Format"),selection:$model.settings.format) { ForEach(OutputFormat.allCases) { f in Text(f.title).tag(f) } }
                    if !model.settings.format.audioOnly && model.settings.format != .webm {
                        Picker(model.t("编码","Codec"),selection:$model.settings.codec) { ForEach(VideoCodec.allCases.filter { model.capabilities?.supports($0.encoder) ?? true }) { c in Text(c.title).tag(c) } }
                    }
                    if model.settings.format == .webm { Text("VP9 · CPU / Vorbis").font(.caption).foregroundStyle(.secondary) }
                    if let name = model.settings.requiredEncoder, let c = model.capabilities, !c.supports(name) { Label(model.t("此编码器不可用","Encoder unavailable"),systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if !model.settings.format.audioOnly {
                        Toggle(model.t("无损复制 / 剪切","Lossless copy / cut"),isOn:$model.settings.lossless)
                        if model.settings.lossless { Text(model.t("不重新编码，切点受关键帧限制；滤镜不可同时使用。合并要求流参数一致。","No re-encoding. Cuts follow keyframes; filters are unavailable. Merging requires matching streams.")).font(.caption2).foregroundStyle(.orange) }
                    }
                }
                if !model.settings.lossless && !model.settings.format.audioOnly {
                    section(model.t("画质与尺寸","QUALITY & SIZE")) {
                        HStack { Text(model.t("画质","Quality")); Spacer(); Text("\(model.settings.quality)%").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
                        Slider(value:Binding(get:{Double(model.settings.quality)},set:{model.settings.quality=Int($0)}),in:1...100,step:1)
                        Text(model.t("Apple 编码根据画质估算码率；可指定码率覆盖。","Apple encoding uses quality-based bitrate; set a bitrate to override.")).font(.caption2).foregroundStyle(.secondary)
                        HStack { Text(model.t("视频码率","Video bitrate")); Spacer(); TextField("0",value:$model.settings.bitrate,format:.number).frame(width:75).multilineTextAlignment(.trailing); Text("kb/s").foregroundStyle(.secondary) }.font(.caption)
                        Text(model.t("0 = 自动","0 = automatic")).font(.caption2).foregroundStyle(.secondary)
                        Picker(model.t("输出宽度","Width"),selection:$model.settings.width) { Text(model.t("原始尺寸","Original")).tag(0); ForEach([3840,2560,1920,1280,854,640,320],id:\.self) { Text("\($0) px").tag($0) } }
                        Picker(model.t("帧率","Frame rate"),selection:$model.settings.frameRate) { Text(model.t("原始帧率","Original")).tag(0); ForEach([24,25,30,50,60],id:\.self) { Text("\($0) fps").tag($0) } }
                    }
                    section(model.t("画面处理","TRANSFORM")) {
                        Picker(model.t("旋转","Rotate"),selection:$model.settings.rotation) { Text(model.t("不旋转","None")).tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270) }
                        HStack { Toggle(model.t("水平翻转","Flip H"),isOn:$model.settings.flipH); Toggle(model.t("垂直翻转","Flip V"),isOn:$model.settings.flipV) }.toggleStyle(.checkbox)
                    }
                }
                if !model.settings.lossless {
                    section(model.t("速度与音频","SPEED & AUDIO")) {
                        Picker(model.t("播放速度","Speed"),selection:$model.settings.speed) { ForEach([0.5,0.75,1,1.25,1.5,2],id:\.self) { Text(String(format:"%.2g×",$0)).tag($0) } }
                        if !model.settings.format.audioOnly { Toggle(model.t("静音","Mute audio"),isOn:$model.settings.mute) }
                        Picker(model.t("音频码率","Audio bitrate"),selection:$model.settings.audioBitrate) { ForEach([64,96,128,192,256,320],id:\.self) { Text("\($0) kb/s").tag($0) } }
                    }
                }
                section(model.t("时间剪切","TRIM")) {
                    HStack {
                        VStack(alignment:.leading,spacing:5) { Text(model.t("开始（秒）","Start (seconds)")).font(.caption2).foregroundStyle(.secondary); TextField("0",value:$model.settings.start,format:.number) }
                        Text("→").foregroundStyle(.tertiary)
                        VStack(alignment:.leading,spacing:5) { Text(model.t("结束（秒）","End (seconds)")).font(.caption2).foregroundStyle(.secondary); TextField("0",value:$model.settings.end,format:.number) }
                    }.disabled(model.settings.merge)
                    Text(model.t(model.settings.merge ? "合并前请先对各片段剪切。" : "结束为 0 表示直到片尾。", model.settings.merge ? "Trim individual clips before merging." : "End at 0 means until the end.")).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.background(Color(nsColor:.controlBackgroundColor).opacity(0.25))
        .onChange(of:model.settings.lossless) { _,value in if value { model.settings.width=0;model.settings.frameRate=0;model.settings.speed=1;model.settings.rotation=0;model.settings.flipH=false;model.settings.flipV=false } }
        .onChange(of:model.settings.format) { _,value in if value.audioOnly { model.settings.lossless=false;model.settings.mute=false } }
    }
    var presetPicker: some View {
        VStack(alignment:.leading,spacing:8) {
            Menu {
                Button(model.t("默认 H.264","Default H.264")) { model.settings = .init() }
                Button(model.t("轻量 MP4 · 720p","Compact MP4 · 720p")) { var s=ConversionSettings();s.width=1280;s.bitrate=2500;model.settings=s }
                Button(model.t("仅导出音频 · M4A","Extract audio · M4A")) { var s=ConversionSettings();s.format = .m4a;model.settings=s }
                ForEach(model.queue.presets) { p in Button(p.name) { model.settings=p.settings } }
            } label: { Label(model.t("选择预设","Choose preset"),systemImage:"slider.horizontal.3") }
            if !model.queue.presets.isEmpty {
                DisclosureGroup(model.t("管理自定义预设","Manage saved presets")) {
                    ForEach(model.queue.presets) { p in HStack { Text(p.name).lineLimit(1);Spacer();Button { model.queue.deletePreset(id:p.id) } label:{ Image(systemName:"trash") }.buttonStyle(.plain) }.font(.caption).padding(.vertical,3) }
                }.font(.caption)
            }
        }
    }
    func section<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:11) { Text(title).font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary); content() }.font(.system(size:12))
    }
}
