import Foundation
import ConverterCore
@main struct MediaCheck {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.temporaryDirectory.appendingPathComponent("FrameShift-validation-"+UUID().uuidString).path)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let ffmpeg = try EnginePaths.tool("ffmpeg")
        var results: [String] = []
        func check(_ condition: Bool,_ name:String) throws {
            guard condition else { throw MediaError.message("FAILED: "+name) }; results.append("PASS "+name); print("PASS "+name)
        }
        let input = root.appendingPathComponent("测试 clip ' one.mp4")
        let input2 = root.appendingPathComponent("second.mp4")
        let silent = root.appendingPathComponent("silent.mp4")
        let different = root.appendingPathComponent("different.mp4")
        _ = try await ProcessCapture.run(executable:ffmpeg,arguments:["-v","error","-n","-f","lavfi","-i","testsrc2=size=320x240:rate=24:duration=3","-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=3","-c:v","h264_videotoolbox","-b:v","500k","-c:a","aac","-shortest",input.path])
        try FileManager.default.copyItem(at:input,to:input2)
        _ = try await ProcessCapture.run(executable:ffmpeg,arguments:["-v","error","-n","-i",input.path,"-an","-c:v","copy",silent.path])
        _ = try await ProcessCapture.run(executable:ffmpeg,arguments:["-v","error","-n","-i",input.path,"-vf","scale=160:120","-c:v","h264_videotoolbox","-c:a","aac",different.path])
        let media = try await MediaProbe.inspect(url:input)
        let m2 = try await MediaProbe.inspect(url:input2)
        let noAudio = try await MediaProbe.inspect(url:silent)
        let diff = try await MediaProbe.inspect(url:different)
        try check(media.hasAudio && media.width == 320 && abs(media.duration-3)<0.2,"probe Unicode and quoted path")
        let caps = try await EngineCapabilities.load()
        try check(["h264_videotoolbox","hevc_videotoolbox","libvpx-vp9","libmp3lame"].allSatisfy{caps.supports($0)},"bundled encoders")
        func convert(_ name:String,_ settings:ConversionSettings,_ inputs:[MediaInfo]) async throws -> MediaInfo {
            let out = root.appendingPathComponent(name+"."+settings.format.rawValue)
            let plan = try CommandBuilder.build(inputs:inputs,settings:settings,output:out)
            try await EngineRunner().run(plan:plan,progress:{_ in})
            return try await MediaProbe.inspect(url:out)
        }
        let regular = try await convert("regular",.init(),[media]); try check(regular.width == 320 && regular.hasAudio,"H264 conversion")
        var s = ConversionSettings();s.start=0.5;s.end=2.5
        let trim = try await convert("trim",s,[media]);try check(abs(trim.duration-2)<0.25,"precise trim duration")
        s = .init();s.lossless=true;s.end=2
        let copy = try await convert("copy",s,[media]);try check(copy.videoCodec==media.videoCodec && copy.duration < 2.5,"lossless trim")
        s = .init();s.rotation=90
        let rotated = try await convert("rotated",s,[media]);try check(rotated.width==240 && rotated.height==320,"rotation dimensions")
        s = .init();s.width=160
        let scaled = try await convert("scaled",s,[media]);try check(scaled.width==160 && scaled.height==120,"scale dimensions")
        s = .init();s.speed=2
        let faster = try await convert("faster",s,[media]);try check(abs(faster.duration-1.5)<0.25,"2x video and audio speed")
        s.speed=0.5
        let slower = try await convert("slower",s,[noAudio]);try check(abs(slower.duration-6)<0.3 && !slower.hasAudio,"0.5x silent video")
        for format in [OutputFormat.mp3,.m4a,.wav] {
            s = .init();s.format=format
            let audio = try await convert("audio-"+format.rawValue,s,[media]);try check(!audio.hasVideo && audio.hasAudio,"audio "+format.rawValue)
        }
        s = .init();s.format = .webm
        let webm = try await convert("webm",s,[media]);try check(webm.videoCodec=="vp9" && webm.hasAudio,"VP9 WebM")
        s = .init();s.codec = .hevc
        let hevc = try await convert("hevc",s,[media]);try check(hevc.videoCodec=="hevc","HEVC")
        s = .init();s.merge=true;s.lossless=true
        let merged = try await convert("merged-copy",s,[media,m2]);try check(abs(merged.duration-6)<0.3,"lossless merge")
        s.lossless=false
        let normalized = try await convert("merged-normalized",s,[media,diff,noAudio]);try check(abs(normalized.duration-9)<0.4 && normalized.hasAudio,"normalized merge mixed sizes and silent clip")
        s = .init();s.mute=true
        let muted = try await convert("muted",s,[media]);try check(!muted.hasAudio,"mute")
        let runner = EngineRunner()
        let cancelOut = root.appendingPathComponent("cancelled.mp4")
        let job = Task { try await runner.run(plan:CommandPlan(arguments:["-v","error","-re","-i",input.path,"-c","copy",cancelOut.path],duration:3),progress:{_ in}) }
        try await Task.sleep(nanoseconds:150_000_000); runner.cancel()
        do { try await job.value; throw MediaError.message("Cancellation did not throw") } catch is CancellationError { results.append("PASS process cancellation");print("PASS process cancellation") }
        let queue = QueueStore(directory:root.appendingPathComponent("history"))
        try queue.enqueue(inputs:[media,m2],settings:.init(),directory:root)
        let paths = queue.items.map(\.output.path)
        try check(Set(paths).count==2,"queue unique output allocation")
        queue.start()
        while queue.running { try await Task.sleep(nanoseconds:50_000_000) }
        try check(queue.items.allSatisfy{$0.status == .completed},"serial queue completion")
        let restored = QueueStore(directory:root.appendingPathComponent("history"))
        try check(restored.items.count==2 && restored.items.allSatisfy{$0.status == .completed},"history recovery")
        var invalid = ConversionSettings();invalid.format = .mp3
        do { try queue.enqueue(inputs:[noAudio],settings:invalid,directory:root);throw MediaError.message("Expected no-audio rejection") } catch { try check(!error.localizedDescription.contains("Expected"),"no-audio extraction rejection") }
        let before = try Data(contentsOf:input)
        do { let p=try CommandBuilder.build(inputs:[media],settings:.init(),output:input);try await EngineRunner().run(plan:p,progress:{_ in});throw MediaError.message("Input overwrite allowed") } catch { try check(before == Data(contentsOf:input),"original input protected") }
        try results.joined(separator:"\n").write(to:root.appendingPathComponent("RESULTS.txt"),atomically:true,encoding:.utf8)
        print("VERIFIED \(results.count) checks at \(root.path)")
    }
}
