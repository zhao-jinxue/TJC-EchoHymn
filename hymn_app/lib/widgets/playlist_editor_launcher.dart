import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../services/log_service.dart';
import '../services/sqlite_repository.dart';
import 'playlist_dialog.dart';

/// 歌单编辑器的统一入口（`ANDROID_PLAN §3.1.9`）
///
/// **手机走全屏页**（`CreatePlaylistDialog(fullscreen: true)` 经路由压栈），
/// 桌面仍走原 520×420 弹窗 —— 两者**共用同一份编辑逻辑**，不分叉。
///
/// 返回值语义与 `showDialog` 一致：`'create'` / `'save'` / `'delete'` / `null`（取消）。
Future<String?> showPlaylistEditor(
  BuildContext context,
  SqliteRepository repo, {
  Playlist? existing,
}) {
  final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;
  if (!isPhone) {
    return showDialog<String>(
      context: context,
      builder: (_) => CreatePlaylistDialog(repo: repo, existing: existing),
    );
  }
  LogService.instance.info(
    LogTag.action,
    existing == null ? '打开歌单编辑器（全屏·新建）' : '打开歌单编辑器（全屏·修改）',
  );
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => CreatePlaylistDialog(
        repo: repo,
        existing: existing,
        fullscreen: true,
      ),
    ),
  );
}
