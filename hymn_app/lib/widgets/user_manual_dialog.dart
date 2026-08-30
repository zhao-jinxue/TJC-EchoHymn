import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';

/// 全局快捷键说明（与 app.dart 全局快捷键实现保持一致）
const List<({String action, String shortcut})> kShortcutList = [
  (action: '播放 / 暂停', shortcut: '空格键 或 Ctrl+P'),
  (action: '下一首', shortcut: 'Ctrl+→ 或 Alt+→'),
  (action: '上一首', shortcut: 'Ctrl+← 或 Alt+←'),
  (action: '音量增大', shortcut: 'Ctrl+↑'),
  (action: '音量减小', shortcut: 'Ctrl+↓'),
  (action: '静音 / 取消静音', shortcut: 'Ctrl+M'),
  (action: '打开用户手册', shortcut: 'F1'),
];

/// 用户手册弹窗（顶栏右上角「？」按钮 / F1 打开）
///
/// 包含三部分：软件介绍 / 操作说明 / 快捷键说明。Esc 或右上角 ✕ 关闭。
class UserManualDialog extends StatelessWidget {
  const UserManualDialog({super.key});

  /// 是否已打开（防止 F1 / ？重复点击叠加多个手册弹窗，H11）
  static bool _isOpen = false;

  /// 弹出用户手册（已打开时忽略，避免叠加）
  static Future<void> show(BuildContext context) {
    if (_isOpen) return Future.value();
    _isOpen = true;
    try {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const UserManualDialog(),
      ).whenComplete(() => _isOpen = false);
    } catch (_) {
      // 弹窗打开异常时复位标志，避免卡死无法再次打开
      _isOpen = false;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: AppColors.cardBg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // 按 Esc 关闭手册
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- 标题栏 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '用户手册',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: AppColors.textSecondary),
                      tooltip: '关闭（Esc）',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.divider),
              // ---- 手册内容 ----
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('软件介绍'),
                      const _SectionBody(
                        'EchoHymn · 聆听赞美诗是一款本地运行的赞美诗歌应用：'
                        '收录《赞美诗歌》（增订本）474 首，可离线播放钢琴版 / 人声版音频，'
                        '查看歌词、简谱与五线谱。内置默认歌单分类与个人歌单管理，'
                        '自动记忆上次播放的诗歌、版本与界面状态（状态存于 exe 同级 state.json，便携可迁移）。',
                      ),
                      const SizedBox(height: 16),
                      const _SectionTitle('操作说明'),
                      _buildGuideList(context),
                      const SizedBox(height: 16),
                      const _SectionTitle('快捷键说明'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '支持通用媒体键（播放 / 暂停、上一首、下一首、音量）直接控制；'
                          '输入框获得焦点时，空格仍用于输入文字。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      _buildShortcutTable(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideList(BuildContext context) {
    const items = <String>[
      '标题栏最右侧（关闭按钮左侧）新增「调色盘」按钮：一键切换 5 套界面配色（晨光蓝 · 经典 / 暖阳金 · 圣堂 / 静谧绿 · 草木 / 典雅紫 · 暮云 / 暗夜墨 · 深色），各分区以极浅同色相底色区分，选择自动记忆，重启保持。',
      '顶栏：左侧「诗歌列表 / 歌单」箭头按钮展开或收起左栏；右侧「源考」箭头按钮展开或收起右栏。标题栏空白处按住可拖动窗口，双击可最大化 / 还原。',
      '左侧栏三个栏目：「诗歌列表」按编号分页浏览全部诗歌；「默认歌单」按分类目录浏览；「个人歌单」管理自己创建的歌单（可新建 / 编辑 / 删除）。',
      '搜索定位：输入编号即时定位并翻页高亮；输入标题显示匹配列表；在搜索框按回车可播放定位到的诗歌。',
      '音频版本：主内容区顶部「钢琴版｜人声版」切换音频；某首诗歌有多个（>1）人声版本时，播放条右侧出现 👥 按钮可切换。',
      '显示模式：「歌词」「简谱」「五线谱」切换主内容区显示内容（简谱 / 五线谱可缩放拖动）。',
      '播放控制：播放条上的 上一首 / 播放·暂停 / 下一首 与进度条（可拖动跳转）；播放条左侧有**音量调节**（图标点击静音 / 滑条拖动调节 / 右侧显示音量百分比），**与系统音量双向同步**（调应用音量会同步改动 Windows 系统音量，反之系统音量变化也会实时跟随）；右侧栏展示当前诗歌的源考资料。',
      '底部状态栏：显示当前诗歌编号、歌名、作词、作曲与播放进度。',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child:
                      Icon(Icons.circle, size: 6, color: AppColors.textTertiary),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShortcutTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1.6)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: AppColors.sidebarBg),
            children: const [
              _Cell('功能', bold: true),
              _Cell('快捷键', bold: true),
            ],
          ),
          for (final s in kShortcutList) ...[
            TableRow(
              children: [
                _Cell(s.action),
                _Cell(s.shortcut),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 章节标题
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// 章节正文
class _SectionBody extends StatelessWidget {
  final String text;
  const _SectionBody(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// 快捷键表格单元格
class _Cell extends StatelessWidget {
  final String text;
  final bool bold;
  const _Cell(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: bold ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
