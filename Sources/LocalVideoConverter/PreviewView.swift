import SwiftUI
import AVKit
import ConverterCore
struct PreviewView: View {
    let media: MediaInfo?
    @ObservedObject var model: AppModel
    @State private var player: AVPlayer?
    @State private var thumbnail: NSImage?
    @State private var unsupported = false
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(model.t("预览","PREVIEW")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let media { Text(media.url.pathExtension.uppercased()).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.secondary) }
                Button { model.snapshot() } label:{ Image(systemName:"camera") }.buttonStyle(.plain).disabled(media?.hasVideo != true).help(model.t("保存开始时间处的截图","Save frame at trim start"))
            }.padding(.horizontal,18).padding(.vertical,12)
            ZStack {
                Color(red:0.07,green:0.085,blue:0.105)
                if let player { NativePlayerView(player:player) }
                else if let thumbnail { Image(nsImage:thumbnail).resizable().scaledToFit().padding(8) }
                else {
                    VStack(spacing:12) { Image(systemName:media == nil ? "play.rectangle" : "waveform").font(.system(size:44,weight:.ultraLight)); Text(model.t(media == nil ? "选择文件以预览" : "正在准备预览",media == nil ? "Select a file to preview" : "Preparing preview")).font(.caption) }.foregroundStyle(.white.opacity(0.45))
                }
                if unsupported {
                    VStack { Spacer(); Text(model.t("系统暂不支持播放此格式，仍可转换或保存截图。","Playback unavailable for this format. Conversion and snapshots remain available.")).font(.caption2).padding(8).background(.black.opacity(0.7)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius:6)).padding(10) }
                }
            }.clipShape(RoundedRectangle(cornerRadius:8)).padding(.horizontal,16)
            HStack {
                if let m=media { Text(m.url.lastPathComponent).lineLimit(1); Spacer(); Text(durationText(m.duration)).monospacedDigit(); if m.hasVideo { Text("\(m.displayWidth)×\(m.displayHeight)") } }
                else { Text(model.t("支持本地视频和音频","Local video and audio"));Spacer();Image(systemName:"lock.shield") }
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,18).padding(.vertical,10)
        }
        .task(id:media?.id) {
            player?.pause(); player=nil;thumbnail=nil;unsupported=false
            guard let media else { return }
            let asset = AVURLAsset(url:media.url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            guard !Task.isCancelled else { return }
            if playable { player=AVPlayer(playerItem:AVPlayerItem(asset:asset)) }
            else {
                unsupported=true
                if media.hasVideo {
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
                    defer { try? FileManager.default.removeItem(at:temp) }
                    _ = try? await ProcessCapture.run(executable:EnginePaths.tool("ffmpeg"),arguments:["-v","error","-nostdin","-i",media.url.path,"-vf","scale=800:-2","-frames:v","1",temp.path])
                    if !Task.isCancelled { thumbnail=NSImage(contentsOf:temp) }
                }
            }
        }.onDisappear { player?.pause() }
    }
}

// Use AVPlayerView directly to avoid _AVKit_SwiftUI generic metadata issues
// when a new SDK deployment-target build runs on macOS 15.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .floating; view.showsFrameSteppingButtons = true; view.player = player; return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}
