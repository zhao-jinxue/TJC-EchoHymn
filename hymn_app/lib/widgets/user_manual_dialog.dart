import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/app_state_service.dart';
import '../services/log_service.dart';

/// 用户手册显示偏好（全局单例，与 ThemeController/FontScaleController 同模式）
///
/// 控制"每次启动自动弹出用户手册"：取消勾选后启动不再弹出，
/// 之后可随时经标题栏「？」按钮或 F1 打开手册并重新勾选恢复。
/// 值持久化到 state.json `manualOnStart`（经 AppStateService.shared 单键更新，
/// 与 HomeScreen 的全量保存共用同一串行写队列）。
class ManualPrefs {
  ManualPrefs._();
  static final ManualPrefs instance = ManualPrefs._();

  final ValueNotifier<bool> showOnStartNotifier = ValueNotifier<bool>(true);

  bool get showOnStart => showOnStartNotifier.value;

  /// 启动恢复：从 state.json 读初始值（HomeScreen._init 调用）
  void restoreFrom(bool value) => showOnStartNotifier.value = value;

  /// 勾选框切换：即时更新内存值 + 持久化单键 + 记日志
  void set(bool value) {
    showOnStartNotifier.value = value;
    LogService.instance.info(
      LogTag.action,
      value ? '用户手册：恢复启动时自动弹出' : '用户手册：取消启动时自动弹出',
    );
    AppStateService.shared.updateManualOnStart(value);
  }
}

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

/// 用户手册弹窗（标题栏「？」按钮 / F1 / 启动自动弹出）
///
/// 内容四部分：软件介绍 / 操作说明 / 快捷键说明 / 启动显示设置。
/// 底部提供「启动时显示本手册」勾选框（ManualPrefs 持久化）。
/// Esc / 右上角 ✕ / 点击遮罩关闭；重复触发不叠加。
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
              // ---- 底部固定区：启动时显示本手册开关（ManualPrefs 持久化） ----
              Divider(height: 1, color: AppColors.divider),
              _buildStartupOption(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideList(BuildContext context) {
    const items = <String>[
      '本手册的打开与关闭：点击标题栏右侧「？」按钮，或在软件任意界面按 F1；关闭可按 Esc、点右上角 ✕ 或点弹窗外任意处。每次启动软件会自动弹出本手册，可在弹窗底部勾选/取消「启动时显示本手册」来控制。',
      '标题栏：空白处按住拖动可移动窗口，双击最大化 / 还原；右侧按钮组从左至右依次为「A」字号、「调色盘」配色、「？」用户手册、最小化、最大化·还原、关闭。',
      '字号：「A」按钮提供默认 / 中号 / 大号 / 最大四档，全界面控件与文字等比例放大、即时生效；选择自动记忆，重启保持。歌词区按显示区域自动铺满，放大后歌词超出显示区时可滚动阅读。',
      '配色：「调色盘」按钮提供五套界面配色（晨光蓝 · 经典 / 暖阳金 · 圣堂 / 静谧绿 · 草木 / 典雅紫 · 暮云 / 暗夜墨 · 深色），各分区底色自动配套、即时生效；选择自动记忆，重启保持。',
      '顶栏：左端箭头按钮展开 / 收起左侧栏，右端箭头按钮展开 / 收起右侧栏；中央显示当前选中歌曲（第 N 首《标题》）。',
      '左侧栏三个栏目：「诗歌列表」按编号分页浏览全部诗歌；「默认歌单」按分类目录浏览；「个人歌单」管理自己创建的歌单（可新建 / 编辑 / 删除，点歌单名播放整单）。',
      '搜索：输入编号即时定位并翻页高亮；输入标题显示匹配列表，点击播放；在搜索框按回车播放定位到的诗歌。',
      '音频版本：主内容区顶部「钢琴版｜人声版」切换音频版本；某首诗歌有多个（>1）人声版本时，播放条右侧出现 👥 按钮可选择切换。',
      '显示模式：「歌词」「简谱」「五线谱」切换主内容区显示内容（简谱 / 五线谱可缩放拖动查看）。',
      '播放条：进度条可拖动跳转，两端显示播放位置与总时长；上一首 / 播放·暂停 / 下一首 三个控制键；左侧音量控件——点击图标静音或取消、拖动滑条调节、右侧显示音量百分比。音量与 Windows 系统音量双向同步：调应用音量会同步系统音量，系统音量变化（如媒体键）也实时跟随。',
      '右侧栏：显示当前诗歌的源考资料（诗歌背景、词曲作者信息等），内容超一屏可滚动。',
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
                  child: Icon(Icons.circle,
                      size: 6, color: AppColors.textTertiary),
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

  /// 弹窗底部固定区：「启动时显示本手册」勾选框
  ///
  /// 勾选（默认）= 每次启动自动弹出；取消 = 启动不弹出。
  /// 两种状态都可在此处反向切换（从「？」/F1 打开手册即可再勾回）。
  Widget _buildStartupOption() {
    return ValueListenableBuilder<bool>(
      valueListenable: ManualPrefs.instance.showOnStartNotifier,
      builder: (context, showOnStart, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ManualPrefs.instance.set(!showOnStart),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 28,
                child: Checkbox(
                  value: showOnStart,
                  visualDensity: VisualDensity.compact,
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  onChanged: (v) => ManualPrefs.instance.set(v ?? true),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '启动时显示本手册',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '取消后启动不再自动弹出；可随时经「？」按钮或 F1 打开',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
