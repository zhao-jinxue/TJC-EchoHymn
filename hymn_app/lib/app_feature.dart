import 'package:flutter/foundation.dart' show ValueNotifier;

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

/// 构建期注入的变体标识（调试 / 桌面兜底）
const String kAudioVariantId =
    String.fromEnvironment('AUDIO_VARIANT', defaultValue: 'full');

/// 构建期变体（未知值回退 `full`）
final AudioVariant kBuildAudioVariant = AudioVariant.values.firstWhere(
  (v) => v.id == kAudioVariantId,
  orElse: () => AudioVariant.full,
);

/// **运行期**音频能力（2026-11-13 架构调整）
///
/// Android 主体 APK 不再按 flavor 裁剪 UI，而是**首启按前十首诗歌检测**
/// 实际存在哪些素材（扫描图 / 人声 / 钢琴），据此决定界面形态：
///
/// | 检测结果 | 生效变体 | UI |
/// | --- | --- | --- |
/// | 钢琴 + 人声 | `full` | 版本循环切换 + 播放条 |
/// | 仅钢琴 | `piano` | 无版本按钮 + 播放条 |
/// | 仅人声 | `vocal` | 无版本按钮 + 播放条 |
/// | 都没有（可能只有扫描图） | `lite` | 读谱形态：无播放条 |
///
/// 桌面（Windows）不参与检测：固定用构建期变体（`full`），行为与 v1.8.x 一致。
class AudioCapability {
  AudioCapability._();

  static final ValueNotifier<AudioVariant?> _detected =
      ValueNotifier<AudioVariant?>(null);

  /// 当前生效变体（检测结果优先，未检测时用构建期兜底）
  static AudioVariant get effective => _detected.value ?? kBuildAudioVariant;

  /// 是否已完成运行期检测
  static bool get detected => _detected.value != null;

  /// 最近一次检测是否发现扫描图（首启引导 / 模式按钮显隐用；随 [apply] 一起更新）
  static bool lastHasScores = false;

  /// 是否检测到扫描图（无扫描图时**移动端不显示简谱/五线谱模式**）
  static bool get hasScores => lastHasScores;

  static void apply(AudioVariant variant, {bool hasScores = false}) {
    lastHasScores = hasScores;
    _detected.value = variant;
  }

  static void reset() => _detected.value = null;
}

/// 当前生效变体（**运行期**；勿再用作编译期常量）
AudioVariant get kAudioVariant => AudioCapability.effective;

/// 是否具备音频播放能力（`lite` = false）
bool get kHasAudio => kAudioVariant != AudioVariant.lite;

/// 是否为「单音频版本」（钢琴版 / 人声版）—— 决定是否显示版本行、`👥`
bool get kSingleAudioVariant =>
    kAudioVariant == AudioVariant.piano || kAudioVariant == AudioVariant.vocal;

/// 是否为全量音频版（显示版本切换按钮与 `👥`）
bool get kFullAudioVariant => kAudioVariant == AudioVariant.full;
