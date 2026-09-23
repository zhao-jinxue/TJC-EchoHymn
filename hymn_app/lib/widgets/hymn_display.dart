import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../app.dart';
import '../models/hymn.dart';
import '../models/jianpu_grid.dart';
import '../services/audio_service.dart';
import '../services/app_paths.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../services/sqlite_repository.dart';
import '../theme/app_fonts.dart';
import 'jianpu_grid_view.dart';

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

  const HymnDisplay({
    super.key,
    required this.audio,
    this.initialMode,
    this.initialAutoPaging,
    this.onModeChanged,
    this.onAudioVersionChanged,
    this.onAutoPagingChanged,
    this.repo,
  });

  @override
  State<HymnDisplay> createState() => _HymnDisplayState();
}

class _HymnDisplayState extends State<HymnDisplay> {
  late DisplayMode _mode;

  /// 当前歌词页（0 基节号）
  int _page = 0;

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

  /// 当前诗歌的页数（歌词/曲谱模式 = 节数；简谱/五线谱 = 整页，翻页条不显示）
  int _pageCount(Hymn? hymn) {
    if (hymn == null) return 0;
    if (_mode == DisplayMode.score) {
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
    LogService.instance.info(
      LogTag.action,
      delta > 0 ? '歌词翻到下一页（第 ${next + 1} 节）' : '歌词翻到上一页（第 ${next + 1} 节）',
    );
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
          Divider(height: 1, color: AppColors.divider),
          _buildPlayerBar(hymn),
        ],
      ),
    );
  }

  // ============ 版本栏 ============
  Widget _buildVersionBar(Hymn? hymn) {
    return Container(
      height: 44,
      color: AppColors.versionBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _versionBtn(
            label: '钢琴版',
            icon: Icons.piano,
            active:
                hymn != null && widget.audio.currentAudioVersion.contains('鋼琴'),
            onTap: hymn == null ? null : () => _switchVersion(hymn, '鋼琴版'),
          ),
          const SizedBox(width: 8),
          _buildVoiceButton(hymn),
          const Spacer(),
          _modeBtn('歌词', DisplayMode.lyrics, Icons.lyrics_outlined),
          const SizedBox(width: 4),
          _modeBtn('曲谱', DisplayMode.score, Icons.queue_music),
          const SizedBox(width: 4),
          _modeBtn('简谱', DisplayMode.jianpu, Icons.music_note),
          const SizedBox(width: 4),
          _modeBtn('五线谱', DisplayMode.staff, Icons.graphic_eq),
        ],
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
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
  Widget _buildVoiceButton(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    if (hymn == null || voices.isEmpty) {
      return _versionBtn(label: '人声版', icon: Icons.mic, active: false);
    }
    final currentVoice = widget.audio.currentAudioVersion;
    final isVoiceActive = currentVoice.contains('人聲') ||
        currentVoice.contains('人声') ||
        !currentVoice.contains('鋼琴');
    return _versionBtn(
      label: '人声版',
      icon: Icons.mic,
      active: isVoiceActive,
      onTap: () => _switchVersion(hymn, voices.first),
    );
  }

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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon,
                  size: 15,
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
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
        return _buildJianpu(hymn);
      case DisplayMode.jianpu:
        return _buildScore(hymn.numberedPngPath, isEmpty: '暂无简谱');
      case DisplayMode.staff:
        return _buildScore(hymn.staffPngPath, isEmpty: '暂无五线谱');
    }
  }

  /// 「曲谱」：一页一节的简谱网格（**单声部**主旋律 + 该节一行歌词）
  ///
  /// 数据源 `jianpu_*` 三表（列 = 拍点）；**无网格数据时回退**该首简谱扫描图
  /// （老库、未收录、数据异常时不留空白）。
  /// 谱面各节共用（全库无「一块一节」结构）→ 切节只切换歌词行；
  /// 节数 > 1 时叠加「上一节/下一节 + 手自切换」控件，自动模式复用
  /// `autoPageIndexFor` 跟随播放进度。
  Widget _buildJianpu(Hymn hymn) {
    final stanzas = _jianpu.stanzaCount;
    final perStanza = stanzas > 1;
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
                  return Center(
                    child: Text(
                      '简谱加载中…',
                      style:
                          TextStyle(fontSize: 14, color: AppColors.textTertiary),
                    ),
                  );
                }
                return JianpuGridView(
                  score: _jianpu,
                  constraints: constraints,
                  stanza: perStanza ? _page + 1 : null,
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
              child: _buildPageNav(stanzas),
            ),
        ],
      ),
    );
  }

  /// 文字歌词页（**一页 = 一节**：正歌 + 副歌），叠加翻页与手自切换控件
  Widget _buildLyrics(Hymn hymn) {
    final pages = hymn.lyricPages;
    if (pages.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }
    final page = pages[_page.clamp(0, pages.length - 1)];

    // 歌词显示区：暖白背景（与左右侧栏冷灰形成轻微色差，便于感知区域大小）
    return Container(
      color: AppColors.lyricsBg,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildLyricPage(hymn, page, constraints),
            ),
          ),
          // 右上角：歌词翻页「手动 / 自动」切换按钮（默认自动）
          Positioned(top: 10, right: 12, child: _buildPagingModeButton()),
          // 底部中央：上一页 / 页码 / 下一页（仅多页时出现）
          if (pages.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: _buildPageNav(pages.length),
            ),
        ],
      ),
    );
  }

  /// 单页歌词渲染：字号受「铺满显示区」与「每行不换行」双约束
  Widget _buildLyricPage(
      Hymn hymn, LyricPage page, BoxConstraints constraints) {
    final conv = ChineseConvertService.instance;
    // 底部翻页条预留高度，避免歌词与控件重叠
    const padX = 24.0;
    const padTop = 24.0;
    const padBottom = 56.0;
    final availH =
        (constraints.maxHeight - padTop - padBottom).clamp(100.0, 4000.0);
    final availW = constraints.maxWidth - padX * 2;

    // 总行数：标题 + 本页歌词行
    // （2026-09-21 二轮反馈：「第 N 首」标题已删除——标题栏已有该信息）
    // （2026-09-21 五轮反馈：「第 N 节」标签也已删除——底部翻页条已给出节号）
    final lineCount = 1 + page.lineCount;
    final maxByH = lyricMaxFontByHeight(availH, lineCount);
    final maxByW = lyricMaxFontByWidth(availW, page.maxDisplayWidth);

    // K10c：字号完全由窗口尺寸决定（maxByH/maxByW），不再被固定 baseBody 卡住
    // （否则窗口放大后字号被卡死、无法铺满）。整体 +4 改善最小尺寸可读性，
    // 但**宽度上限是不可破的硬约束**——超过 maxByW 必须回钳，否则长句会被折行
    // （实测 343 首第 1 节 34 字全角句被折成两行，正是用户要求根治的现象）。
    // v1.5.0 字号等级：系数只作用于**高度方向**（行数少时字可更大），
    // 宽度受限的长句不会被放大到折行。
    final ls = AppFonts.lyricsScale;
    var size = maxByH * ls;
    if (size > maxByW) size = maxByW;
    size = size + 4.0 > maxByW ? maxByW : size + 4.0;
    final bodySize = size.clamp(12.0, 100.0);
    final titleSize = (bodySize * 1.4).clamp(16.0, 40.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
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
            Text(
              conv.toSimplified(hymn.title),
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
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
  Widget _buildPageNav(int total) {
    final current = _page.clamp(0, total - 1);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              tooltip: current > 0 ? '上一页：第 $current 节' : '已是第一节',
              enabled: current > 0,
              onTap: () => _turnPage(-1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '第 ${current + 1} / $total 节',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _pageBtn(
              icon: Icons.chevron_right,
              tooltip:
                  current < total - 1 ? '下一页：第 ${current + 2} 节' : '已是最后一节',
              enabled: current < total - 1,
              onTap: () => _turnPage(1),
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
  }) {
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
      return Center(
        child: Text(isEmpty, style: TextStyle(color: AppColors.textTertiary)),
      );
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
  Widget _buildPlayerBar(Hymn? hymn) {
    return Container(
      color: AppColors.playBarBg,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上层：进度条
          _buildProgress(),
          const SizedBox(height: 6),
          // 下层：控制按钮 + 人声版本列表（>1 时显示）
          _buildControls(hymn),
        ],
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
        // 左配重：音量控件（滑轨宽度由内部 LayoutBuilder 自适应本区分配）
        Expanded(child: _buildVolumeControl()),
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
                final pctW = 38 / s; // 视觉恒 38
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
                        ),
                      ),
                    ),
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

  Size? _natural; // 图片自然像素尺寸（解码完成后有效）
  double _zoom = 1.0; // 1=初始宽度；上限=歌词区宽/初始宽（build 内钳制）
  final ScrollController _scroll = ScrollController();
  ImageStream? _stream;
  ImageStreamListener? _listener;

  bool get _isNetwork => widget.path.startsWith('http');

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    late final ImageProvider provider;
    if (_isNetwork) {
      provider = NetworkImage(widget.path);
    } else {
      provider = FileImage(File(widget.path));
    }
    _stream = provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() => _natural = Size(info.image.width.toDouble(),
            info.image.height.toDouble()));
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
      _resolve();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final vpW = constraints.maxWidth;
      final vpH = constraints.maxHeight;
      final natural = _natural;

      // 初始显示宽度 baseW：图片 contain 进歌词区且不放大的结果。
      // 纵向长图 → 受高度限制，baseW < vpW（两侧留白，可滚轮放大填充）；
      // 横向宽图 → 受宽度限制，baseW = vpW（缩放区间退化为 1）。
      double baseW = vpW;
      if (natural != null && natural.width > 0 && natural.height > 0) {
        final fit = math.min(vpW / natural.width, vpH / natural.height);
        baseW = natural.width * math.min(fit, 1.0);
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
    return _isNetwork
        ? Image.network(widget.path,
            width: w, height: h, fit: BoxFit.contain, errorBuilder: _imageError)
        : Image.file(File(widget.path),
            width: w, height: h, fit: BoxFit.contain, errorBuilder: _imageError);
  }

  Widget _imageError(BuildContext context, Object error, StackTrace? stack) =>
      const Icon(Icons.broken_image);
}
