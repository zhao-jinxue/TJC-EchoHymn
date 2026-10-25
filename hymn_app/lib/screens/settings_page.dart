import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../theme/app_fonts.dart';
import '../theme/app_palette.dart';
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
                  _buildPreviewSection(context),
                  _buildPlaybackSection(),
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
              for (final l in FontSizeLevel.values)
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
                    UserManualDialog.show(context);
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

