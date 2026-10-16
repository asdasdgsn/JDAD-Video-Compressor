# SDD ledger — plan: outputs/本地视频转换器实施计划.md
Pre-flight: tasks 1–4 share MediaInfo, ConversionSettings, CommandPlan and QueueStore; interfaces will be kept in ConverterCore.
Ruling: The chat has no existing Git project, so use a new isolated project directory and develop branch rather than a linked worktree; no existing user code is changed.
Ruling: Use an LGPL build with VideoToolbox H.264/HEVC and libvpx VP9; software H.264/HEVC is not available without additional codecs, and UI must reflect this.
Task 1: Media probing and capability interfaces implemented; ProbeTests 2/2 pass. Source builds in progress.
Task 2: Core parameter tests 5/5 pass; safety tests exposed 3 missing validations, added mute/unknown-duration rejection and even-dimension padding.
Task 3: Persistent history and progress tests pass; async shutdown now waits for process cleanup.
Task 4: SwiftUI app compiles in Release. Pending real app UI inspection.

Task 4: UI import reproduced SIGABRT in _AVKit_SwiftUI metadata initialization. Ruling: replace SwiftUI VideoPlayer with NSViewRepresentable AVPlayerView to support the actual macOS 15 runtime; playback functionality is preserved. Retest via UI required.
Task 4: Native AVPlayerView import/preview retest succeeds on macOS 15.7.1; no metadata crash.
Task 5: 23 real-media integration checks passed including both merge modes, speed, HEVC, WebM, audio exports, cancellation and history.

Final review: independent reviewer completed. Fixed four P2 findings: sample aspect normalization, output reservations on retry, cancellable auxiliary processes with awaited shutdown, and attached-picture exclusion. Each was reproduced with failing regression tests before fixes; suite now 19/19 green. 28 real-media checks green after the fixes, extended delivery checks pending.
Final: Ruling: retain documented first-stream output, keyframe copy-cut semantics, and advanced lossless compatibility boundary; these are stated in README, with re-encode merge available. Unnotarized Apple Silicon-only distribution follows approved scope.

Integration finding: PNG snapshot test failed because --disable-autodetect disabled system zlib and hence FFmpeg PNG encoder. Enable the macOS system zlib explicitly; rebuild and rerun all media checks. No additional redistributed library is introduced.
Task 1: complete. Bundled FFmpeg 8.0.3, libvpx 1.15.2, LAME 3.100 built; PNG added via system zlib. Network/GPL/nonfree disabled; system-only dependencies checked.
Task 2: complete. All parameter and review regression tests green.
Task 3: complete. Cancellation, cleanup, persistence, failover and retry reservations validated.
Task 4: complete. Release build and real native UI import/preview/conversion verified.
Task 5: media acceptance complete, 34/34. DMG verification pending final command.

Task 5: complete. Final 19/19 unit tests and 34/34 real media checks pass. Ad-hoc signature, system-only engine dependencies, PNG encoder, DMG checksum, read-only mount, Applications symlink and included source archive verified. Source tarballs match recorded checksums. No deferred minor findings.
Ruling: This is a new local deliverable repository without a base branch or remote; preserve develop and export source instead of initiating merge/PR workflows outside the user's requested scope.
