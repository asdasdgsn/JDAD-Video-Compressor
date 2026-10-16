import XCTest
@testable import ConverterCore
final class ProbeTests: XCTestCase {
    func testVideoWithoutAudioAndRotation() throws {
        let data = Data(#"{"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"avg_frame_rate":"30000/1001","side_data_list":[{"rotation":90}]}],"format":{"duration":"12.5"}}"#.utf8)
        let info = try MediaProbe.decode(data, url: URL(fileURLWithPath: "/tmp/测试 clip.mp4"))
        XCTAssertEqual(info.duration, 12.5); XCTAssertFalse(info.hasAudio)
        XCTAssertEqual(info.displayWidth, 1080); XCTAssertEqual(info.displayHeight, 1920)
        XCTAssertEqual(info.fps, 29.97, accuracy: 0.01)
    }
    func testRejectsInvalidAndNonMedia() {
        XCTAssertThrowsError(try MediaProbe.decode(Data("bad".utf8), url: URL(fileURLWithPath: "/tmp/a")))
        XCTAssertThrowsError(try MediaProbe.decode(Data(#"{"streams":[],"format":{}}"#.utf8), url: URL(fileURLWithPath: "/tmp/a")))
    }
}
final class CommandBuilderTests: XCTestCase {
    let media = MediaInfo(url: URL(fileURLWithPath: "/tmp/片 ' one.mp4"), duration: 10, width: 640, height: 360, videoCodec: "h264", audioCodec: "aac", fps: 30, rotation: 0, sampleRate: 48000, channels: 2)
    func testPathAndH264Arguments() throws {
        let plan = try CommandBuilder.build(inputs: [media], settings: .init(), output: URL(fileURLWithPath: "/tmp/out.mp4"))
        XCTAssertTrue(plan.arguments.contains(media.url.path)); XCTAssertTrue(plan.arguments.contains("h264_videotoolbox"))
        XCTAssertTrue(plan.arguments.contains("-progress")); XCTAssertFalse(plan.arguments.contains("-y"))
    }
    func testTransformAndTrim() throws {
        var s = ConversionSettings(); s.start = 1; s.end = 5; s.speed = 2; s.width = 320; s.rotation = 90
        let p = try CommandBuilder.build(inputs: [media], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp4"))
        let filter = p.arguments[p.arguments.firstIndex(of: "-vf")! + 1]
        XCTAssertTrue(filter.contains("transpose=1")); XCTAssertTrue(filter.contains("scale=320:-2")); XCTAssertTrue(filter.contains("setpts=PTS/2"))
        XCTAssertTrue(p.arguments.contains("atempo=2")); XCTAssertEqual(p.duration, 2, accuracy: 0.01)
    }
    func testAudioAndWebMAndHEVC() throws {
        for pair in [(OutputFormat.mp3,"libmp3lame"),(.m4a,"aac"),(.wav,"pcm_s16le"),(.webm,"libvpx-vp9")] {
            var s = ConversionSettings(); s.format = pair.0
            let p = try CommandBuilder.build(inputs: [media], settings: s, output: URL(fileURLWithPath: "/tmp/out." + pair.0.rawValue))
            XCTAssertTrue(p.arguments.contains(pair.1))
        }
        var s = ConversionSettings(); s.codec = .hevc
        XCTAssertTrue(try CommandBuilder.build(inputs: [media], settings: s, output: URL(fileURLWithPath: "/tmp/a.mp4")).arguments.contains("hevc_videotoolbox"))
    }
    func testNoAudioAndInvalidSettings() throws {
        var m = media; m.audioCodec = nil
        var s = ConversionSettings(); s.speed = 0.5
        let p = try CommandBuilder.build(inputs: [m], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp4"))
        XCTAssertFalse(p.arguments.contains("-af"))
        s.lossless = true
        XCTAssertThrowsError(try CommandBuilder.build(inputs: [m], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp4")))
        s = .init(); s.end = 20
        XCTAssertThrowsError(try CommandBuilder.build(inputs: [m], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp4")))
        s = .init(); s.format = .mp3
        XCTAssertThrowsError(try CommandBuilder.build(inputs: [m], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp3")))
    }
    func testMergeCompatibilityAndInputProtection() {
        var m = media; m.width = 1280
        var s = ConversionSettings(); s.merge = true; s.lossless = true
        XCTAssertThrowsError(try CommandBuilder.build(inputs: [media,m], settings: s, output: URL(fileURLWithPath: "/tmp/o.mp4")))
        XCTAssertThrowsError(try CommandBuilder.build(inputs: [media], settings: .init(), output: media.url))
    }
}
final class PersistenceTests: XCTestCase {
    func testRoundTripAndCollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONStore(directory: root)
        try store.save([SavedPreset(name: "测试", settings: .init())], file: "presets.json")
        let loaded: [SavedPreset] = store.load(file: "presets.json", fallback: [])
        XCTAssertEqual(loaded.first?.name, "测试")
        try Data().write(to: root.appendingPathComponent("a.mp4"))
        XCTAssertEqual(OutputAllocator.unique(directory: root, name: "a", extension: "mp4").lastPathComponent, "a-2.mp4")
        try Data("broken".utf8).write(to: root.appendingPathComponent("presets.json"))
        let broken: [SavedPreset] = store.load(file: "presets.json", fallback: [])
        XCTAssertTrue(broken.isEmpty); XCTAssertFalse(store.diagnostics.isEmpty)
    }
    func testHistoryRecovery() {
        var item = QueueItem(inputs: [], settings: .init(), output: URL(fileURLWithPath: "/tmp/a"))
        item.status = .running
        XCTAssertEqual(item.recovered().status, .interrupted)
    }
}
final class ProgressTests: XCTestCase {
    func testProgressParser() {
        XCTAssertEqual(ProgressParser.fraction(line: "out_time_us=2500000", duration: 10)!, 0.25)
        XCTAssertNil(ProgressParser.fraction(line: "bitrate=N/A", duration: 10))
        XCTAssertEqual(ProgressParser.fraction(line: "out_time_us=20000000", duration: 10)!, 0.99)
    }
}
final class SafetyTests: XCTestCase {
    let media = MediaInfo(url:URL(fileURLWithPath:"/tmp/a.mp4"),duration:5,width:641,height:359,videoCodec:"h264",audioCodec:"aac",fps:30)
    func testAudioOnlyMuteRejected() {
        var s=ConversionSettings();s.format = .m4a;s.mute=true
        XCTAssertThrowsError(try CommandBuilder.build(inputs:[media],settings:s,output:URL(fileURLWithPath:"/tmp/b.m4a")))
    }
    func testUnknownDurationMergeRejected() {
        var m=media;m.duration=0
        var s=ConversionSettings();s.merge=true
        XCTAssertThrowsError(try CommandBuilder.build(inputs:[m,media],settings:s,output:URL(fileURLWithPath:"/tmp/b.mp4")))
    }
    func testOddVideoGetsEvenPadding() throws {
        let p = try CommandBuilder.build(inputs:[media],settings:.init(),output:URL(fileURLWithPath:"/tmp/b.mp4"))
        XCTAssertTrue(p.arguments.joined(separator:" ").contains("pad=ceil(iw/2)*2:ceil(ih/2)*2"))
    }
}
final class ProcessTests: XCTestCase {
    func testNonzeroExitHasUsefulDiagnostic() async {
        do { _ = try await ProcessCapture.run(executable:URL(fileURLWithPath:"/usr/bin/false"),arguments:[]);XCTFail("Expected failure") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
    func testStdoutAndStderrAreDrainedTogether() async throws {
        let data = try await ProcessCapture.run(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","i=0; while [ $i -lt 3000 ]; do printf 'diagnostic message\\n' >&2; i=$((i+1)); done; printf ok"])
        XCTAssertEqual(String(decoding:data,as:UTF8.self),"ok")
    }
}
final class ReviewRegressionTests: XCTestCase {
    func testAnamorphicDisplayDimensions() throws {
        let data=Data(#"{"streams":[{"codec_type":"video","codec_name":"h264","width":720,"height":576,"sample_aspect_ratio":"16:15"}],"format":{"duration":"2"}}"#.utf8)
        let m=try MediaProbe.decode(data,url:URL(fileURLWithPath:"/tmp/a.mp4"))
        XCTAssertEqual(m.displayWidth,768);XCTAssertEqual(m.displayHeight,576)
        let p=try CommandBuilder.build(inputs:[m],settings:.init(),output:URL(fileURLWithPath:"/tmp/b.mp4"))
        XCTAssertTrue(p.arguments.joined(separator:" ").contains("iw*sar"))
    }
    @MainActor func testRetriesReserveDistinctQueuedOutputs() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let queue=QueueStore(directory:dir)
        let m=MediaInfo(url:dir.appendingPathComponent("missing.mp4"),duration:5,width:320,height:240,videoCodec:"h264")
        var failed=QueueItem(inputs:[m],settings:.init(),output:dir.appendingPathComponent("out.mp4"));failed.status = .failed
        queue.items=[failed];queue.retry(id:failed.id);queue.retry(id:failed.id)
        let reserved=queue.items.filter{$0.status == .waiting || $0.status == .running}.map(\.output.path)
        XCTAssertEqual(Set(reserved).count,reserved.count)
        queue.shutdown()
    }
    func testCaptureCancellationStopsWaitingForProcess() async throws {
        let start=Date()
        let task=Task {try await ProcessCapture.run(executable:URL(fileURLWithPath:"/bin/sleep"),arguments:["3"])}
        try await Task.sleep(nanoseconds:50_000_000);task.cancel()
        do {_ = try await task.value;XCTFail("Cancellation must throw")} catch is CancellationError {} catch {XCTFail("Unexpected \(error)")}
        XCTAssertLessThan(Date().timeIntervalSince(start),1.5)
    }
}
final class StreamSelectionTests: XCTestCase {
    func testAttachedCoverIsExcludedFromConversion() throws {
        let data=Data(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"mjpeg","width":600,"height":600,"disposition":{"attached_pic":1}},{"index":1,"codec_type":"video","codec_name":"h264","width":640,"height":360}],"format":{"duration":"2"}}"#.utf8)
        let m=try MediaProbe.decode(data,url:URL(fileURLWithPath:"/tmp/cover.mp4"))
        XCTAssertEqual(m.width,640)
        let p=try CommandBuilder.build(inputs:[m],settings:.init(),output:URL(fileURLWithPath:"/tmp/b.mp4"))
        XCTAssertTrue(p.arguments.contains("0:V:0"))
    }
}

final class FileSizeTests: XCTestCase {
    func testActualSizeAndHistoryPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 2048).write(to: url)
        let media = MediaInfo(url: url, duration: 1)
        XCTAssertEqual(media.fileSize, 2048)
        var item = QueueItem(inputs: [media, media], settings: .init(), output: url)
        item.outputBytes = 1024
        let data = try JSONEncoder().encode(item)
        try FileManager.default.removeItem(at: url)
        let decoded = try JSONDecoder().decode(QueueItem.self, from: data)
        XCTAssertEqual(decoded.inputBytes, 4096)
        XCTAssertEqual(decoded.outputBytes, 1024)
        XCTAssertEqual(FileSize.reduction(input: decoded.inputBytes, output: decoded.outputBytes), 75)
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old.removeValue(forKey: "inputBytes"); old.removeValue(forKey: "outputBytes")
        var inputs = old["inputs"] as! [[String: Any]]
        for i in inputs.indices { inputs[i].removeValue(forKey: "fileSize") }
        old["inputs"] = inputs
        let legacy = try JSONDecoder().decode(QueueItem.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.inputBytes)
        XCTAssertNil(FileSize.total(legacy.inputs))
    }
    func testLargerAndUnknownSizes() {
        XCTAssertEqual(FileSize.reduction(input: 100, output: 150), -50)
        XCTAssertNil(FileSize.reduction(input: 0, output: 100))
        XCTAssertNil(FileSize.reduction(input: nil, output: 100))
        XCTAssertEqual(FileSize.text(nil), "—")
    }
}
