import Foundation
public enum OutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4, mov, mkv, webm, mp3, m4a, wav
    public var id: String { rawValue }
    public var audioOnly: Bool { [.mp3,.m4a,.wav].contains(self) }
    public var title: String { rawValue.uppercased() }
}
public enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264, hevc, mpeg4
    public var id: String { rawValue }
    public var encoder: String { switch self { case .h264: return "h264_videotoolbox"; case .hevc: return "hevc_videotoolbox"; case .mpeg4: return "mpeg4" } }
    public var title: String { switch self { case .h264: return "H.264 · Apple"; case .hevc: return "HEVC · Apple"; case .mpeg4: return "MPEG-4 · CPU" } }
}
public struct ConversionSettings: Codable, Equatable, Sendable {
    public var format: OutputFormat = .mp4
    public var codec: VideoCodec = .h264
    public var quality: Int = 70
    public var bitrate: Int = 0
    public var audioBitrate: Int = 192
    public var width: Int = 0
    public var frameRate: Int = 0
    public var start: Double = 0
    public var end: Double = 0
    public var speed: Double = 1
    public var rotation: Int = 0
    public var flipH = false
    public var flipV = false
    public var mute = false
    public var lossless = false
    public var merge = false
    public init() {}
    public var transformed: Bool { width != 0 || frameRate != 0 || speed != 1 || rotation != 0 || flipH || flipV }
    public var requiredEncoder: String? { if lossless { return nil }; switch format { case .webm: return "libvpx-vp9"; case .mp3: return "libmp3lame"; case .m4a: return "aac"; case .wav: return "pcm_s16le"; default: return codec.encoder } }
}
public struct SavedPreset: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var settings: ConversionSettings
    public init(name: String, settings: ConversionSettings) { self.name = name; self.settings = settings }
}
