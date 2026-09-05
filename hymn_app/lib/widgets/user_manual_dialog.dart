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

/// 键盘快捷键与滚轮操作说明
///
/// 键盘部分与 app.dart 全局快捷键实现保持一致；
/// 滚轮部分与 hymn_display.dart `_ScoreImageView`（谱面缩放/滚动分流）一致。
const List<({String action, String shortcut})> kShortcutList = [
  (action: '播放 / 暂停', shortcut: '空格键 或 Ctrl+P'),
  (action: '下一首', shortcut: 'Ctrl+→ 或 Alt+→'),
  (action: '上一首', shortcut: 'Ctrl+← 或 Alt+←'),
  (action: '音量增大', shortcut: 'Ctrl+↑'),
  (action: '音量减小', shortcut: 'Ctrl+↓'),
  (action: '静音 / 取消静音', shortcut: 'Ctrl+M'),
  (action: '打开用户手册', shortcut: 'F1'),
  (action: '关闭用户手册', shortcut: 'Esc'),
  (action: '谱面图片放大 / 缩小', shortcut: 'Ctrl+滚轮'),
  (action: '谱面图片上下滚动', shortcut: '滚轮'),
  (action: '浏览列表 / 歌词 / 诗歌源考', shortcut: '滚轮'),
];

/// 操作说明条目：text 为二级圆点项；当一条说明涵盖多种情况时，
/// 用 subs（三级短横项）按情况拆开逐条说明，避免一行混排
class GuideLine {
  final String text;
  final List<String> subs;
  const GuideLine(this.text, [this.subs = const []]);
}

/// 操作说明内容（按界面区域分小节、逐子项说明；不同情况分层拆开；无版本化措辞）
const List<({String title, List<GuideLine> lines})> _guideSections = [
  (
    title: '本手册的打开与关闭',
    lines: [
      GuideLine('打开（三种方式）：', [
        '点击标题栏右侧「？」按钮（最小化左侧）；',
        '在软件任意界面按 F1；',
        '每次启动软件时默认自动弹出。',
      ]),
      GuideLine('关闭（三种方式）：', [
        '按 Esc 键；',
        '点击弹窗右上角 ✕；',
        '点击弹窗外任意位置。',
      ]),
      GuideLine('弹窗底部的「启动时显示本手册」勾选框可控制每次启动是否自动弹出。'),
    ],
  ),
  (
    title: '标题栏与窗口',
    lines: [
      GuideLine('标题栏空白处操作：', [
        '按住拖动：移动窗口；',
        '双击：最大化 / 还原。',
      ]),
      GuideLine('右侧按钮组从左至右：「调色盘」配色、「大小写T」字号、「？」用户手册、最小化、最大化·还原、关闭。'),
      GuideLine('改变窗口大小时界面内容整体等比缩放，不变形不裁切。'),
    ],
  ),
  (
    title: '字号',
    lines: [
      GuideLine('「大小写T」按钮（位于调色盘与手册之间）提供 默认 / 中号 / 大号 / 最大 四档，当前档带 ✓。'),
      GuideLine('全界面控件与文字（含弹窗）等比例放大，点击即时生效。'),
      GuideLine('歌词区显示：', [
        '按显示区域自动铺满；',
        '放大后歌词超出显示区时，可滚动阅读。',
      ]),
      GuideLine('字号选择自动记忆，重启保持。'),
    ],
  ),
  (
    title: '配色',
    lines: [
      GuideLine('「调色盘」按钮提供五套界面配色：晨光蓝 · 经典 / 暖阳金 · 圣堂 / 静谧绿 · 草木 / 典雅紫 · 暮云 / 暗夜墨 · 深色。'),
      GuideLine('标题栏、顶栏、侧栏、歌词区等各分区底色自动配套为同色相层次，点击即时生效。'),
      GuideLine('配色选择自动记忆，重启保持。'),
    ],
  ),
  (
    title: '顶栏',
    lines: [
      GuideLine('两端箭头按钮：', [
        '左端：展开 / 收起左侧栏；',
        '右端：展开 / 收起右侧栏。',
      ]),
      GuideLine('中央显示当前选中歌曲（第 N 首《标题》），切歌即时刷新。'),
    ],
  ),
  (
    title: '左侧栏（三个栏目）',
    lines: [
      GuideLine('「诗歌列表」：按编号分页浏览全部 474 首诗歌，每页 35 首，底部可翻页。'),
      GuideLine('「默认歌单」：按分类目录两级展开浏览，点击诗歌播放。'),
      GuideLine('「个人歌单」：可新建 / 编辑 / 删除自己的歌单，点歌单名展示并整单播放。'),
      GuideLine('正在播放的诗歌在列表中高亮，切歌时自动滚动跟随。'),
    ],
  ),
  (
    title: '搜索（诗歌列表栏目）',
    lines: [
      GuideLine('输入纯数字（编号搜索）：', [
        '回车：按编号翻页定位并高亮该诗歌（不自动播放）；',
        '再按一次回车：开始播放，播完搜索框自动清空。',
      ]),
      GuideLine('输入中文回车：同时模糊搜索歌名与歌词，有命中时弹出统一结果列表（编号 / 诗歌名称 / 歌词三列）。'),
      GuideLine('结果列表中的命中显示：', [
        '歌名命中：名称中关键字红色加粗，歌词列默认显示第一节；',
        '歌词命中：歌词列显示第一个命中的歌词节（从关键字所在行开始），节内关键字蓝色加粗；',
        '同一首歌两种命中都有：同一行红、蓝并存显示。',
      ]),
      GuideLine('弹窗中操作：', [
        '单击行：选中；',
        '双击行：关闭弹窗、在左栏定位该诗歌并播放（回车不会直接播放）。',
      ]),
      GuideLine('无命中时：不弹窗，列表显示「未找到匹配的诗歌」。'),
      GuideLine('点搜索框清除（×）：回到当前播放定位行。'),
    ],
  ),
  (
    title: '音频版本',
    lines: [
      GuideLine('主内容区顶部「钢琴版｜人声版」按钮切换播放版本。'),
      GuideLine('某首诗歌有多个（多于一个）人声版本时，播放条右侧出现 👥 按钮可选择。'),
      GuideLine('版本记忆规则：', [
        '版本选择自动记忆，重启保持；',
        '某首没有所选版本时：临时改用另一版本播放，记忆不变。',
      ]),
    ],
  ),
  (
    title: '显示模式',
    lines: [
      GuideLine('「歌词」「简谱」「五线谱」三个按钮切换主内容区显示内容。'),
      GuideLine('简谱 / 五线谱图片查看：', [
        'Ctrl+滚轮：缩放图片——宽度从初始大小逐渐变大，最宽铺满歌词区，高度同步变高；',
        '滚轮：上下滚动查看图片内容；',
        '切换诗歌后：自动复位为初始视图。',
      ]),
    ],
  ),
  (
    title: '播放条与音量',
    lines: [
      GuideLine('进度条可拖动跳转，两端显示播放位置与总时长。'),
      GuideLine('控制键：上一首 / 播放·暂停 / 下一首，列表内循环切换。'),
      GuideLine('左侧音量控件：', [
        '点击图标：静音或取消；',
        '拖动滑条：调节音量；',
        '右侧数字：当前音量百分比。',
      ]),
      GuideLine('音量滑条与 Windows 系统音量同步（滑条即系统音量的镜像，与系统播放器听感一致）。'),
    ],
  ),
  (
    title: '右侧栏（诗歌源考）',
    lines: [
      GuideLine('展开 / 收起：顶栏右端箭头按钮。'),
      GuideLine('显示当前诗歌的源考资料（诗歌背景、词曲作者信息等）。'),
      GuideLine('内容超过一屏时：可滚动阅读。'),
    ],
  ),
  (
    title: '底部状态栏',
    lines: [
      GuideLine('显示当前诗歌的编号、歌名、作词、作曲。'),
      GuideLine('显示播放进度（播放位置 / 总时长 · 百分比）。'),
    ],
  ),
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
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '支持通用媒体键（播放 / 暂停、上一首、下一首、音量）直接控制。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '输入框获得焦点时，空格仍用于输入文字（不触发播放/暂停）。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '滚轮操作仅在鼠标指针位于对应区域（谱面图片、列表、歌词、源考）时生效。',
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

  /// 操作说明：小节标题（▶）→ 二级圆点项（•）→ 三级短横项（–，按情况拆开）
  Widget _buildGuideList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in _guideSections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 小节标题（主色三角 + 加粗）
                Row(
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 2),
                    Text(
                      section.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                for (final line in section.lines)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 二级子项（圆点 + 缩进）
                      Padding(
                        padding: const EdgeInsets.only(left: 14, top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 7, right: 6),
                              child: Icon(Icons.circle,
                                  size: 4, color: AppColors.textTertiary),
                            ),
                            Expanded(
                              child: Text(
                                line.text,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 三级子项（短横 + 更深缩进）：不同情况逐条拆开说明
                      for (final sub in line.subs)
                        Padding(
                          padding: const EdgeInsets.only(left: 34, top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 9, right: 6),
                                child: Container(
                                  width: 7,
                                  height: 1.5,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  sub,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
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
              _Cell('快捷键 / 滚轮', bold: true),
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
