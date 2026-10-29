import '../app_feature.dart';
import 'user_manual_dialog.dart' show GuideLine;

/// **Android 版用户手册内容**（2026-10-28 新建）
///
/// 与 Windows 手册**完全分开**：手机没有键盘快捷键、没有窗口/托盘、没有右侧「诗歌源考」栏，
/// 多了「SAF 素材导入」「系统音量键」「长按/滑动」等移动端交互 —— 照搬桌面手册会误导用户。
///
/// 同时**按 4 个细分变体精确匹配**（用户明确要求）：
/// - `full`：钢琴 + 人声两种音频，按钮可循环切换
/// - `piano`：仅钢琴伴奏，**没有**版本切换按钮
/// - `vocal`：仅人声，**没有**版本切换按钮
/// - `lite`：**无内置音频**，只有歌词 + 简谱/五线谱扫描图，必须导入音频才能出声
List<({String title, List<GuideLine> lines})> androidManualSections() {
  final variant = kAudioVariant;
  return [
    _openClose(variant),
    _topBar(),
    _audio(variant),
    _displayMode(),
    _playerBar(),
    _leftPanel(),
    _settings(variant),
    _faq(variant),
  ];
}

/// 变体中文名（手册正文用）
String _variantName(AudioVariant v) => switch (v) {
      AudioVariant.full => '全量音频版',
      AudioVariant.piano => '钢琴版',
      AudioVariant.vocal => '人声版',
      AudioVariant.lite => '精简版（无音频）',
    };

({String title, List<GuideLine> lines}) _openClose(AudioVariant v) => (
      title: '本手册的打开与关闭',
      lines: [
        GuideLine('打开方式：', [
          '点击顶栏右侧「？/ 更多」里的「用户手册」；',
          '打开「设置 → 用户手册」；',
          '${_variantName(v)}：若开启「启动时显示手册」，每次进入都会自动弹出。',
        ]),
        const GuideLine('关闭方式：', [
          '点击右上角 ✕；',
          '点击弹窗外任意空白处；',
          'Android 返回手势（从屏幕左右边缘向内滑）也会关闭弹窗。',
        ]),
        const GuideLine('弹窗底部「启动时显示本手册」开关控制每次进入是否自动弹出，可随时恢复。'),
      ],
    );

({String title, List<GuideLine> lines}) _topBar() => (
      title: '顶栏与音频版本按钮',
      lines: [
        const GuideLine('左侧 ☰：打开诗歌列表 / 分类 / 我的歌单。'),
        const GuideLine('中间标题：显示「第 N 首《诗歌名》」。'),
        const GuideLine('右侧 🔍 搜索、⋮ 更多（用户手册、设置、关于）。'),
        const GuideLine('按钮栏分左右两组：', [
          '左边是**音频版本**，右边是**显示模式**（歌词 / 简谱 / 五线谱）—— 两组互不干扰；',
          'Android 版**没有「曲谱」模式**（桌面 Windows 版才有）。',
        ]),
      ],
    );

({String title, List<GuideLine> lines}) _audio(AudioVariant v) {
  switch (v) {
    case AudioVariant.full:
      return (
        title: '音频版本（全量音频版）',
        lines: [
          const GuideLine('顶栏左侧只有一个音频按钮，点一下**循环切换**该首的可用版本：', [
            '显示「钢琴」→ 当前播放钢琴伴奏；',
            '显示「人声」→ 当前播放人声演唱；',
            '若该首只有一个版本，点击后会提示「该首只有「XX」音频」，不会静默无反应。',
          ]),
          const GuideLine('当前版本会记入状态，下次启动自动沿用。'),
          const GuideLine('某首播不出声音时：说明本包内没有该首的音频文件，'
              '可在「设置 → 素材 → 选择目录」导入（见「设置与素材导入」一节）。'),
        ],
      );
    case AudioVariant.piano:
      return (
        title: '音频（钢琴版）',
        lines: [
          const GuideLine('本版本**只内置钢琴伴奏**，因此顶栏左侧**没有音频版本切换按钮**。'),
          const GuideLine('这也意味着：不会出现「切到人声却播不出来」的情况。'),
          const GuideLine('想听人声？请改用「人声版」或「全量音频版」安装包；'
              '也可以导入自己的人声音频（见「设置与素材导入」）。'),
        ],
      );
    case AudioVariant.vocal:
      return (
        title: '音频（人声版）',
        lines: [
          const GuideLine('本版本**只内置人声演唱**，因此顶栏左侧**没有音频版本切换按钮**。'),
          const GuideLine('适合跟唱练习：人声起唱、歌词同步，便于学唱。'),
          const GuideLine('想听纯伴奏？请改用「钢琴版」或「全量音频版」安装包，'
              '或导入自己的伴奏音频（见「设置与素材导入」）。'),
        ],
      );
    case AudioVariant.lite:
      return (
        title: '音频（精简版：无内置音频）',
        lines: [
          const GuideLine('**本版本不包含任何音频文件**，安装后点击播放不会有声音，这是设计如此。'),
          const GuideLine('精简版提供的是：474 首诗歌的**歌词**、**简谱扫描图**、**五线谱扫描图**、'
              '分类与歌单管理 —— 体积最小，适合只看谱/背词。'),
          const GuideLine('要让精简版出声，必须自己导入音频：', [
            '进入「设置 → 素材 → 选择目录」；',
            '选中存有音频的文件夹（文件名需匹配诗歌编号，如 001.mp3）；',
            '导入完成后回到列表点播放即可 —— 详见「设置与素材导入」。',
          ]),
        ],
      );
  }
}

({String title, List<GuideLine> lines}) _displayMode() => (
      title: '显示模式：歌词 / 简谱 / 五线谱',
      lines: [
        const GuideLine('顶栏右侧三个按钮切换主区内容：', [
          '歌词：按节分页，字号大、便于跟唱；',
          '简谱：该首的简谱扫描图（可双指缩放、拖动）；',
          '五线谱：该首的五线谱扫描图（同样可缩放拖动）。',
        ]),
        const GuideLine('歌词页翻页：', [
          '底部「＜ 第 N / M 节 ＞」翻页条左右切换；',
          '在歌词区左右滑动也可以翻页；',
          '顶栏「⟳ 自动」开启后，按播放进度自动翻到对应节。',
        ]),
        const GuideLine('谱面图缩放/拖动：双指捏合缩放，单指拖动平移；双击快速复位。'),
        const GuideLine('Android 版**没有「曲谱」模式** —— 该模式只在 Windows 桌面版提供。'),
      ],
    );

({String title, List<GuideLine> lines}) _playerBar() => (
      title: '播放条（无音量滑轨）',
      lines: [
        const GuideLine('底部播放条：进度条 + 上一首 / 播放暂停 / 下一首。'),
        const GuideLine('**Android 版没有音量滑轨与音量图标**（2026-10-28 定稿）：', [
          '请用手机**音量键**调节（系统音量，与其它音乐 App 一致）；',
          '插拔耳机、蓝牙切换时行为与系统一致。',
        ]),
        const GuideLine('通知栏 / 锁屏可控制播放（播放、暂停、上一首、下一首），'
            '首次使用需允许通知权限。'),
        const GuideLine('拖进度条可跳到任意位置；拖动时不会误触发翻页。'),
      ],
    );

({String title, List<GuideLine> lines}) _leftPanel() => (
      title: '左侧栏：诗歌列表 / 分类 / 我的歌单',
      lines: [
        const GuideLine('左上 ☰ 打开，三栏目顶部切换：', [
          '诗歌列表：全部 474 首，按编号排列；',
          '分类：按主题分类浏览；',
          '我的歌单：自建歌单，可增删改。',
        ]),
        const GuideLine('搜索（诗歌列表栏目顶部搜索框）：', [
          '输入**编号**会定位并高亮该首；',
          '输入**标题关键字**会过滤列表；',
          '点击结果项即播放。',
        ]),
        const GuideLine('歌单操作：新建、重命名、删除；在诗歌上长按或点「更多」可加入歌单。'),
        const GuideLine('选择诗歌后左侧栏自动收起，把屏幕让给内容区。'),
      ],
    );

({String title, List<GuideLine> lines}) _settings(AudioVariant v) => (
      title: '设置与素材导入（SAF）',
      lines: [
        const GuideLine('进入方式：顶栏 ⋮ →「设置」。'),
        const GuideLine('可调项：配色（多套主题）、字号（标准 / 大 / 特大）、'
            '启动时显示手册、关于信息。'),
        const GuideLine('**素材导入**（Android 独有，使用系统 SAF 目录选择器）：', [
          '设置 →「素材」→「选择目录」；',
          '在系统文件选择器里选中存放音频/图片的文件夹；',
          '确认后 App 会把文件复制到自己的私有目录（**不会改动你的原始文件**），'
              '完成后列表刷新即可播放；',
          '导入过程有进度提示，可随时取消。',
        ]),
        if (v == AudioVariant.full || v == AudioVariant.lite)
          const GuideLine('文件命名建议与诗歌编号对应（如 `001.mp3`、`001_鋼琴版.m4a`），'
              '每首才能自动匹配到自己的音频。'),
        if (v == AudioVariant.piano || v == AudioVariant.vocal)
          GuideLine('本版本已内置${v == AudioVariant.piano ? '钢琴' : '人声'}素材，'
              '导入主要用于补充本包未收录的诗歌。'),
        const GuideLine('体积提醒：素材复制进私有目录会占用手机存储，导入前请确认剩余空间。'),
      ],
    );

({String title, List<GuideLine> lines}) _faq(AudioVariant v) => (
      title: '常见问题',
      lines: [
        if (v == AudioVariant.lite)
          const GuideLine('**点了播放没声音？** 精简版不含音频，需先「设置 → 素材 → 选择目录」导入。'),
        if (v != AudioVariant.lite)
          const GuideLine('点了播放没声音？该首可能不在内置素材里，用「设置 → 素材」导入补充。'),
        if (v == AudioVariant.piano)
          const GuideLine('找不到「人声」按钮？本版只含钢琴伴奏，属正常；需要人声请装人声版/全量版。'),
        if (v == AudioVariant.vocal)
          const GuideLine('找不到「钢琴」按钮？本版只含人声，属正常；需要伴奏请装钢琴版/全量版。'),
        if (v == AudioVariant.full)
          const GuideLine('音频按钮点了没反应？若该首只有一个版本，会提示「该首只有…音频」，'
              '这是正常保护，不会静默失败。'),
        const GuideLine('字体显示成方块/乱码？请确认系统未强制替换字体，'
            '或卸载第三方字体模块后重试。'),
        const GuideLine('导入素材失败？确认所选目录有读取权限，且文件为 mp3 / m4a 等常见格式。'),
      ],
    );
