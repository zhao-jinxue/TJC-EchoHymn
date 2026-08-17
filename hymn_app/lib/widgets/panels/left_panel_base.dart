import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hymn.dart';
import '../../services/audio_service.dart';
import '../../services/app_state_service.dart';
import '../../services/sqlite_repository.dart';

/// 播放回调：面板内点击播放后通知 HomeScreen 保存状态
class PlaybackEvent {
  final List<Hymn> contextList;
  final Hymn hymn;
  final int index;

  /// 播放来源：默认歌单的二级目录名（null = 非默认歌单）
  final String? sourceSubcategory;

  /// 播放来源：个人歌单名（null = 非个人歌单）
  final String? sourcePlaylistName;

  const PlaybackEvent({
    required this.contextList,
    required this.hymn,
    required this.index,
    this.sourceSubcategory,
    this.sourcePlaylistName,
  });
}

/// 左侧栏面板抽象基类（三个栏目共用契约）
///
/// 基类持有公共依赖与公共方法：
/// - `buildHymnTile`：诗歌行渲染（抽象接口，各子类实现自己的行样式/交互）
/// - `playHymn`：点击播放（公共，含播放上下文设置 + 通知上层保存）
/// - `scrollToCurrent`：滚动定位工具（公共）
/// - `restoreSaved`：恢复锚点（抽象，各子类按自身滚动列/展开逻辑实现）
///
/// `anchor`：启动恢复的锚点状态。面板首次挂载（或 anchor 变化）时自动调用
/// `restoreSaved` 恢复自身滚动/展开/分页状态。
abstract class LeftPanel extends StatefulWidget {
  final AudioService audio;
  final SqliteRepository repo;
  final ValueChanged<PlaybackEvent> onPlayback;
  final AppState? anchor;

  const LeftPanel({
    super.key,
    required this.audio,
    required this.repo,
    required this.onPlayback,
    this.anchor,
  });

  @override
  State<LeftPanel> createState();
}

abstract class LeftPanelState<P extends LeftPanel> extends State<P> {
  /// 列表项近似高度（滚动定位用）
  static const double itemHeight = 34;

  /// 顶部聊天栏固定高度兜底（子类可用 [scrollCurrentIntoView] 的 headerHeight 覆盖）
  static const double defaultHeaderHeight = 56;

  StreamSubscription<PlayerStatus>? _statusSub;

  /// 上次已联动滚动过的诗歌 id（避免暂停/进度事件反复滚动）
  int? _lastSyncedHymnId;

  @override
  void initState() {
    super.initState();
    // 监听播放状态：切歌（loading/playing）时刷新高亮 + 联动子类滚动高亮行
    _statusSub = widget.audio.statusStream.listen((_) {
      final hymn = widget.audio.currentHymn;
      if (hymn == null) return;
      final isNew = hymn.id != _lastSyncedHymnId;
      _lastSyncedHymnId = hymn.id;
      if (!mounted) return;
      if (isNew) {
        // 先重建列表让新高亮行生效，再滚动到可视区域
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) syncWithPlayback();
        });
      }
    });
    final a = widget.anchor;
    if (a != null) {
      // 首次挂载：延后一帧等自身视图就绪后恢复
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.anchor != null) restoreSaved(a);
      });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(P oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = widget.anchor;
    if (a != null && a != oldWidget.anchor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) restoreSaved(a);
      });
    }
  }

  /// 供子类使用的常用简写
  AudioService get audio => widget.audio;
  SqliteRepository get repo => widget.repo;

  Hymn? get currentHymn => audio.currentHymn;
  List<Hymn> get currentPlaylist => audio.playlist;
  int get currentIndex => audio.currentIndex;

  /// 子类实现的视图内容
  @override
  Widget build(BuildContext context);

  /// 恢复锚点状态（滚动/展开/分页），子类按各自逻辑实现
  void restoreSaved(AppState anchor);

  /// 切歌联动：当前播放歌曲变化后，将高亮行滚动到自身列表的可视区域内。
  /// 各子类判断当前歌曲是否属于自身列表，再调用 [scrollCurrentIntoView]。
  void syncWithPlayback();

  /// ===== 抽象接口：诗歌行渲染 =====
  ///
  /// 各面板的行样式/交互可不同，由子类实现。
  /// 实现中点击行时应调用 [playHymn]，并传入面板自身的播放来源：
  /// - 默认歌单 → 传当前二级目录到 `sourceSubcategory`
  /// - 个人歌单 → 传当前歌单名到 `sourcePlaylistName`
  /// - 诗歌列表 → 不传来源（null = 全部诗歌）
  Widget buildHymnTile(Hymn hymn, int index, List<Hymn> contextList);

  /// ===== 公共：点击播放（设置播放上下文 + 播放 + 通知上层保存） =====
  ///
  /// [sourceSubcategory] / [sourcePlaylistName]：播放来源（见 [buildHymnTile]）。
  void playHymn(
    Hymn hymn,
    int index,
    List<Hymn> contextList, {
    String? sourceSubcategory,
    String? sourcePlaylistName,
  }) {
    audio.setPlaylist(contextList, startIndex: index);
    audio.playHymn(hymn, index: index, version: audio.currentAudioVersion);
    widget.onPlayback(PlaybackEvent(
      contextList: contextList,
      hymn: hymn,
      index: index,
      sourceSubcategory: sourceSubcategory,
      sourcePlaylistName: sourcePlaylistName,
    ));
    if (mounted) setState(() {});
  }

  /// ===== 共用：滚动定位工具（jumpTo + 校验偏移） =====
  /// 返回 true 表示滚动到位；false 表示列表未挂载（可重试）。
  bool scrollToCurrent(ScrollController ctrl, int index) {
    if (!ctrl.hasClients) return false;
    final target = (index * itemHeight)
        .clamp(0.0, ctrl.position.maxScrollExtent)
        .toDouble();
    ctrl.jumpTo(target);
    return (ctrl.offset - target).abs() <= 2.0;
  }

  /// 切歌联动滚动：将 [index] 行滚动到可视区域，且避开顶部固定栏
  /// （搜索框/标题行等，高度 [headerHeight]），不遮挡高亮行。
  /// 行已在可视区域内时不动，避免无谓跳动。
  void scrollCurrentIntoView(
    ScrollController ctrl,
    int index, {
    double headerHeight = defaultHeaderHeight,
  }) {
    if (!ctrl.hasClients) return;
    final rowTop = index * itemHeight;
    final rowBottom = rowTop + itemHeight;
    final offset = ctrl.offset;
    final viewport = ctrl.position.viewportDimension;
    // 可视区域 = [offset + headerHeight, offset + viewport)
    final visibleTop = offset + headerHeight;
    final visibleBottom = offset + viewport;
    if (rowTop < visibleTop || rowBottom > visibleBottom) {
      final target = (rowTop - headerHeight)
          .clamp(0.0, ctrl.position.maxScrollExtent)
          .toDouble();
      ctrl.jumpTo(target);
    }
  }
}
