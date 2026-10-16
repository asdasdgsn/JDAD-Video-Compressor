import Foundation
public struct CommandPlan: Sendable {
    public var arguments: [String]
    public var duration: Double
    public var temporaryDirectory: URL?
    public init(arguments: [String], duration: Double, temporaryDirectory: URL? = nil) { self.arguments = arguments; self.duration = duration; self.temporaryDirectory = temporaryDirectory }
}
public enum CommandBuilder {
    static func number(_ value: Double) -> String { String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value) }
    public static func build(inputs: [MediaInfo], settings s: ConversionSettings, output: URL) throws -> CommandPlan {
        guard !inputs.isEmpty else { throw MediaError.message("请先添加媒体文件 / Add media first") }
        guard !inputs.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == output.standardizedFileURL.resolvingSymlinksInPath() }) else { throw MediaError.message("输出不能覆盖输入文件 / Output cannot replace input") }
        guard s.start.isFinite, s.end.isFinite, s.speed.isFinite, s.start >= 0, s.end >= 0, (0.5...2).contains(s.speed), s.width >= 0, s.width % 2 == 0, s.bitrate >= 0, (32...512).contains(s.audioBitrate), (1...100).contains(s.quality), (0...120).contains(s.frameRate), [0,90,180,270].contains(s.rotation) else { throw MediaError.message("参数无效 / Invalid settings") }
        if s.lossless && (s.transformed || s.format.audioOnly) { throw MediaError.message("无损模式不支持滤镜或音频导出 / Lossless mode cannot apply filters or extract audio") }
        if s.format.audioOnly && s.mute { throw MediaError.message("音频输出不能静音 / Audio output cannot be muted") }
        if s.merge && !s.lossless && inputs.count > 1 && inputs.contains(where: { $0.duration <= 0 }) { throw MediaError.message("无法确定片段时长，请先单独转换 / Unknown clip duration; convert clips first") }
        if s.format.audioOnly && !inputs.allSatisfy(\.hasAudio) { throw MediaError.message("文件没有音轨 / No audio stream") }
        if !s.format.audioOnly && !inputs.allSatisfy(\.hasVideo) { throw MediaError.message("视频输出需要视频输入 / Video output requires video input") }
        if inputs.count > 1 && !s.merge { throw MediaError.message("多输入必须启用合并 / Enable merge for multiple inputs") }
        let total = inputs.reduce(0) { $0 + $1.duration }
        if total > 0 && (s.start >= total || s.end > total + 0.05) { throw MediaError.message("剪切时间超过媒体时长 / Trim exceeds duration") }
        if s.end > 0 && s.end <= s.start { throw MediaError.message("结束时间必须晚于开始 / End must follow start") }
        if s.merge && (s.start != 0 || s.end != 0) { throw MediaError.message("合并时请先关闭剪切 / Trim clips before merging") }
        if s.lossless && inputs.dropFirst().contains(where: { !inputs[0].compatible(with: $0) }) { throw MediaError.message("媒体参数不兼容，请关闭无损模式进行统一编码合并 / Incompatible streams; use re-encode merge") }
        var args = ["-hide_banner","-nostdin","-n","-progress","pipe:1","-nostats"]
        var temp: URL?
        if s.merge && s.lossless && inputs.count > 1 {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FrameShift-"+UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let list = dir.appendingPathComponent("inputs.ffconcat")
            let body = "ffconcat version 1.0\n" + inputs.map { "file '" + $0.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'\n" }.joined()
            guard !inputs.contains(where: { $0.url.path.contains("\n") || $0.url.path.contains("\r") }) else { try? FileManager.default.removeItem(at: dir); throw MediaError.message("无损合并不支持文件名中的换行 / Rename files containing newlines") }
            try body.write(to: list, atomically: true, encoding: .utf8); temp = dir
            args += ["-f","concat","-safe","0","-i",list.path]
        } else {
            for input in inputs { if s.start > 0 { args += ["-ss",number(s.start)] }; args += ["-i",input.url.path] }
        }
        let hasAudio = inputs[0].hasAudio && !s.mute
        if s.merge && !s.lossless && inputs.count > 1 {
            let w = s.width > 0 ? s.width : max(2, inputs[0].displayWidth / 2 * 2)
            let h = max(2, Int(Double(w) * Double(max(2,inputs[0].displayHeight)) / Double(max(2,inputs[0].displayWidth))) / 2 * 2)
            var filters: [String] = []; var pins = ""
            for (i,m) in inputs.enumerated() {
                if !s.format.audioOnly {
                    filters.append("[\(i):v:0]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=\(s.frameRate > 0 ? s.frameRate : 30),setpts=PTS-STARTPTS[v\(i)]")
                    pins += "[v\(i)]"
                }
                if !s.mute {
                    if m.hasAudio { filters.append("[\(i):a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim=duration=\(number(m.duration)),asetpts=PTS-STARTPTS[a\(i)]") }
                    else { filters.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(number(m.duration)),asetpts=PTS-STARTPTS[a\(i)]") }
                    pins += "[a\(i)]"
                }
            }
            let videoOut = !s.format.audioOnly; let audioOut = !s.mute
            filters.append(pins+"concat=n=\(inputs.count):v=\(videoOut ? 1 : 0):a=\(audioOut ? 1 : 0)"+(videoOut ? "[joinedv]" : "")+(audioOut ? "[joineda]" : ""))
            if videoOut { filters.append("[joinedv]"+videoFilters(s).joined(separator: ",")+"[vout]") }
            if audioOut { filters.append("[joineda]atempo=\(number(s.speed))[aout]") }
            args += ["-filter_complex",filters.joined(separator: ";")]
            if videoOut { args += ["-map","[vout]"] }; if audioOut { args += ["-map","[aout]"] }
        } else {
            if !s.format.audioOnly { args += ["-map","0:v:0"] }
            if hasAudio { args += ["-map","0:a:0"] }
            if !s.lossless {
                if !s.format.audioOnly { args += ["-vf",videoFilters(s).joined(separator: ",")] }
                if hasAudio { args += ["-af","atempo=\(number(s.speed))"] }
            }
        }
        if s.end > 0 { args += ["-t",number((s.end-s.start)/s.speed)] }
        if s.lossless { args += ["-c","copy"] }
        else {
            if !s.format.audioOnly {
                let encoder = s.format == .webm ? "libvpx-vp9" : s.codec.encoder
                args += ["-c:v",encoder,"-pix_fmt","yuv420p"]
                if encoder.contains("videotoolbox") { args += ["-allow_sw","1","-b:v",String(s.bitrate > 0 ? s.bitrate : max(500, s.quality * 80))+"k"] }
                else if encoder == "libvpx-vp9" { args += ["-crf",String(63-s.quality*55/100),"-b:v",s.bitrate > 0 ? String(s.bitrate)+"k" : "0","-deadline","good","-cpu-used","4"] }
                else { args += ["-q:v",String(31-s.quality*29/100)] }
                if encoder == "hevc_videotoolbox" && s.format != .mkv { args += ["-tag:v","hvc1"] }
            }
            if s.format.audioOnly { args += ["-vn"] }
            if !s.mute && (hasAudio || (s.merge && inputs.count > 1)) {
                let audio: String
                switch s.format { case .mp3: audio="libmp3lame"; case .wav: audio="pcm_s16le"; case .webm: audio="vorbis"; default: audio="aac" }
                args += ["-c:a",audio]
                if audio == "vorbis" { args += ["-strict","experimental","-ac","2"] }
                if audio != "pcm_s16le" { args += ["-b:a",String(s.audioBitrate)+"k"] }
            }
        }
        if s.mute { args += ["-an"] }
        if [.mp4,.mov,.m4a].contains(s.format) { args += ["-movflags","+faststart"] }
        args += [output.path]
        return CommandPlan(arguments: args, duration: max(0, (s.end > 0 ? s.end-s.start : total-s.start)/s.speed), temporaryDirectory: temp)
    }
    static func videoFilters(_ s: ConversionSettings) -> [String] {
        var f = ["setpts=PTS/"+number(s.speed)]
        switch s.rotation { case 90: f += ["transpose=1"]; case 180: f += ["hflip","vflip"]; case 270: f += ["transpose=2"]; default: break }
        if s.flipH { f += ["hflip"] }; if s.flipV { f += ["vflip"] }
        if s.width > 0 { f += ["scale=\(s.width):-2"] }
        if s.frameRate > 0 { f += ["fps=\(s.frameRate)"] }; f += ["pad=ceil(iw/2)*2:ceil(ih/2)*2","setsar=1"]
        return f
    }
}
