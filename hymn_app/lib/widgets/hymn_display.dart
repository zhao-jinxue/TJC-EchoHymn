import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../app.dart';
import '../app_feature.dart';
import '../models/hymn.dart';
import '../models/jianpu_grid.dart';
import '../models/jianpu_pagination.dart';
import '../services/audio_service.dart';
import '../services/app_paths.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../services/sqlite_repository.dart';
import '../theme/app_fonts.dart';
import '../theme/app_palette.dart';
import '../theme/score_display_prefs.dart';
import 'jianpu_grid_view.dart';
import 'state_views.dart';

/// 歌词显示模式
///
/// `score` = 曲谱：**一页一节**的简谱网格（单声部主旋律 + 该节一行歌词；
///   数据源 `jianpu_*` 三表，APK 谱面 CSV 网格，列 = 拍点）；
/// `jianpu` = 简谱：**简谱扫描图片**（印刷四声部谱，作为参考图；可缩放拖动）；
/// `staff` = 五线谱扫描图片。
/// 旧名归一化：`scoreLyric` → `score`、`numbered` → `jianpu`、未知 → `歌词`。
enum DisplayMode { lyrics, score, jianpu, staff }

/// 主内容区：版本切换 + 歌词/谱面 + 播放控制
class HymnDisplay extends StatefulWidget {
  final AudioService audio;

  /// 初始歌词模式（状态恢复用）
  final String? initialMode;

  /// 初始歌词翻页模式（true=自动，状态恢复用）
  final bool? initialAutoPaging;

  /// 选中歌词模式回调（供上层持久化）
  final ValueChanged<String>? onModeChanged;

  /// 选中音频版本回调（供上层持久化）
  final ValueChanged<String>? onAudioVersionChanged;

  /// 手/自动翻页切换回调（供上层持久化）
  final ValueChanged<bool>? onAutoPagingChanged;

  /// 数据仓库（读 `jianpu_*` 三表渲染简谱网格视图；可为 null=该模式不可用）
  final SqliteRepository? repo;

  /// 歌词字号缩放（**仅 Android**；1.0 默认，范围 0.8~2.0）
  final double lyricScale;

  /// 歌词字号缩放变化回调（供上层持久化到 `state.json`）
  final ValueChanged<double>? onLyricScaleChanged;

  const HymnDisplay({
    super.key,
    required this.audio,
    this.initialMode,
    this.initialAutoPaging,
    this.onModeChanged,
    this.onAudioVersionChanged,
    this.onAutoPagingChanged,
    this.repo,
    this.lyricScale = 1.0,
    this.onLyricScaleChanged,
  });

  @override
  State<HymnDisplay> createState() => _HymnDisplayState();
}

class _HymnDisplayState extends State<HymnDisplay> {
  late DisplayMode _mode;

  /// 当前歌词页（0 基节号）
  int _page = 0;

  /// 曲谱分页结果（按小节；`_jianpu` 装载后计算，`ANDROID_PLAN §3.14`）
  JianpuPagination? _pagination;

  /// 「曲谱页渲染」日志去重键（每页只记一次，避免 build 刷屏）
  String? _lastPageLogKey;

  /// 翻页模式：true=自动（跟随播放进度），false=手动（按钮翻页）
  late bool _auto;

  /// 播放进度 / 播放器上报时长（自动翻页的两个输入）
  Duration _pos = Duration.zero;
  Duration _playerDur = Duration.zero;

  /// 上一次分页归属的「诗歌 + 音频版本」键，变化即复位到第 1 页
  String? _pageKey;

  /// 简谱网格数据（按诗歌异步装载，避免 UI 线程同步查库）
  JianpuScore _jianpu = JianpuScore.empty;

  /// 简谱数据装载归属的诗歌编号
  String? _scoreLoadedFor;

  /// 简谱装载中（占位显示用）
  bool _jianpuLoading = false;

  StreamSubscription? _statusSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  @override
  void initState() {
    super.initState();
    LogService.instance.info(LogTag.ui, '主内容区 HymnDisplay 初始化');
    _auto = widget.initialAutoPaging ?? true;
    // 模式归一化：历史 state.json 可能存旧名 ——
    // `scoreLyric`（旧 PDF 管线曲谱）→ `score`（新网格整页曲谱）；
    // `numbered`（旧简谱扫描图）→ `jianpu`（新网格一页一节）；未知值 → 「歌词」。
    _mode = switch (widget.initialMode) {
      'score' || 'scoreLyric' => DisplayMode.score,
      'jianpu' || 'numbered' => DisplayMode.jianpu,
      'staff' => DisplayMode.staff,
      _ => DisplayMode.lyrics,
    };
    _statusSub = widget.audio.statusStream.listen((s) {
      if (!mounted) return;
      setState(() {});
      if (s == PlayerStatus.error) _showAudioError();
    });
    // 进度/时长驱动自动翻页。positionStream 每秒推送一次，
    // **仅当页码真的变化才 setState**——否则歌词/曲谱区每秒无谓整树重建。
    _posSub = widget.audio.positionStream.listen((p) {
      if (!mounted) return;
      final old = _page;
      _pos = p;
      _applyAutoPage();
      if (_page != old) setState(() {});
    });
    _durSub = widget.audio.durationStream.listen((d) {
      if (!mounted) return;
      final old = _page;
      _playerDur = d;
      _applyAutoPage();
      if (_page != old) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  String get currentModeName => _mode.name;

  // ============ 分页（歌词模式按节翻页；简谱网格同页展示全部节） ============

  /// 当前诗歌的页数
  ///
  /// - **曲谱模式**：按**小节分页**（`ANDROID_PLAN §3.14` / B9 / C15）—— 页数来自 `JianpuPagination`；
  /// - 歌词模式：按节（`hymn.lyricPages.length`）。
  int _pageCount(Hymn? hymn) {
    if (hymn == null) return 0;
    if (_mode == DisplayMode.score) {
      // 曲谱：**一页一节**（节内按整小节折行，2026-10-27 定型）
      return _jianpu.stanzaCount > 1 ? _jianpu.stanzaCount : 1;
    }
    return hymn.lyricPages.length;
  }

  /// 异步装载简谱网格（一首一次；单首数百行记录，microtask 中查库不阻塞 UI）
  void _ensureJianpu(Hymn? hymn) {
    if (hymn == null || _mode != DisplayMode.score) return;
    if (_scoreLoadedFor == hymn.hymnNumber) return;
    if (_jianpuLoading) return;
    _jianpuLoading = true;
    _jianpu = JianpuScore.empty;
    final repo = widget.repo;
    final number = hymn.hymnNumber;
    Future.microtask(() {
      JianpuScore score;
      try {
        // 「曲谱」= 单声部（第一声部）网格：四部合唱谱只取女高/主旋律行 + 歌词行
        score = repo?.loadJianpuScore(number, firstVoiceOnly: true) ??
            JianpuScore.empty;
      } catch (e) {
        LogService.instance.error(LogTag.error, '装载简谱网格失败',
            detail: '诗歌: $number\n异常: $e');
        score = JianpuScore.empty;
      }
      if (!mounted) return;
      setState(() {
        _jianpuLoading = false;
        _scoreLoadedFor = number;
        _jianpu = score;
        // 曲谱按小节分页（§3.14）：每页 2 小节（可在 C-6 设置项里改 2/3/4 或自适应）
        _pagination = JianpuPagination.build(score, barsPerPage: 2);
      });
    });
  }

  /// 有效总时长（秒）：优先播放器上报，回退数据库 audio_durations
  double? _effectiveDuration(Hymn hymn) {
    final pd = _playerDur.inMilliseconds / 1000.0;
    if (pd > 5) return pd;
    return hymn.durationOf(widget.audio.currentAudioVersion) ??
        (hymn.audioDurations.isEmpty
            ? null
            : hymn.audioDurations.values.first);
  }

  /// 自动模式下按「进度 / (总时长/页数)」重算当前页（**只改状态，不 setState**，
  /// 由调用方统一 setState，避免嵌套 setState）
  void _applyAutoPage() {
    if (!_auto) return;
    final hymn = widget.audio.currentHymn;
    if (hymn == null) return;
    final pages = _pageCount(hymn);
    if (pages <= 1) return;
    _page = autoPageIndexFor(
      position: _pos,
      totalSeconds: _effectiveDuration(hymn) ?? 0,
      pageCount: pages,
    );
  }

  /// 切歌/切版本 → 复位第 1 页；进度缓存清零（新歌的 position 流尚未推送时不用旧值）
  void _resetPageIfNeeded(Hymn? hymn) {
    final key = hymn == null ? null : '${hymn.hymnNumber}|${widget.audio.currentAudioVersion}';
    if (key == _pageKey) return;
    _pageKey = key;
    _page = 0;
    _pos = Duration.zero;
    _playerDur = Duration.zero;
  }

  void _turnPage(int delta) {
    final hymn = widget.audio.currentHymn;
    final pages = _pageCount(hymn);
    if (pages == 0) return;
    final next = (_page + delta).clamp(0, pages - 1);
    if (next == _page) return;
    if (_mode == DisplayMode.score) {
      final pg = _pagination;
      final bar = (pg != null && !pg.isEmpty)
          ? '，${pg.pages[next].barRangeLabel}'
          : '';
      LogService.instance
          .info(LogTag.action, '曲谱翻到第 ${next + 1}/$pages 页$bar');
    } else {
      LogService.instance.info(
        LogTag.action,
        delta > 0 ? '歌词翻到下一页（第 ${next + 1} 节）' : '歌词翻到上一页（第 ${next + 1} 节）',
      );
    }
    setState(() => _page = next);
  }

  void _toggleAutoPaging() {
    setState(() => _auto = !_auto);
    widget.onAutoPagingChanged?.call(_auto);
    LogService.instance
        .info(LogTag.action, _auto ? '歌词翻页切换为自动模式' : '歌词翻页切换为手动模式');
    if (_auto) {
      setState(_applyAutoPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hymn = widget.audio.currentHymn;
    _resetPageIfNeeded(hymn);
    _ensureJianpu(hymn);
    return Container(
      color: AppColors.pageBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildVersionBar(hymn),
          Divider(height: 1, color: AppColors.divider),
          Expanded(child: _buildContent(hymn)),
          // 无音频版（lite）：**不显示播放条**（ANDROID_PLAN §3.1.15）；
          // 改为「浏览导航条」——只提供上一首 / 下一首，不出现播放、进度与音量。
          if (kHasAudio) ...[
            Divider(height: 1, color: AppColors.divider),
            _buildPlayerBar(hymn),
          ] else ...[
            Divider(height: 1, color: AppColors.divider),
            _buildBrowseBar(hymn),
          ],
        ],
      ),
    );
  }

  // ============ 版本栏 ============
  /// 顶栏按钮行（2026-10-28 用户定稿，三条规则）：
  ///
  /// 1. **音频区**：宽屏显示**两个独立按钮**（钢琴 / 人声，选中高亮）；
  ///    窄屏放不下才**自动合并**为单按钮循环切换 —— 按可用宽度自适应，不写死平台。
  /// 2. **文案**：移动端「钢琴 / 人声」；桌面保留「钢琴版 / 人声版」。
  /// 3. **对齐**：桌面**全部左对齐**（连续排列，不用两端分布）；
  ///    移动端保持「左音频 / 右模式」两组分明。
  Widget _buildVersionBar(Hymn? hymn) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    // **纯文本歌词模式**（2026-11-17 用户要求）：移动端既无音频、也无扫描图时，
    // 音频按钮与「简谱/五线谱」按钮都没有可选项 → 整行隐藏，把 44dp 高度让给歌词。
    if (isMobile && !kHasAudio && !AudioCapability.hasScores) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 44,
      color: AppColors.versionBarBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏判定（< 380dp 视为窄屏 → 合并音频按钮）
          final wide = constraints.maxWidth >= 380;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              // **两平台统一规则**（2026-10-28 用户澄清）：
              //   音频切换按钮组 → 靠左
              //   歌词模式按钮组 → 靠右
              // 中间自然留出空白，形成两个区域。（我上一轮把桌面改成"全部左对齐"是理解错了）
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ---- 左组：音频（**整组包成一个 child**）----
                // 关键：若把两个音频按钮直接展开在外层 children，`spaceBetween` 会把
                // 「钢琴版」推到最左、「人声版」推到中间/右侧（2026-10-28 实测就是这个现象）。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kFullAudioVariant) ...[
                      if (!wide)
                        // 窄屏：合并单按钮（点一下循环切换）
                        _versionBtn(
                          label: _voiceLabel(widget.audio.currentAudioVersion),
                          icon:
                              widget.audio.currentAudioVersion.contains('鋼琴')
                                  ? Icons.piano
                                  : Icons.record_voice_over,
                          active: true,
                          onTap: hymn == null
                              ? null
                              : () => _cycleAudioVersion(hymn),
                        )
                      else ...[
                        // 宽屏：两个独立按钮，选中高亮
                        _versionBtn(
                          label: isMobile ? '钢琴' : '钢琴版',
                          icon: Icons.piano,
                          active: hymn != null &&
                              widget.audio.currentAudioVersion.contains('鋼琴'),
                          onTap: hymn == null
                              ? null
                              : () => _switchVersion(hymn, '鋼琴版'),
                        ),
                        const SizedBox(width: 6),
                        _versionBtn(
                          label: isMobile ? '人声' : '人声版',
                          icon: Icons.record_voice_over,
                          active: hymn != null &&
                              !widget.audio.currentAudioVersion.contains('鋼琴'),
                          onTap: hymn == null
                              ? null
                              : () {
                                  final v = voiceVersions(hymn);
                                  _switchVersion(
                                      hymn, v.isEmpty ? '人聲版' : v.first);
                                },
                        ),
                      ],
                    ],
                  ],
                ),
                // ---- 右组：模式（靠右） ----
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _modeBtn('歌词', DisplayMode.lyrics, Icons.lyrics_outlined),
                    const SizedBox(width: 2),
                    // 「曲谱」**仅 Windows**（2026-11-17 收紧：Android/iOS/Linux/macOS 均不提供）
                    if (Platform.isWindows) ...[
                      _modeBtn('曲谱', DisplayMode.score, Icons.queue_music),
                      const SizedBox(width: 2),
                    ],
                    // 「简谱 / 五线谱」：Windows 始终显示；移动端仅在**检测到扫描图**时显示
                    // （2026-11-17：无扫描图时点开只会是"暂无"，故不显示）
                    if (Platform.isWindows || AudioCapability.hasScores) ...[
                      _modeBtn('简谱', DisplayMode.jianpu, Icons.music_note),
                      const SizedBox(width: 2),
                      _modeBtn('五线谱', DisplayMode.staff, Icons.graphic_eq),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 合并按钮：在该首的**可用版本**之间循环切换（2026-10-25 用户要求）
  ///
  /// 原来的「鋼琴版 / 人聲版」两个 chip + 👥 占满一行；合并后点按钮即切，
  /// 宽度省下约 80dp，模式按钮得以全部显示。
  ///
  /// ⚠️ 2026-10-25 实机 bug：此处原先用 [voiceVersions]（**只含人声版**，已滤掉
  /// 鋼琴版）→ 长度恒为 1 → 命中 `length < 2` 直接 return，点按钮**毫无反应**。
  /// 现改用 [AudioService.availableVersions]（全部版本，含鋼琴版）。
  void _cycleAudioVersion(Hymn hymn) {
    final versions = widget.audio.availableVersions(hymn);
    final current = widget.audio.currentAudioVersion;
    if (versions.length < 2) {
      // 只有一个版本时明确提示，避免"点了没反应"的错觉
      final only = versions.isEmpty ? '鋼琴版' : versions.first;
      LogService.instance.info(
        LogTag.action,
        '切换音频版本（合并按钮）：该首只有一个版本',
        detail: '可用版本: ${versions.join(' / ')} / 当前: $current',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('该首只有「${_voiceLabel(only)}」音频'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var idx = versions.indexOf(current);
    if (idx < 0) {
      // 记忆/实际版本不在列表里（降级替代、旧数据）→ 优先从人声版接着切
      idx = versions.indexWhere((v) => !v.contains('鋼琴'));
      if (idx < 0) idx = 0;
    }
    final next = versions[(idx + 1) % versions.length];
    LogService.instance.info(
      LogTag.action,
      '切换音频版本（合并按钮）',
      detail: '$current → $next（该首共 ${versions.length} 个版本）',
    );
    _switchVersion(hymn, next);
  }

  Widget _versionBtn({
    required String label,
    required IconData icon,
    required bool active,
    VoidCallback? onTap,
  }) {
    return Material(
      color: active ? AppColors.primary : AppColors.controlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: active ? Colors.transparent : AppColors.controlBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          // 2026-10-25 用户要求：按钮内除图标/文字外的留白尽量小
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 人声版本 = 音频版本中除「钢琴版」外
  List<String> voiceVersions(Hymn hymn) {
    final all = widget.audio.availableVersions(hymn);
    return all.where((v) => !v.contains('鋼琴')).toList();
  }

  String _voiceLabel(String v) =>
      ChineseConvertService.instance.toSimplified(v);

  /// 人声版切换按钮（切到第一个人声版本；多版本列表在播放条）
  Widget _modeBtn(String label, DisplayMode mode, IconData icon) {
    final selected = _mode == mode;
    return Material(
      color: selected ? AppColors.selectedBg : AppColors.controlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? Colors.transparent : AppColors.controlBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _setMode(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setMode(DisplayMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _page = 0; // 模式切换回到第一节
    });
    widget.onModeChanged?.call(mode.name);
    LogService.instance.info(
      LogTag.action,
      '切换歌词显示模式: ${mode.name}',
    );
  }

  Future<void> _switchVersion(Hymn hymn, String version) async {
    try {
      LogService.instance.info(
        LogTag.action,
        '切换音频版本: ${ChineseConvertService.instance.toSimplified(version)}',
        detail: '诗歌: 第 ${hymn.hymnNumber} 首《${hymn.title}》',
      );
      await widget.audio.switchAudioVersion(version);
      widget.onAudioVersionChanged?.call(version);
      if (mounted) setState(() {});
    } catch (e) {
      LogService.instance.error(
        LogTag.error,
        '切换音频版本异常',
        detail: '版本: $version\n异常: $e',
      );
      _showAudioError();
    }
  }

  // ============ 内容区 ============
  Widget _buildContent(Hymn? hymn) {
    if (hymn == null) {
      return Center(
        child: Text(
          '请在左侧选择一首诗歌',
          style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
        ),
      );
    }

    switch (_mode) {
      case DisplayMode.lyrics:
        return _buildLyrics(hymn);
      case DisplayMode.score:
        // **仅 Windows 提供「曲谱」模式**（2026-11-17 收紧：移动端与其它桌面平台均不提供）。
        // 若 state.json 里残留 score（旧状态/跨平台同步）→ 回退歌词页。
        if (!Platform.isWindows) return _buildLyrics(hymn);
        return _buildJianpu(hymn);
      case DisplayMode.jianpu:
        // 移动端未检测到扫描图 → 回退歌词（纯文本模式，避免露出"暂无简谱"空页）
        if (!Platform.isWindows && !AudioCapability.hasScores) {
          return _buildLyrics(hymn);
        }
        return _buildScore(hymn.numberedPngPath, isEmpty: '暂无简谱');
      case DisplayMode.staff:
        if (!Platform.isWindows && !AudioCapability.hasScores) {
          return _buildLyrics(hymn);
        }
        return _buildScore(hymn.staffPngPath, isEmpty: '暂无五线谱');
    }
  }

  /// 「曲谱」：**一页一节 + 节内按整小节折行**（单声部主旋律 + 该节歌词行）
  ///
  /// 数据源 `jianpu_*` 三表（列 = 拍点）；**无网格数据时回退**该首简谱扫描图
  /// （老库、未收录、数据异常时不留空白）。
  ///
  /// **2026-10-27 定型**（用户多轮反馈后的最终形态）：
  /// - **一页只显示一节**（`stanza: 当前节`）—— 多节同屏会让 2~3 行歌词混在一起，用户明确不要；
  /// - **节内按整小节折行**（见 `JianpuGridView` 移动端折行）→ 一行 1~2 小节、歌词约 26.5sp；
  /// - 节数 > 1 时叠加「上一节/下一节 + 手自切换」控件。
  ///
  /// 轨迹：C-4「按小节分页 + 全部节同页」→ 2026-10-25「一页一节」→
  /// 2026-10-27 中途误改为「整页形态（全部节同页）」以对齐参考 APK，实机是多节混排
  /// → 定型为「**一页一节 + 折行**」：既拿到大字，又不让多节歌词挤在一起。
  Widget _buildJianpu(Hymn hymn) {
    final stanzas = _jianpu.stanzaCount;
    final total = stanzas > 1 ? stanzas : 1;
    final perStanza = total > 1;
    return Container(
      color: AppColors.lyricsBg,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_jianpu.isEmpty) {
                  if (!_jianpuLoading) {
                    return _buildScore(hymn.numberedPngPath,
                        isEmpty: '暂无简谱');
                  }
                  return const LoadingView(message: '简谱加载中…');
                }
                final stanzaNo =
                    perStanza ? _page.clamp(0, stanzas - 1) + 1 : null;
                final key = 'stanza=$stanzaNo';
                if (_lastPageLogKey != key) {
                  _lastPageLogKey = key;
                  // 字号可测量化（2026-10-27）：折行后的真实列数 / 槽宽 / 字号
                  var maxCols = 0;
                  for (final b in _jianpu.blocks) {
                    if (b.colCount > maxCols) maxCols = b.colCount;
                  }
                  final availW =
                      (constraints.maxWidth - JianpuGridView.padX * 2);
                  final gaps = <int>[
                    for (final b in _jianpu.blocks)
                      JianpuGridView.minLyricColGap(b),
                  ];
                  final gap =
                      gaps.isEmpty ? 1 : gaps.reduce((a, b) => a > b ? a : b);
                  final lyricEm = gap <= 1
                      ? JianpuGridView.lyricFontEmFor
                      : (gap * 0.92).clamp(JianpuGridView.lyricFontEmFor, 2.6);
                  // 平衡点（与渲染同一函数）→ 日志给出**真实每段小节数与字号**
                  final availH = (constraints.maxHeight -
                          JianpuGridView.padTop -
                          JianpuGridView.padBottom)
                      .clamp(60.0, 100000.0);
                  final (bpsLog, slotLog) = JianpuGridView.fitFullPage(
                    _jianpu,
                    availW,
                    availH,
                    gaps,
                    (kind, g) => switch (kind) {
                      JianpuRowKind.note => 1.27,
                      JianpuRowKind.markUp => 0.48,
                      JianpuRowKind.markDown => 0.55,
                      JianpuRowKind.lyric => 1.5,
                      JianpuRowKind.blank => 0.30,
                    },
                  );
                  final slot = slotLog > 0 ? slotLog : availW / 10;
                  LogService.instance.info(
                    LogTag.ui,
                    '曲谱页渲染（一页一节 + 整小节折行）',
                    detail: '第 ${stanzaNo ?? 1} / $stanzas 节'
                        '（块数 ${_jianpu.blocks.length}，最大列数 $maxCols，'
                        '歌词列距 $gap）\n'
                        '可用宽 ${availW.toStringAsFixed(0)}dp / 可用高 ${availH.toStringAsFixed(0)}dp\n'
                        '基准：歌词 ≥18sp（折行优先，允许轻微滚动）；'
                        '估算每段 $bpsLog 小节 / 槽宽 ${slot.toStringAsFixed(1)}dp'
                        ' → 音符 ${(slot * JianpuGridView.noteFontEmFor).toStringAsFixed(1)}sp'
                        ' / 歌词 ${(slot * lyricEm).toStringAsFixed(1)}sp'
                        '（${lyricEm.toStringAsFixed(2)} em）',
                  );
                }
                // **曲谱不跟随「设置 → 字号」与系统字体缩放**（2026-10-27 用户要求）：
                // 曲谱字号由本算法按「列数 / 行数 / 最小可读字号」严格计算，
                // 任何外部缩放都会破坏列对齐与折行结果 → 这里强制关闭文本缩放。
                return MediaQuery.withNoTextScaling(
                  child: JianpuGridView(
                    score: _jianpu,
                    constraints: constraints,
                    // **一页一节**：只显示该节歌词行；节内由组件按整小节折行
                    stanza: stanzaNo,
                  ),
                );
              },
            ),
          ),
          if (perStanza)
            Positioned(top: 10, right: 12, child: _buildPagingModeButton()),
          if (perStanza)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: _buildPageNav(total),
            ),
        ],
      ),
    );
  }

  /// 文字歌词页（**一页 = 一节**：正歌 + 副歌），叠加翻页与手自切换控件
  Widget _buildLyrics(Hymn hymn) {
    final pages = hymn.lyricPages;
    if (pages.isEmpty) {
      return const EmptyView(
        icon: Icons.lyrics_outlined,
        message: '暂无歌词',
      );
    }
    final page = pages[_page.clamp(0, pages.length - 1)];

    // 移动端：翻页条占用独立的 56dp 区域（不再压住歌词）——
    // 2026-11-11 布局走查实测：横屏（914×411dp）等低高度场景下，
    // 字号系数会把内容撑出可用高度（可滚动），overlay 的翻页条会盖住第 3~4 行歌词。
    // 桌面保持原 overlay 版式（Windows golden 基准不变）。
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final navReserve = (isMobile && pages.length > 1) ? 44.0 : 0.0;

    // 歌词显示区：暖白背景（与左右侧栏冷灰形成轻微色差，便于感知区域大小）
    return Container(
      color: AppColors.lyricsBg,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: navReserve,
            child: LayoutBuilder(
              builder: (context, constraints) => _buildLyricPage(
                hymn,
                page,
                constraints,
                navReserved: navReserve > 0,
              ),
            ),
          ),
          // 右上角：歌词字号缩放（仅 Android）+ 手/自动切换
          Positioned(top: 10, right: 12, child: _buildLyricToolbar()),
          // 底部中央：上一页 / 页码 / 下一页（仅多页时出现）
          if (pages.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: _buildPageNav(pages.length, compact: isMobile),
            ),
        ],
      ),
    );
  }

  /// 单页歌词渲染：字号受「铺满显示区」与「每行不换行」双约束
  Widget _buildLyricPage(
      Hymn hymn, LyricPage page, BoxConstraints constraints,
      {bool navReserved = false}) {
    final conv = ChineseConvertService.instance;
    // 底部翻页条预留高度，避免歌词与控件重叠。
    // 移动端翻页条已有独立占位区（见 _buildLyrics 的 navReserve）→ 此处不再重复预留，
    // 否则字号会被压小两次。
    const padX = 24.0;
    const padTop = 24.0;
    final padBottom = navReserved ? 0.0 : 56.0;
    final availH =
        (constraints.maxHeight - padTop - padBottom).clamp(100.0, 4000.0);
    final availW = constraints.maxWidth - padX * 2;

    // 总行数：标题 + 本页歌词行
    // （2026-09-21 二轮反馈：「第 N 首」标题已删除——标题栏已有该信息）
    // （2026-09-21 五轮反馈：「第 N 节」标签也已删除——底部翻页条已给出节号）
    // 移动端**不显示诗歌名称**（标题栏已有该信息，2026-11-18 用户要求省出篇幅）
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final showTitle = !isMobile;
    final lineCount = (showTitle ? 1 : 0) + page.lineCount;
    final maxByH = lyricMaxFontByHeight(availH, lineCount);
    final maxByW = lyricMaxFontByWidth(availW, page.maxDisplayWidth);

    // K10c：字号完全由窗口尺寸决定（maxByH/maxByW），不再被固定 baseBody 卡住
    // （否则窗口放大后字号被卡死、无法铺满）。整体 +4 改善最小尺寸可读性，
    // 但**宽度上限是不可破的硬约束**——超过 maxByW 必须回钳，否则长句会被折行
    // （实测 343 首第 1 节 34 字全角句被折成两行，正是用户要求根治的现象）。
    // v1.5.0 字号等级：系数只作用于**高度方向**（行数少时字可更大），
    // 宽度受限的长句不会被放大到折行。
    //
    // 2026-11-11 布局走查修正（仅移动端）：**高度才是瓶颈时不叠加字号系数**。
    // 横屏（914×411dp）实测：availH 仅 ~151dp，maxByH（≈16.8sp）< maxByW，
    // 若仍 ×1.26 再 +4，内容总高必然超出可用高 → 歌词整段滚出可视区（只看得到标题）。
    // 此系数本是"高度有余量时把字放大"，高度不足时放大只会牺牲可见性。
    // 桌面（ls=1.0 且版式基准固定）不进入该分支，golden 基准不变。
    final ls = AppFonts.lyricsScale;
    final heightBound = isMobile && maxByH <= maxByW;
    var size = heightBound ? maxByH : maxByH * ls;
    if (size > maxByW) size = maxByW;
    if (!heightBound) {
      size = size + 4.0 > maxByW ? maxByW : size + 4.0;
    }
    // 歌词字号缩放（**仅 Android**，用户按钮调节，持久化到 state.json）
    final userScale = isMobile ? widget.lyricScale.clamp(0.8, 2.0) : 1.0;
    final bodySize = (size * userScale).clamp(12.0, 160.0);
    final titleSize = (bodySize * 1.4).clamp(16.0, 40.0);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      // 2026-09-22（用户反馈）：内容整体**垂直居中**。
      // 此前用 spaceBetween 把内容摊开铺满（标题贴顶、末行贴底），
      // 结果标题与歌词之间被拉出巨大空隙、整块内容偏上，用户要求居中；
      // 这里保留 minHeight（滚动与居中两不误）并把主轴改为 center——
      // 内容不足显示区时整块居中，超过时正常滚动（顶部不会被裁）。
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - padTop - padBottom)
              .clamp(0.0, double.infinity),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showTitle) ...[
              Text(
                conv.toSimplified(hymn.title),
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
            ],
            for (final line in page.verseLines)
              Text(
                conv.toSimplified(line),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: bodySize,
                  height: 1.8,
                  color: AppColors.textPrimary,
                ),
              ),
            if (page.hasChorus) ...[
              const SizedBox(height: 18),
              for (final line in page.chorusLines)
                Text(
                  conv.toSimplified(line),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: bodySize,
                    height: 1.8,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 歌词页右上角工具条：**字号缩小 / 放大（仅 Android）** + 手/自动切换。
  ///
  /// 桌面（Windows）不显示字号按钮，行为与 v1.8.x 一致。
  Widget _buildLyricToolbar() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (!isMobile) return _buildPagingModeButton();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _lyricScaleBtn(
          icon: Icons.text_decrease,
          tooltip: '缩小歌词字号',
          delta: -0.15,
        ),
        const SizedBox(width: 4),
        _lyricScaleBtn(
          icon: Icons.text_increase,
          tooltip: '放大歌词字号',
          delta: 0.15,
        ),
        const SizedBox(width: 6),
        _buildPagingModeButton(),
      ],
    );
  }

  /// 字号缩放按钮（0.8~2.0，步进 0.15）
  Widget _lyricScaleBtn({
    required IconData icon,
    required String tooltip,
    required double delta,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.controlBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: AppColors.controlBorder, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // 两位小数（避免 1.4499999… 这类浮点尾数写进 state.json）
            final next = (((widget.lyricScale + delta) * 100).round() / 100)
                .clamp(0.8, 2.0);
            if (next == widget.lyricScale) return;
            LogService.instance.info(
              LogTag.action,
              '歌词字号缩放: ${(next * 100).round()}%',
            );
            widget.onLyricScaleChanged?.call(next);
          },
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 18, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  /// 右上角「手动 / 自动」翻页切换按钮（默认自动：歌词随播放进度切节）
  Widget _buildPagingModeButton() {
    final auto = _auto;
    return Material(
      color: auto ? AppColors.primary : AppColors.controlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: auto ? Colors.transparent : AppColors.controlBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _toggleAutoPaging,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                auto ? Icons.autorenew : Icons.touch_app_outlined,
                size: 14,
                color: auto ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                auto ? '自动' : '手动',
                style: TextStyle(
                  fontSize: 12,
                  color: auto ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部翻页条：◀ 上一页 · 第 N / M 节 · 下一页 ▶
  ///
  /// 自带歌词区底色背景：内容超高时翻页条浮在文字之上，无背景会压字难读。
  Widget _buildPageNav(int total, {bool byBar = false, bool compact = false}) {
    final current = _page.clamp(0, total - 1);
    final unit = byBar ? '页' : '节';
    final barText = (byBar && _pagination != null && !_pagination!.isEmpty)
        ? '（${_pagination!.pages[current].barRangeLabel}）'
        : '';
    return Center(
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 4)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.lyricsBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pageBtn(
              icon: Icons.chevron_left,
              tooltip: current > 0 ? '上一页：第 $current $unit' : '已是第一$unit',
              enabled: current > 0,
              onTap: () => _turnPage(-1),
              compact: compact,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
              child: Text(
                '第 ${current + 1} / $total $unit$barText',
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _pageBtn(
              icon: Icons.chevron_right,
              tooltip: current < total - 1
                  ? '下一页：第 ${current + 2} $unit'
                  : '已是最后一$unit',
              enabled: current < total - 1,
              onTap: () => _turnPage(1),
              compact: compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBtn({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    // 移动端紧凑版：32dp 热区（原 48dp）→ 翻页条整体高度≈原来的 2/3
    if (compact) {
      return SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          iconSize: 20,
          icon: Icon(
            icon,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
          ),
          tooltip: tooltip,
          onPressed: enabled ? onTap : null,
        ),
      );
    }
    return IconButton(
      icon: Icon(
        icon,
        size: 26,
        color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
      ),
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
    );
  }

  Widget _buildScore(String path, {required String isEmpty}) {
    final abs = AppPaths.resolveAsset(path);
    // 网络来源判定与 _ScoreImageView 统一用 startsWith('http')——
    // contains 会让中段含 "http" 的本地路径跳过存在性检查，显示破图
    // 而非「暂无谱面」空态
    if (abs.isEmpty || !(abs.startsWith('http') || _fileExists(abs))) {
      // §3.0 Fallback：无谱面属**静默降级**，不弹错、不给重试
      return FallbackView(message: isEmpty);
    }
    return _ScoreImageView(path: abs);
  }

  bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  // ============ 播放条（两层） ============
  /// 浏览导航条（无音频形态）：上一首 / 当前诗歌 / 下一首。
  ///
  /// **高度 28dp**（2026-11-18 用户要求：原 56dp 太高，取一半即可）；
  /// 不出现播放、暂停、进度、时间、音量 —— lite 没有播放能力（§3.1.15）。
  Widget _buildBrowseBar(Hymn? hymn) {
    final title = hymn == null
        ? '未选择诗歌'
        : '第 ${hymn.hymnNumber} 首《'
            '${ChineseConvertService.instance.toSimplified(hymn.title)}》';
    return Container(
      color: AppColors.playBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              _browseBtn(
                icon: Icons.skip_previous,
                tooltip: '上一首',
                onTap: () => widget.audio.browsePrev(),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              _browseBtn(
                icon: Icons.skip_next,
                tooltip: '下一首',
                onTap: () => widget.audio.browseNext(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 浏览条按钮（28dp 紧凑热区）
  Widget _browseBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        iconSize: 18,
        icon: Icon(icon, color: AppColors.textPrimary),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPlayerBar(Hymn? hymn) {
    // 手机判定与 HomeScreen 保持一致：最短边 < 600dp = 手机（横屏也算）
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < 600;
    // 手机横屏（ANDROID_PLAN §3.1.10）：播放条 **64dp 单行**（进度 + 控制同行）
    if (isPhone && size.width > size.height) {
      return Container(
        color: AppColors.playBarBg,
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(child: _buildProgress()),
                const SizedBox(width: 8),
                _buildControlsCompact(hymn),
              ],
            ),
          ),
        ),
      );
    }
    // 手机竖屏（ANDROID_PLAN §3.1）：播放条 72dp 目标，横向留白收紧；
    // 底部手势条 inset 由 SafeArea 吃掉（HomeScreen 的 SafeArea 只管到顶栏）。
    final isNarrow = size.width < 600;
    return Container(
      color: AppColors.playBarBg,
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 10 : 24,
        isNarrow ? 2 : 4,
        isNarrow ? 10 : 24,
        isNarrow ? 0 : 8,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 上层：进度条
            _buildProgress(),
            SizedBox(height: isNarrow ? 2 : 6),
            // 下层：控制按钮 + 人声版本列表（>1 时显示）
            _buildControls(hymn),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    // v1.5.0 方案 B（音量百分比与上一首重叠的结构性根治）：
    // 单一 Row 镜像结构——左 Expanded(音量控件) / 中按钮组(固定) /
    // 右 Expanded(人声版本👥或空配重)。Flex 引擎把剩余宽度**等分**给
    // 左右 Expanded，天然保证：① 按钮组绝对居中（👥 显隐不影响）；
    // ② 音量控件与按钮组由布局互相隔离，几何上永不重叠。
    // 废除旧 Stack + leftMax(半宽-72) 手工几何预算（其假设按钮组宽
    // 144，实际播放键 iconSize42 使组宽 ~154，且无显式间距 → 重叠）。
    return Row(
      children: [
        // 左配重：**Android/iOS 不显示音量控件**（2026-10-28 用户要求：
        // 四个变体都不要音量调节按钮与音量图标 —— 手机用系统音量键即可）。
        // 桌面保留音量滑轨；移动端用等宽空占位，保证中间按钮组仍绝对居中。
        Expanded(
          child: (Platform.isAndroid || Platform.isIOS)
              ? const SizedBox.shrink()
              : _buildVolumeControl(),
        ),
        IconButton(
          icon: Icon(Icons.skip_previous, color: AppColors.textPrimary),
          tooltip: '上一首',
          onPressed: () => widget.audio.playPrev(),
        ),
        StreamBuilder<PlayerStatus>(
          stream: widget.audio.statusStream,
          builder: (context, snap) {
            final status = snap.data ?? PlayerStatus.idle;
            final playing = status == PlayerStatus.playing;
            return IconButton(
              iconSize: 42,
              icon: Icon(
                playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: AppColors.primary,
              ),
              tooltip: playing ? '暂停' : '播放',
              onPressed: () {
                LogService.instance.info(
                  LogTag.action,
                  playing ? '点击播放条：暂停' : '点击播放条：播放',
                );
                widget.audio.togglePlayPause();
              },
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.skip_next, color: AppColors.textPrimary),
          tooltip: '下一首',
          onPressed: () => widget.audio.playNext(),
        ),
        // 右配重：人声版本按钮（>1 时显示，悬停提示 10 秒；
        // 不显示时保持空 Expanded 占位，维持按钮组居中的对称性）
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: voices.length > 1
                ? _buildVoiceListButton(hymn!, voices)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  /// 手机横屏播放条（64dp 单行）用的紧凑控制组：
  /// 只保留图标（静音 / 上一首 / 播放·暂停 / 下一首 / 人声版本），不含滑轨与百分比
  /// —— 横向空间要留给进度条（`ANDROID_PLAN §3.1.10`）。
  Widget _buildControlsCompact(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 移动端不显示音量/静音图标（2026-10-28 用户定稿：四个变体都不要音量
        // 调节按钮与图标，手机用系统音量键）；桌面横屏保留。
        if (!(Platform.isAndroid || Platform.isIOS))
          ValueListenableBuilder<bool>(
            valueListenable: widget.audio.mutedNotifier,
            builder: (context, muted, _) => IconButton(
              iconSize: 24,
              tooltip: muted ? '取消静音' : '静音',
              icon: Icon(
                muted ? Icons.volume_off : Icons.volume_up,
                color: AppColors.textPrimary,
              ),
              onPressed: () => widget.audio.toggleMute(),
            ),
          ),
        IconButton(
          iconSize: 26,
          tooltip: '上一首',
          icon: Icon(Icons.skip_previous, color: AppColors.textPrimary),
          onPressed: () => widget.audio.playPrev(),
        ),
        StreamBuilder<PlayerStatus>(
          stream: widget.audio.statusStream,
          builder: (context, snap) {
            final playing =
                (snap.data ?? PlayerStatus.idle) == PlayerStatus.playing;
            return IconButton(
              iconSize: 38,
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: AppColors.primary,
              ),
              tooltip: playing ? '暂停' : '播放',
              onPressed: () {
                LogService.instance.info(
                  LogTag.action,
                  playing ? '点击播放条：暂停' : '点击播放条：播放',
                );
                widget.audio.togglePlayPause();
              },
            );
          },
        ),
        IconButton(
          iconSize: 26,
          tooltip: '下一首',
          icon: Icon(Icons.skip_next, color: AppColors.textPrimary),
          onPressed: () => widget.audio.playNext(),
        ),
        if (voices.length > 1) _buildVoiceListButton(hymn!, voices),
      ],
    );
  }

  /// 播放条左侧音量控件：静音图标 + 滑条 + 音量百分比
  ///
  /// 数据源为 `AudioService.volumeNotifier/mutedNotifier`（ValueNotifier）：
  /// 拖动滑条 / 点击静音 / 快捷键调节，都会更新同一来源并互相刷新。
  ///
  /// v1.5.0 方案 B（结构性根治，叠加于方案 A 的反向缩放策略之上）：
  /// 容器由 Stack+leftMax 手工预算改为 _buildControls 左 Expanded 实分配宽，
  /// 与按钮组由 Flex 布局天然隔离，百分比永不与上一首重叠——
  /// - 图标/百分比反向缩放（画布宽 = 48/系数、38/系数），**视觉恒为 48px/38px**，
  ///   不随字号挤占滑轨空间；
  /// - 滑轨宽度 = 剩余可用画布，上限 150 画布（默认档保持 150 零回归），
  ///   中/大档更宽更好拖；下限 40/系数 防极限窄场景 overflow；
  /// - 滑块/轨道经 SliderTheme 反向缩放（/系数），**视觉恒为 20px/4px**，
  ///   避免「轨道变短、滑块变大」的比例失调。
  Widget _buildVolumeControl() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.audio.volumeNotifier,
      builder: (context, volume, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.audio.mutedNotifier,
          builder: (context, muted, _) {
            final effective = muted ? 0.0 : volume;
            return LayoutBuilder(
              builder: (context, constraints) {
                final s = AppFonts.scale;
                final iconW = 48 / s; // 视觉恒 48
                // 手机竖屏（ANDROID_PLAN §3.1 播放条）：不显示百分比，把 38 画布让给滑轨——
                // 否则左 Expanded 仅 ~119dp，图标 48 + 滑轨下限 40 + 百分比 38 = 126 → Row 溢出 7.3px（实测）。
                final isNarrow = MediaQuery.sizeOf(context).width < 600;
                final pctW = isNarrow ? 0.0 : 38 / s; // 视觉恒 38（桌面）
                // 滑轨可用画布宽 = 左 Expanded 实分配宽 - 图标 - 百分比；
                // 上限 150 画布（默认档保持 150 视觉零回归）。
                // 方案 B 下限调整：旧下限 150/s（视觉恒≥150）在最大档
                // 基座窗口下会超出 Expanded 分配宽导致 Row overflow
                // （该场景滑轨物理上至多 ~147 视觉），改为 40/s 防溢出
                // 兜底；默认/中/大档不受影响（预算核算均 ≥150 视觉）。
                final avail = constraints.maxWidth - iconW - pctW;
                final sliderW = avail.clamp(40 / s, 150).toDouble();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: iconW,
                      height: 48,
                      child: Center(
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 24 / s, // 视觉恒 24
                          icon: Icon(
                            muted ? Icons.volume_off : Icons.volume_up,
                            color: AppColors.textPrimary,
                          ),
                          tooltip: muted ? '取消静音（Ctrl+M）' : '静音（Ctrl+M）',
                          onPressed: () => widget.audio.toggleMute(),
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.primary,
                        thumbColor: AppColors.primary,
                        // 滑块/轨道反向缩放 → 视觉恒 20px/4px，不随字号变形
                        trackHeight: 4 / s,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 10 / s),
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 20 / s),
                      ),
                      child: SizedBox(
                        width: sliderW,
                        child: Slider(
                          value: effective,
                          onChanged: (v) => widget.audio.setVolume(v),
                          semanticFormatterCallback: (v) =>
                              '音量 ${(v * 100).round()}%',
                        ),
                      ),
                    ),
                    if (!isNarrow)
                      SizedBox(
                        width: pctW,
                        child: Center(
                          child: Text(
                            '${(effective * 100).round()}%',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: 12 / s, // 视觉恒 12
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVoiceListButton(Hymn hymn, List<String> voices) {
    final currentVoice = widget.audio.currentAudioVersion;
    return Tooltip(
      message: '共 ${voices.length} 个人声版本，可选择切换',
      waitDuration: Duration.zero,
      showDuration: const Duration(seconds: 10),
      child: PopupMenuButton<String>(
        tooltip: '人声版本列表',
        initialValue:
            voices.contains(currentVoice) ? currentVoice : voices.first,
        onSelected: (v) => _switchVersion(hymn, v),
        icon: Icon(Icons.groups, size: 22, color: AppColors.textPrimary),
        itemBuilder: (ctx) => [
          for (final v in voices)
            PopupMenuItem(value: v, child: Text(_voiceLabel(v))),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return StreamBuilder<Duration>(
      stream: widget.audio.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.audio.durationStream,
          builder: (context, durSnap) {
            final dur = durSnap.data ?? Duration.zero;
            return Row(
              children: [
                Text(formatTime(pos),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Expanded(
                  child: Slider(
                    value: dur.inMilliseconds > 0
                        ? pos.inMilliseconds
                            .clamp(0, dur.inMilliseconds)
                            .toDouble()
                        : 0,
                    max: dur.inMilliseconds > 0
                        ? dur.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (v) =>
                        widget.audio.seek(Duration(milliseconds: v.toInt())),
                    // 无障碍（§3.0.5）：TalkBack 读到「播放进度 1 分 23 秒」
                    semanticFormatterCallback: (v) =>
                        '播放进度 ${formatTime(Duration(milliseconds: v.toInt()))}',
                  ),
                ),
                Text(formatTime(dur),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            );
          },
        );
      },
    );
  }

  void _showAudioError() {
    if (!mounted) return;
    final err = widget.audio.lastError;
    final msg = (err == null || err.isEmpty) ? '音频加载失败' : '音频加载失败：$err';
    LogService.instance.error(LogTag.error, '音频加载失败（Toast）', detail: msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 谱面图片查看器（简谱/五线谱）——宽度驱动缩放。
///
/// 替代旧 `InteractiveViewer`（默认 maxScale=2.5，纵向长图放大后宽度仍到不了
/// 歌词区边缘，两侧空白无法利用）。新语义：
/// - **最小宽度** = 初始 contain 显示宽度（不放大不缩小，即原默认视图）；
/// - **最大宽度** = 歌词区当前显示宽度（`LayoutBuilder` 实时取值，窗口拉伸/
///   最大化/字号等级变化自动跟随）；
/// - 滚轮语义（两条固定规则，消除缩放与滚动的双响应冲突）：
///   · **Ctrl+滚轮 = 缩放**：宽度在 [初始宽, 歌词区宽] 间连续变化，高度按
///     图片宽高比同步变大；
///   · 普通滚轮 = 上下滚动（内容不足一屏时无滚动空间，自然不动）；
///   · 缩放时经 `PointerSignalResolver` 认领事件，阻止 Scrollable 同时滚动；
///   · 认领 Listener 必须置于滚动内容**内部**（命中测试路径深者先注册
///     resolver，外层 Listener 会输给 Scrollable 内部监听器）；
/// - 横向图（初始宽度已=歌词区宽）缩放区间退化为 [1,1]，只剩纵向滚动，
///   与"放大宽度不超过歌词区"约束一致；
/// - 换歌/换谱面（path 变化）时缩放自动复位为初始。
class _ScoreImageView extends StatefulWidget {
  final String path;

  const _ScoreImageView({required this.path});

  @override
  State<_ScoreImageView> createState() => _ScoreImageViewState();
}

class _ScoreImageViewState extends State<_ScoreImageView> {
  /// 滚轮缩放速度：每像素滚动量对应的指数缩放因子
  static const double _wheelZoomSpeed = 0.0015;

  /// 解码分辨率倍率：**视口宽 × 设备像素比 × 该系数**
  ///
  /// 扫描图常见 2480×3508（A4 300dpi），全尺寸解码 ≈35 MB/张；连开几首即 OOM。
  /// 按 2 倍余量解码（手机约 4~8 MB/张）既够「铺满放大」查看，也不撑爆内存。
  static const double _decodeScale = 2.0;

  Size? _natural; // 解码后的像素尺寸（等比缩放，比例与原图一致）
  double _zoom = 1.0; // 1=初始宽度；上限=歌词区宽/初始宽（build 内钳制）
  final ScrollController _scroll = ScrollController();
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 当前解码宽度（0 = 尚未确定，见 build 的首帧调度）
  int _decodeWidth = 0;

  /// 是否已排入首帧后的解码调度（防重复）
  bool _resolveScheduled = false;

  /// 缩放上限（ANDROID_PLAN §3.11：`maxScale = 3.0×`，相对 contain 宽度）
  static const double _maxScale = 3.0;

  /// 手机触摸缩放/平移的变换控制器（桌面走原有滚轮 + 滚动逻辑，不受影响）
  final TransformationController _ivController = TransformationController();

  bool get _isNetwork => widget.path.startsWith('http');

  @override
  void initState() {
    super.initState();
    // 解码在首帧布局后按视口宽度决定（需要 constraints 才能算出解码尺寸），见 build。
  }

  /// 按解码宽度构造 provider（`_resolve` 与 `_buildImage` **必须用同一参数**，
  /// 否则 `ImageCache` 键不同 → 同一张图被解码两次，内存翻倍）。
  ImageProvider _provider(int decodeW) {
    if (_isNetwork) return NetworkImage(widget.path);
    final file = File(widget.path);
    if (decodeW <= 0) return FileImage(file);
    return ResizeImage(FileImage(file), width: decodeW, allowUpscaling: false);
  }

  String _baseName() {
    final p = widget.path;
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    return i >= 0 ? p.substring(i + 1) : p;
  }

  void _resolve(int decodeW) {
    _decodeWidth = decodeW;
    _stream = _provider(decodeW).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final w = info.image.width;
        final h = info.image.height;
        LogService.instance.info(
          LogTag.ui,
          '谱面图片解码完成',
          detail: '${_baseName()} → ${w}x$h（目标宽 $decodeW）',
        );
        setState(() => _natural = Size(w.toDouble(), h.toDouble()));
      },
      onError: (e, s) {
        LogService.instance.error(LogTag.ui, '谱面图片解码失败',
            detail: '${widget.path}\n$e');
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void didUpdateWidget(covariant _ScoreImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _detachStream();
      _natural = null;
      _zoom = 1.0;
      // 换谱面除复位缩放外，滚动位置也回顶部——否则停在谱尾切歌时，
      // 旧 offset 被钳位到新内容的随机位置（排帧：等新图布局完成后生效）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
      // 重新解码交给 build 的首帧调度（_stream == null 时会按新视口宽重算）。
    }
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detachStream();
    _scroll.dispose();
    _ivController.dispose();
    super.dispose();
  }

  // ============ 手机缩放包络（§3.11） ============

  /// 双击复位到 contain（§3.11「双击 → 复位到 contain」）
  void _resetZoom() {
    _ivController.value = Matrix4.identity();
    LogService.instance
        .info(LogTag.ui, '谱面缩放复位', detail: '双击/按钮 → 1.00×（contain）');
  }

  /// `＋ / －` 按钮缩放：以**视口中心**为不动点（§3.11）
  void _zoomBy(double factor) {
    final size = MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height / 2);
    final current = _ivController.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, _maxScale);
    final f = target / current;
    if ((f - 1).abs() < 0.001) return;
    final next = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_ivController.value.clone());
    _ivController.value = next;
    _logZoom();
  }

  void _logZoom() {
    final s = _ivController.value.getMaxScaleOnAxis();
    LogService.instance.info(
      LogTag.ui,
      '谱面缩放',
      detail: '${s.toStringAsFixed(2)}×（范围 1.00~${_maxScale.toStringAsFixed(2)}×）',
    );
  }

  Widget _zoomButton(IconData icon, String tooltip, double factor) {
    return Material(
      color: AppColors.controlBg,
      shape: const CircleBorder(),
      child: IconButton(
        iconSize: 20,
        tooltip: tooltip,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: Icon(icon, color: AppColors.textPrimary),
        onPressed: () => _zoomBy(factor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final vpW = constraints.maxWidth;
      final vpH = constraints.maxHeight;

      // 首帧后按视口宽决定解码尺寸。
      // 不能在 build 里直接 resolve：若该图已在 ImageCache，listener 会**同步**回调
      // setState → 触发 "setState() called during build"。
      if (_stream == null && !_resolveScheduled && vpW > 0) {
        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
        final decodeW = (vpW * dpr * _decodeScale).round().clamp(320, 2048);
        _resolveScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resolveScheduled = false;
          if (!mounted) return;
          _resolve(decodeW);
        });
      }
      else if (_stream != null && !_resolveScheduled && _decodeWidth > 0) {
        // 视口宽度**显著变化**（旋屏 / 收起侧栏 / 改字号等级）→ 重新按新宽度解码。
        // 实测：字号 ×1.9 + 左栏展开时内容区仅 ~82dp，解码宽被压到 432px；
        // 若此后视口变宽而沿用该图，放大查看会明显模糊。
        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
        final decodeW = (vpW * dpr * _decodeScale).round().clamp(320, 2048);
        if ((decodeW - _decodeWidth).abs() > _decodeWidth * 0.5) {
          _resolveScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _resolveScheduled = false;
            if (!mounted) return;
            _detachStream();
            _resolve(decodeW);
          });
        }
      }

      final natural = _natural;

      // 初始显示宽高：图片 contain 进可视区且不放大的结果。
      // 纵向长图 → 受高度限制，baseW < vpW（两侧留白）；横向宽图 → 受宽度限制。
      double baseW = vpW;
      double baseH = vpH;
      if (natural != null && natural.width > 0 && natural.height > 0) {
        final fit = math.min(vpW / natural.width, vpH / natural.height);
        final f = math.min(fit, 1.0);
        baseW = natural.width * f;
        baseH = natural.height * f;
      }

      // ---------- 手机：标准触摸缩放包络（ANDROID_PLAN §3.11）----------
      // minScale = contain 宽（1.0×）；maxScale = 3.0×；双击复位到 contain；
      // 边界回弹 24dp；横竖屏切换时交互矩阵保持不变（比例自然延续）。
      // 桌面仍走下方的「滚轮缩放 + 纵向滚动」逻辑，行为零改动。
      final mq = MediaQuery.sizeOf(context);
      if (mq.shortestSide < 600 && natural != null) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: _resetZoom,
                child: InteractiveViewer(
                  transformationController: _ivController,
                  minScale: 1.0,
                  maxScale: _maxScale,
                  boundaryMargin: const EdgeInsets.all(24), // §3.11 边界回弹 24dp
                  onInteractionEnd: (_) => _logZoom(),
                  child: SizedBox(
                    width: baseW,
                    height: baseH,
                    child: _buildImage(baseW, baseH),
                  ),
                ),
              ),
            ),
            // ＋/－（§3.11「以视口中心」缩放）：为不便双指的场合与自动化验证留入口。
            // 放**右上角横排**：位置随内容区顶部固定，便于稳定点中（右下角会随曲目/播放条浮动）。
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _zoomButton(Icons.remove, '缩小', 0.8),
                  const SizedBox(width: 8),
                  _zoomButton(Icons.add, '放大', 1.25),
                ],
              ),
            ),
          ],
        );
      }
      // 放大上限：图片宽度恰好铺满歌词区当前显示宽度
      final maxZoom = baseW > 0 ? vpW / baseW : 1.0;
      final zoom = _zoom.clamp(1.0, maxZoom);
      final dispW = baseW * zoom;
      final dispH = natural != null && natural.width > 0
          ? dispW * natural.height / natural.width
          : vpH;
      final canScrollV = dispH > vpH + 1;

      Widget child = SingleChildScrollView(
        controller: _scroll,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          // 不足一屏时等高居中；超出时按放大后真实高度供滚动条向下查看
          height: canScrollV ? dispH : vpH,
          // 滚轮监听必须放在滚动内容内部：Scrollable 经
          // PointerSignalResolver「先注册者赢」处理滚轮，而命中路径
          // 深者优先——放外层会被 Scrollable 抢走，Ctrl+滚轮缩放时会同时滚动
          child: Listener(
            onPointerSignal: (e) => _onWheel(e, maxZoom),
            child: Center(child: _buildImage(dispW, dispH)),
          ),
        ),
      );
      if (canScrollV) {
        child = Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: child,
        );
      }
      return child;
    });
  }

  /// 滚轮语义：普通滚轮 = 上下滚动（交给 Scrollable）；
  /// Ctrl+滚轮 = 缩放（并向 resolver 认领事件，阻止滚动视图同时滚动）
  void _onWheel(PointerSignalEvent e, double maxZoom) {
    if (e is! PointerScrollEvent || _natural == null) return;
    if (!HardwareKeyboard.instance.isControlPressed) return; // 普通滚轮 = 滚动
    // 先于 Scrollable 注册（本 Listener 命中路径更深），
    // 空回调仅用于占住 resolver，使 Scrollable 的注册被忽略
    GestureBinding.instance.pointerSignalResolver
        .register(e, (PointerSignalEvent _) {});
    final factor = math.exp(-e.scrollDelta.dy * _wheelZoomSpeed);
    setState(() => _zoom = (_zoom * factor).clamp(1.0, maxZoom));
  }

  Widget _buildImage(double w, double h) {
    final img = _isNetwork
        ? Image.network(widget.path,
            width: w, height: h, fit: BoxFit.contain, errorBuilder: _imageError)
        : Image(
            // 与 _resolve 使用同一 provider（ResizeImage 以解码宽为键）→ 共享 ImageCache，
            // 同一张图只解码一次；`cacheWidth` 也在此生效，避免全尺寸解码撑爆内存。
            image: _provider(_decodeWidth),
            width: w,
            height: h,
            fit: BoxFit.contain,
            errorBuilder: _imageError,
          );
    return _applyDarkTreatment(img);
  }

  /// 深色主题下的扫描谱面处理（`ANDROID_PLAN §3.10` **定稿**）
  ///
  /// - 浅色主题：原样（白底图本来就合适）
  /// - 深色 + `dim`（默认）：原色 + **20% 黑遮罩** —— 保留白底可读性、只降亮度
  ///   （反色会丢印刷谱细节，不采用；强制浅色违背用户选择）
  /// - 深色 + `invert`：反色（实验项，供用户自行对比）
  /// - 深色 + `original`：原样
  ///
  /// 曲谱网格不受影响（自绘 + `AppColors` 语义色）。
  Widget _applyDarkTreatment(Widget image) {
    final isDark =
        ThemeController.instance.current.brightness == Brightness.dark;
    if (!isDark) return image;
    return ValueListenableBuilder<String>(
      valueListenable: ScoreDisplayPrefs.instance.modeNotifier,
      builder: (context, mode, _) {
        if (mode == 'invert') {
          return ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              -1, 0, 0, 0, 255, //
              0, -1, 0, 0, 255, //
              0, 0, -1, 0, 255, //
              0, 0, 0, 1, 0, //
            ]),
            child: image,
          );
        }
        if (mode == 'dim') {
          return Stack(
            fit: StackFit.passthrough,
            children: [
              image,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black
                        .withValues(alpha: ScoreDisplayPrefs.dimAlpha),
                  ),
                ),
              ),
            ],
          );
        }
        return image;
      },
    );
  }

  Widget _imageError(BuildContext context, Object error, StackTrace? stack) =>
      const Icon(Icons.broken_image);
}
