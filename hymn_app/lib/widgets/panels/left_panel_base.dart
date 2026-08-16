import 'package:flutter/material.dart';

import '../../models/hymn.dart';
import '../../services/audio_service.dart';
import '../../services/app_state_service.dart';
import '../../services/chinese_convert_service.dart';
import '../../services/sqlite_repository.dart';
import '../../app.dart';

/// 播放回调：面板内点击播放后通知 HomeScreen 保存状态
class PlaybackEvent {
  final List<Hymn> contextList;
  final Hymn hymn;
  final int index;
  const PlaybackEvent({
    required this.contextList,
    required this.hymn,
    required this.index,
  });
}

/// 左侧栏面板抽象基类（三个栏目共用契约）
///
/// 基类持有公共依赖与公共方法：
/// - `hymnTile`：诗歌行渲染（共用）
/// - `playHymn`：点击播放（共用，含播放上下文设置 + 通知上层保存）
/// - `scrollToCurrent`：滚动定位工具（共用）
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

  @override
  void initState() {
    super.initState();
    final a = widget.anchor;
    if (a != null) {
      // 首次挂载：延后一帧等自身视图就绪后恢复
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.anchor != null) restoreSaved(a);
      });
    }
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

  /// ===== 共用：诗歌行渲染 =====
  Widget hymnTile(Hymn hymn, int index, List<Hymn> contextList) {
    final isCurrent = currentHymn?.id == hymn.id;
    return Material(
      color: isCurrent ? AppColors.selectedBg : AppColors.cardBg,
      child: InkWell(
        onTap: () => playHymn(hymn, index, contextList),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: isCurrent ? AppColors.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  hymn.hymnNumber,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        isCurrent ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  ChineseConvertService.instance.toSimplified(hymn.title),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ===== 共用：点击播放（设置播放上下文 + 播放 + 通知上层保存） =====
  void playHymn(Hymn hymn, int index, List<Hymn> contextList) {
    audio.setPlaylist(contextList, startIndex: index);
    audio.playHymn(hymn, index: index, version: audio.currentAudioVersion);
    widget.onPlayback(PlaybackEvent(
      contextList: contextList,
      hymn: hymn,
      index: index,
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
}
