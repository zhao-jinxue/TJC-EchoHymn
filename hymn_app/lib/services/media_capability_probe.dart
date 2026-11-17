import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../app_feature.dart';
import '../models/hymn.dart';
import 'app_paths.dart';
import 'log_service.dart';

/// 素材能力探测（2026-11-13 架构调整）
///
/// 主体 APK 不再内置素材；用户安装后导入「扫描图 / 人声音频 / 钢琴音频」压缩包。
/// 首启**按前十首诗歌**检测实际存在哪些文件，决定 UI 形态（见 [AudioCapability]）：
///
/// - 钢琴 + 人声 → `full`（显示版本切换按钮）
/// - 仅钢琴 → `piano`；仅人声 → `vocal`（无版本按钮）
/// - 都没有 → `lite`（读谱形态：无播放条）
///
/// 桌面（Windows）不做检测：固定构建期变体，行为与 v1.8.x 一致。
class MediaCapabilityProbe {
  MediaCapabilityProbe._();

  /// 抽样首数（用户 2026-11-13 指定：检测前十首）
  static const int sampleSize = 10;

  /// **导入完成信号**（设置页导入结束后 +1 → 主页重新检测并刷新 UI，免重启）。
  static final ValueNotifier<int> importTick = ValueNotifier<int>(0);

  /// 检测并应用到 [AudioCapability]，返回生效变体
  static Future<AudioVariant> detectAndApply(List<Hymn> hymns) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return kAudioVariant; // 桌面：保持构建期变体（Windows 零改动）
    }

    final sample = hymns.take(sampleSize).toList();
    var hasPiano = false;
    var hasVocal = false;
    var hasScores = false;

    bool exists(String rel) {
      if (rel.isEmpty) return false;
      final abs = AppPaths.resolveAsset(rel);
      if (abs.isEmpty) return false;
      try {
        return File(abs).existsSync();
      } catch (_) {
        return false;
      }
    }

    for (final h in sample) {
      for (final entry in h.audioVersions.entries) {
        if (!exists(entry.value)) continue;
        if (entry.key.contains('鋼琴')) {
          hasPiano = true;
        } else if (entry.key.contains('人聲') || entry.key.contains('合唱')) {
          hasVocal = true;
        }
      }
      if (exists(h.numberedPngPath) || exists(h.staffPngPath)) {
        hasScores = true;
      }
    }

    final variant = hasPiano && hasVocal
        ? AudioVariant.full
        : hasPiano
            ? AudioVariant.piano
            : hasVocal
                ? AudioVariant.vocal
                : AudioVariant.lite;
    AudioCapability.apply(variant, hasScores: hasScores);
    LogService.instance.info(
      LogTag.lib,
      '素材能力检测完成',
      detail: '抽样 ${sample.length} 首：钢琴=$hasPiano / 人声=$hasVocal / '
          '扫描图=$hasScores → ${variant.id}',
    );
    return variant;
  }
}
