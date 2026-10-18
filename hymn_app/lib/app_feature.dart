/// 音频变体（与 Android Gradle flavor 一一对应）
///
/// 构建时通过 `--dart-define=AUDIO_VARIANT=<id>` 注入；
/// 未指定时默认 `full`（Windows 桌面 / 调试默认值）。
///
/// | id | 应用名 | 说明 |
/// | --- | --- | --- |
/// | `full` | 聆听赞美诗 | 全量音频（11 种版本，473+1 首可播） |
/// | `piano` | 聆听赞美诗（钢琴版） | 仅鋼琴版音频 + `249` 人聲版替代 |
/// | `vocal` | 聆听赞美诗（人声版） | 仅人聲版音频 + 2 首四部合唱版 + 9 首鋼琴版替代 |
/// | `lite` | 读谱版 | 无音频、无播放能力（纯看谱/读词/源考） |
enum AudioVariant {
  full('full', '聆听赞美诗'),
  piano('piano', '聆听赞美诗（钢琴版）'),
  vocal('vocal', '聆听赞美诗（人声版）'),
  lite('lite', '读谱版');

  const AudioVariant(this.id, this.displayName);

  /// 持久化 / 构建标识（与 flavor 名一致）
  final String id;

  /// 应用名后缀基（关于页、手册使用）
  final String displayName;
}

/// 构建期注入的变体标识
const String kAudioVariantId =
    String.fromEnvironment('AUDIO_VARIANT', defaultValue: 'full');

/// 当前变体（首次访问时解析一次；未知值回退 `full`）
final AudioVariant kAudioVariant = AudioVariant.values.firstWhere(
  (v) => v.id == kAudioVariantId,
  orElse: () => AudioVariant.full,
);

/// 是否具备音频播放能力（`lite` = false）
bool get kHasAudio => kAudioVariant != AudioVariant.lite;

/// 是否为「单音频版本」（钢琴版 / 人声版）—— 决定是否显示版本行、`👥`
bool get kSingleAudioVariant =>
    kAudioVariant == AudioVariant.piano || kAudioVariant == AudioVariant.vocal;

/// 是否为全量音频版（显示版本 chips 与 `👥`）
bool get kFullAudioVariant => kAudioVariant == AudioVariant.full;
