# JDAD视频压缩工具

独立的原生 macOS 本地视频工作台，面向 macOS 14+、Apple Silicon。SwiftUI 界面，内置 FFmpeg/ffprobe；无账号、无云端处理。

## 下载与源码

- [官网介绍](https://phiba.jdad.online/index.html#jdad-video-compressor)
- [下载 Mac 版 1.0.3](https://phiba.jdad.online/downloads/JDAD-Video-Compressor-1.0.3-arm64.dmg)
- [GitHub 开源仓库](https://github.com/asdasdgsn/JDAD-Video-Compressor)

## 使用

1. 打开 DMG，将 JDAD视频压缩工具 拖到 Applications。
2. 打开应用，添加或拖入视频/音频。
3. 选择输出目录、格式和处理参数，点击“开始处理”。任务按顺序执行。
4. 对文件右键可调整合并顺序；输出成功后点击文件夹图标在 Finder 中显示。

此开发交付使用 ad-hoc 本地签名，未使用 Developer ID 签名或 Apple 公证。在其他 Mac 上，系统可能提示无法验证开发者。确认文件来源后，可通过“系统设置 → 隐私与安全性”允许打开。不要关闭系统整体安全机制。

## 功能

- 导入文件显示原始大小；任务完成显示实际输出大小及减少/增加比例，历史记录保存大小。

- MP4、MOV、MKV、WebM、MP3、M4A、WAV。
- Apple VideoToolbox H.264 / HEVC、CPU MPEG-4、CPU VP9，按真实引擎能力显示。
- 批量串行任务、进度、取消、重试、错误详情；历史和预设保存在 ~/Library/Application Support/FrameShift。
- 精确剪切、无损剪切、缩放、旋转、翻转、0.5–2 倍速、静音、音频导出。
- 无损或统一参数合并。无损模式校验主要流参数；编码器 extradata、色彩参数或时间基不同仍可能导致 FFmpeg 拒绝合并或需重编码，优先使用重编码合并。
- 系统支持格式使用 AVKit 播放；其他视频显示静态预览并保留转换功能。相机按钮保存剪切开始时间处的截图。
- 中文 / English 切换。原文件保留，输出同名自动编号。

## 限制

- 无损切点受关键帧限制。滤镜和变速需要重新编码。
- Apple 编码器可用性及速度由主机决定；允许系统软件回退。质量滑块对 Apple 编码映射到估算码率，可指定码率覆盖。不含 x264/x265。
- 合并使用每个输入的第一个视频和音频流；不保留其他音轨、字幕和附件。混合有声/无声片段时重编码合并会补静音。
- 历史可查看和重新提交，不支持断点续转。最多保存最近 500 条任务。
- 本次不含 Intel 安装包、在线服务、内购、iCloud 或自动更新。

## 构建

需要 Xcode/Command Line Tools、macOS 14+、Apple Silicon，及下载源码时的网络。

```sh
./scripts/build-engine.sh
swift test
./scripts/package.sh ./dist
./scripts/make-dmg.sh ./dist
```

build-engine.sh 从 FFmpeg 和 libvpx 官方发布源、LAME 项目的 SourceForge 发布地址获取源码，自行构建禁用 GPL/nonfree 的媒体工具，记录下载包 SHA-256。首次构建需数分钟；这些校验值是下载后记录，不代替上游签名验证。

```sh
FRAMESHIFT_ENGINE_DIR="$PWD/.engine/install/bin" swift run -c release MediaCheck /tmp/FrameShift-unique-validation-directory
```

验证目录必须是新的或为空；程序生成样例并验证真实媒体输出。请勿将验证目录指向你的媒体资料目录。

## 许可与源码

Swift 应用源代码按本目录 LICENSE 的 MIT 条款提供。媒体引擎及依赖保留各自许可。安装包内 Resources/LICENSES 及交付的 MediaEngine-Sources 源码归档提供相应说明。替换 FFmpeg 后需自行确认编码能力与兼容性，可重新进行本地签名。

安装包验证：

```sh
./scripts/verify-package.sh ./dist
```

生成的 DMG 附带媒体引擎源码归档。分发安装包时请保留这些源码与许可资料。


## 贡献

欢迎通过 GitHub Issues 反馈问题，或提交 Pull Request。请附上 macOS 版本、芯片型号、复现步骤及去除私人信息后的错误日志。修改后运行 `swift test`；涉及媒体处理逻辑时同时运行上述 MediaCheck 检查。

MIT 许可适用于本项目原创代码，不覆盖第三方依赖、品牌名称和图标素材。`Resources/AppIcon.png` 是项目提供的品牌素材，未另行授予 MIT 授权；制作衍生发行版时请替换为自己的图标。第三方媒体引擎许可详见 `LICENSES/`。
