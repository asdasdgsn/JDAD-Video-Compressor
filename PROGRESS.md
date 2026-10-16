# SDD ledger — plan: outputs/本地视频转换器实施计划.md
Pre-flight: tasks 1–4 share MediaInfo, ConversionSettings, CommandPlan and QueueStore; interfaces will be kept in ConverterCore.
Ruling: The chat has no existing Git project, so use a new isolated project directory and develop branch rather than a linked worktree; no existing user code is changed.
Ruling: Use an LGPL build with VideoToolbox H.264/HEVC and libvpx VP9; software H.264/HEVC is not available without additional codecs, and UI must reflect this.
Task 1: Media probing and capability interfaces implemented; ProbeTests 2/2 pass. Source builds in progress.
Task 2: Core parameter tests 5/5 pass; safety tests exposed 3 missing validations, added mute/unknown-duration rejection and even-dimension padding.
Task 3: Persistent history and progress tests pass; async shutdown now waits for process cleanup.
Task 4: SwiftUI app compiles in Release. Pending real app UI inspection.

Task 4: UI import reproduced SIGABRT in _AVKit_SwiftUI metadata initialization. Ruling: replace SwiftUI VideoPlayer with NSViewRepresentable AVPlayerView to support the actual macOS 15 runtime; playback functionality is preserved. Retest via UI required.
