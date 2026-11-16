import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../app_feature.dart';
import '../models/hymn.dart';
import '../platform/media_import.dart';
import '../platform/pack_import.dart';
import '../services/app_paths.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../theme/app_fonts.dart';
import '../theme/app_palette.dart';
import '../theme/score_display_prefs.dart';
import '../widgets/manual_launcher.dart';
import '../widgets/user_manual_dialog.dart';

/// 设置页（`ANDROID_PLAN §3.1.7` / 确认单 3.1.7）
///
/// 决策：Android 把**配色 / 字号 / 播放选项 / 用户手册**集中到**一个全屏设置页**
/// （顶栏 `⋮` → 设置）。**点选即生效，没有"保存"按钮** —— 与 Windows 标题栏
/// 调色盘 / 字号按钮的即时生效语义一致；持久化由调用方写回 `state.json`。
///
/// 分组：外观（配色 / 字号）· 实时预览 · 播放 · 帮助 · 关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.previewHymn,
    required this.audioVersion,
    required this.onAudioVersionChanged,
    required this.onSaveState,
  });

  /// 预览用的诗歌（当前播放/选中；null 时显示占位文案）
  final Hymn? previewHymn;

  /// 当前默认音频版本（`鋼琴版` / `人聲版`）
  final String audioVersion;

  final ValueChanged<String> onAudioVersionChanged;

  /// 让调用方把当前状态写回 `state.json`（配色 / 字号 / 版本变了就落盘）
  final VoidCallback onSaveState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lyricsBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _buildAppearanceSection(),
                  _buildDisplaySection(),
                  _buildPreviewSection(context),
                  // 无音频版（lite）没有播放能力 → 不显示「播放」分组（§3.1.15）
                  if (kHasAudio) _buildPlaybackSection(),
                  // 素材导入（SAF；仅 Android 且有音频能力的变体才有意义，
                  // 但 lite 也需要扫描图 → 全部 Android 变体都显示）
                  if (Platform.isAndroid) _buildImportSection(context),
                  _buildHelpSection(context),
                  _buildAboutSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 顶栏 56：← / 设置 / 完成 ----------
  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            iconSize: 24,
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(
              '完成',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ---------- 分组标题（40dp，13sp 二级色）----------
  Widget _sectionTitle(String title) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: AppColors.divider),
      );

  // ---------- 外观（配色 / 字号）----------
  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('外观'),
        _rowLabel('配色'),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kThemes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = kThemes[i];
              return _chip(
                label: p.name,
                active: ThemeController.instance.current.id == p.id,
                onTap: () {
                  ThemeController.instance.switchTo(p);
                  LogService.instance
                      .info(LogTag.action, '设置页切换配色：${p.name}');
                  onSaveState();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _rowLabel('字号'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 手机只显示 3 档（标准/大/特大；2026-10-25 用户要求档间差异温和）
              for (final l in FontSizeLevel.values.take(3))
                _chip(
                  label: _fontLabel(l),
                  active: FontScaleController.instance.current.id == l.id,
                  onTap: () {
                    FontScaleController.instance.switchTo(l);
                    LogService.instance
                        .info(LogTag.action, '设置页切换字号：${_fontLabel(l)}');
                    onSaveState();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _divider(),
      ],
    );
  }

  /// 字号档位文案（§3.1.7：标准 / 大 / 特大 / 最大）
  String _fontLabel(FontSizeLevel l) => switch (l) {
        FontSizeLevel.normal => '标准',
        FontSizeLevel.medium => '大',
        FontSizeLevel.large => '特大',
        FontSizeLevel.xlarge => '最大',
      };

  Widget _rowLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      );

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? AppColors.primary : AppColors.controlBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? Colors.transparent : AppColors.controlBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
  // ---------- 显示（深色下谱面，§3.10）----------
  Widget _buildDisplaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('显示'),
        _rowLabel('深色下谱面显示'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final m in ScoreDisplayPrefs.modes)
                _chip(
                  label: ScoreDisplayPrefs.labelOf(m),
                  active: ScoreDisplayPrefs.instance.mode == m,
                  onTap: () {
                    ScoreDisplayPrefs.instance.set(m);
                    LogService.instance.info(
                      LogTag.action,
                      '设置页切换谱面显示：${ScoreDisplayPrefs.labelOf(m)}',
                    );
                    onSaveState();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '仅深色配色下生效：暗化 = 原色 + 20% 黑遮罩（默认）；反色为实验项',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: 16),
        _divider(),
      ],
    );
  }

  // ---------- 实时预览（200dp 卡片；按 0.55 缩放，用真实配色/字号令牌）----------
  Widget _buildPreviewSection(BuildContext context) {
    final hymn = previewHymn;
    final scale = 0.55 * AppFonts.scale;
    final cardW = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('实时预览（改动立即生效）'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 200,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.playBarBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.controlBorder),
            ),
            child: hymn == null
                ? Center(
                    child: Text(
                      '暂无预览（先选一首诗歌）',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textTertiary),
                    ),
                  )
                : ClipRect(
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: cardW / scale,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '第 ${hymn.hymnNumber} 首《'
                                '${ChineseConvertService.instance.toSimplified(hymn.title)}》',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                ChineseConvertService.instance.toSimplified(
                                  hymn.verses.isNotEmpty
                                      ? hymn.verses.first
                                      : '',
                                ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.8,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '预览按 0.55 缩放渲染，使用当前配色与字号令牌（非另画一套假预览）',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: 16),
        _divider(),
      ],
    );
  }

  // ---------- 播放 ----------
  Widget _buildPlaybackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('播放'),
        _rowLabel('默认音频版本'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final v in const ['鋼琴版', '人聲版'])
                _chip(
                  label: v,
                  active: audioVersion == v,
                  onTap: () {
                    onAudioVersionChanged(v);
                    LogService.instance
                        .info(LogTag.action, '设置页切换默认音频版本：$v');
                    onSaveState();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _switchTile(
          title: '后台播放 / 媒体通知',
          subtitle: '试用版暂未开启（计划 M4 系统集成）',
          value: false,
          onChanged: null,
        ),
        _switchTile(
          title: '屏幕常亮（歌词 / 谱面页）',
          subtitle: '试用版暂未开启（计划 M4 系统集成）',
          value: false,
          onChanged: null,
        ),
        const SizedBox(height: 8),
        _divider(),
      ],
    );
  }

  Widget _switchTile({
    required String title,
    String? subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        enabled ? AppColors.textPrimary : AppColors.textTertiary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // ---------- 素材导入（SAF，§7.5）----------
  Widget _buildImportSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(kHasAudio ? '素材' : '素材（扫描图）'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            kHasAudio
                ? '包内只有 12 首样本音频。可把完整素材目录（Hymn_Downloads）拷到手机后从这里导入；'
                    '导入会**复制**到应用私有目录（约 2.9 GB，需数分钟，期间请保持应用在前台）。'
                : '包内只有 12 首的扫描图。可把完整素材目录（Hymn_Downloads）拷到手机后从这里导入，'
                    '补齐全部诗歌的简谱 / 五线谱扫描图（约 0.5 GB）。'
                    '**本版本没有播放功能**，导入音频也不会播放。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '导入完整素材',
                    style:
                        TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _startImport(context),
                  child: const Text('选择目录'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle('数据导入（压缩包）'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '选择安装包附带的 zip：扫描图 / 人声 / 钢琴。只导入符合既有目录与文件名规则的文件'
            '（规则外一律丢弃、不写入存储），同名文件直接覆盖。导入完成后请重启应用以更新界面。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: () => _startPackImport(context, 'scores', '扫描图'),
                child: const Text('导入扫描图'),
              ),
              OutlinedButton(
                onPressed: () => _startPackImport(context, 'vocal', '人声音频'),
                child: const Text('导入人声'),
              ),
              OutlinedButton(
                onPressed: () => _startPackImport(context, 'piano', '钢琴音频'),
                child: const Text('导入钢琴'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _divider(),
      ],
    );
  }

  /// 选择 zip → 流式导入（规则外丢弃）→ 提示重启
  Future<void> _startPackImport(
      BuildContext context, String kind, String label) async {
    final target = AppPaths.dataRoot;
    if (target == null || target.isEmpty) {
      LogService.instance.warning(LogTag.action, '数据包导入：数据根目录未就绪');
      return;
    }
    final uri = await PackImport.pickZip(kind);
    if (uri == null) {
      LogService.instance.info(LogTag.action, '数据包导入：用户取消（$kind）');
      return;
    }
    LogService.instance
        .info(LogTag.action, '数据包导入开始：$label', detail: 'kind=$kind');
    StreamSubscription<PackImportResult>? sub;
    sub = PackImport.doneStream.listen((r) async {
      await sub?.cancel();
      LogService.instance.info(
        LogTag.action,
        '数据包导入结束：$label',
        detail: '导入 ${r.accepted} / 规则外丢弃 ${r.rejected} / 失败 ${r.failed}'
            '${r.error == null ? '' : ' / 错误 ${r.error}'}',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok
            ? '$label 导入完成：${r.accepted} 个（规则外丢弃 ${r.rejected}）；请重启应用以更新界面'
            : '$label 导入失败：${r.error ?? '${r.failed} 个文件写入失败'}'),
      ));
    });
    await PackImport.startImport(uri: uri, kind: kind, targetRoot: target);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PackProgressDialog(),
    );
  }

  /// 选目录 → 导入 → 进度对话框（进度/结束走 `MediaImport` 的流）
  Future<void> _startImport(BuildContext context) async {
    final target = AppPaths.dataRoot;
    if (target == null || target.isEmpty) {
      LogService.instance.warning(LogTag.action, '素材导入：数据根目录未就绪');
      return;
    }
    final uri = await MediaImport.pickDirectory();
    if (uri == null) {
      LogService.instance.info(LogTag.action, '素材导入：用户取消选择目录');
      return;
    }
    final started =
        await MediaImport.startImport(treeUri: uri, targetRoot: target);
    if (!started || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ImportProgressDialog(),
    );
  }

  // ---------- 帮助 ----------
  Widget _buildHelpSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('帮助'),
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '用户手册',
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    LogService.instance.info(LogTag.action, '设置页打开用户手册');
                    showManualPage(context);
                  },
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: ManualPrefs.instance.showOnStartNotifier,
          builder: (context, on, _) => SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '启动时显示手册',
                      style:
                          TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ),
                  Switch(
                    value: on,
                    onChanged: (v) {
                      ManualPrefs.instance.set(v);
                      onSaveState();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _divider(),
      ],
    );
  }

  // ---------- 关于 ----------
  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('关于'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EchoHymn · 聆听赞美诗   v1.8.5（build 1）',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '数据来源与致谢：《生命诗歌》诗歌数据与音频；简谱/五线谱扫描图与网格'
                '由第三方 TJC APK 逆向复原，仅用于个人学习与敬拜。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}


/// 素材导入进度对话框（SAF 复制过程）
///
/// 监听 `MediaImport.progressStream` / `doneStream`：每 20 个文件刷新一次；
/// 完成后自动关闭并提示结果（**需重启应用**才会重新扫描素材）。
class _ImportProgressDialog extends StatefulWidget {
  const _ImportProgressDialog();

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  int _copied = 0;
  int _failed = 0;
  StreamSubscription<MediaImportProgress>? _p;
  StreamSubscription<MediaImportResult>? _d;

  @override
  void initState() {
    super.initState();
    _p = MediaImport.progressStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _copied = e.copied;
        _failed = e.failed;
      });
    });
    _d = MediaImport.doneStream.listen((e) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
      LogService.instance.info(
        LogTag.action,
        '素材导入结束',
        detail: '成功 ${e.copied} / 失败 ${e.failed} / 错误 ${e.error ?? '无'}',
      );
      final msg = e.success
          ? '素材导入完成：${e.copied} 个文件（重启应用后生效）'
          : '导入中断：${e.error}（已完成 ${e.copied}）';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  @override
  void dispose() {
    _p?.cancel();
    _d?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在导入素材'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text('已复制 $_copied 个文件${_failed > 0 ? '（失败 $_failed）' : ''}'),
          const SizedBox(height: 6),
          Text(
            '约 2.9 GB，请保持应用在前台',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
      actions: const [],
    );
  }
}

/// 数据包（zip）导入进度：`packDone` 到达后自动关闭
class _PackProgressDialog extends StatefulWidget {
  const _PackProgressDialog();

  @override
  State<_PackProgressDialog> createState() => _PackProgressDialogState();
}

class _PackProgressDialogState extends State<_PackProgressDialog> {
  StreamSubscription<PackImportResult>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PackImport.doneStream.listen((result) {
      if (!mounted) return;
      Navigator.of(context).maybePop(result);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在导入数据包'),
        content: StreamBuilder<PackImportProgress>(
          stream: PackImport.progressStream,
          builder: (context, snap) {
            final p = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  p == null
                      ? '正在读取压缩包…'
                      : '已处理 ${p.processed} 个（导入 ${p.accepted} / 规则外丢弃 ${p.rejected}）',
                ),
                const SizedBox(height: 6),
                Text(
                  '规则外的文件会被丢弃，不会写入存储。',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


