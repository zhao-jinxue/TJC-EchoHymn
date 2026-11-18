import '../app_feature.dart';
import 'user_manual_dialog.dart' show GuideLine;

/// Android 版用户手册
///
/// 原则（2026-11-17 用户要求）：**只说明本应用有什么、怎么用** ——
/// 不写平台对比（如「Android 没有…」「桌面版才有…」）、不写技术术语
/// （SAF / 私有目录 / 通道）、不写跨版本购买指引。按运行期能力
/// （full / piano / vocal / lite）只陈述本版本的事实。
List<({String title, List<GuideLine> lines})> androidManualSections() {
  final variant = kAudioVariant;
  final sections = <({String title, List<GuideLine> lines})>[
    _start(),
    _mainScreen(),
    _displayMode(),
  ];
  if (variant != AudioVariant.lite) {
    sections.add(_playback());
  }
  sections.addAll([
    _audioInfo(variant),
    _listPanel(),
    _settings(),
    _dataImport(),
    _faq(variant),
  ]);
  return sections;
}

({String title, List<GuideLine> lines}) _start() => (
      title: '打开与关闭手册',
      lines: [
        const GuideLine('打开：顶栏右侧「⋮」→「用户手册」，或「设置」→「用户手册」。'),
        const GuideLine('关闭：点右上角「✕」，或点页面空白处。'),
        const GuideLine('页面底部「启动时显示本手册」开关，控制每次启动是否自动打开。'),
      ],
    );

({String title, List<GuideLine> lines}) _mainScreen() => (
      title: '主界面',
      lines: [
        const GuideLine('左上角「☰」：打开诗歌列表、分类、我的歌单。'),
        const GuideLine('中间标题：当前诗歌，如「第 1 首《颂赞独一真神》」。'),
        const GuideLine('右上角「🔍」：搜索；「⋮」：用户手册、设置、关于。'),
        const GuideLine('标题下方按钮：左边是音频，右边是显示模式（歌词 / 简谱 / 五线谱）。'),
      ],
    );

({String title, List<GuideLine> lines}) _displayMode() => (
      title: '歌词、简谱与五线谱',
      lines: [
        const GuideLine('点「歌词 / 简谱 / 五线谱」切换内容。'),
        const GuideLine('歌词：一页一节，底部「＜ 第 N / M 节 ＞」翻页，也可以在歌词上左右滑动。'),
        const GuideLine('点右上角「自动」后，歌词会随播放进度自动翻页。'),
        const GuideLine('简谱、五线谱：显示该首的谱面图片；双指捏合缩放，单指拖动，双击复位。'),
      ],
    );

({String title, List<GuideLine> lines}) _playback() => (
      title: '播放',
      lines: [
        const GuideLine('底部播放条：拖进度条可跳转；按钮为上一首、播放 / 暂停、下一首。'),
        const GuideLine('音量请用手机音量键调节。'),
        const GuideLine('播放时可在通知栏和锁屏上控制播放、暂停、上一首、下一首。'),
      ],
    );

({String title, List<GuideLine> lines}) _audioInfo(AudioVariant variant) {
  switch (variant) {
    case AudioVariant.full:
      return (
        title: '音频选择',
        lines: [
          const GuideLine('点左侧音频按钮，可在「钢琴」和「人声」之间切换。'),
          const GuideLine('若该首只有一种音频，点击时会提示「该首只有…音频」。'),
        ],
      );
    case AudioVariant.piano:
      return (
        title: '音频',
        lines: [
          const GuideLine('本应用提供钢琴伴奏音频。'),
        ],
      );
    case AudioVariant.vocal:
      return (
        title: '音频',
        lines: [
          const GuideLine('本应用提供人声演唱音频。'),
        ],
      );
    case AudioVariant.lite:
      return (
        title: '音频',
        lines: [
          const GuideLine('本应用没有播放功能，只提供歌词与谱面阅读。'),
          const GuideLine('页面底部可点「上一首」「下一首」切换诗歌。'),
        ],
      );
  }
}

({String title, List<GuideLine> lines}) _listPanel() => (
      title: '诗歌列表与歌单',
      lines: [
        const GuideLine('「诗歌列表」：全部 474 首，按编号排列。'),
        const GuideLine('「分类」：按主题分组浏览。'),
        const GuideLine('「我的歌单」：新建、改名、删除歌单，并可把诗歌加入歌单。'),
        const GuideLine('列表顶部搜索框：输入编号可定位该首，输入歌名或歌词可筛选。'),
        const GuideLine('点诗歌即开始浏览或播放；选择后列表自动收起。'),
      ],
    );

({String title, List<GuideLine> lines}) _settings() => (
      title: '设置',
      lines: [
        const GuideLine('进入：顶栏「⋮」→「设置」。'),
        const GuideLine('配色：晨光蓝、暖阳金、静谧绿、典雅紫、暗夜墨，点选立即生效。'),
        const GuideLine('字号：标准 / 大 / 特大，点选立即生效。'),
        const GuideLine('数据导入：导入扫描图、人声、钢琴三类数据（见下一节）。'),
        const GuideLine('素材自检：检查已导入的文件是否完整。'),
        const GuideLine('启动时显示手册：控制每次启动是否自动打开本手册。'),
      ],
    );

({String title, List<GuideLine> lines}) _dataImport() => (
      title: '数据导入',
      lines: [
        const GuideLine('安装包附带三类压缩文件：扫描图、人声、钢琴。'),
        const GuideLine('导入步骤：设置 →「数据导入」→ 选择类型（扫描图 / 人声 / 钢琴）→ 选择压缩文件。'),
        const GuideLine('程序只取需要的文件，同名文件直接覆盖；导入完成后重启应用。'),
        const GuideLine('导入后可点「素材自检」，查看是否有缺失或损坏的文件。'),
      ],
    );

({String title, List<GuideLine> lines}) _faq(AudioVariant variant) => (
      title: '常见问题',
      lines: [
        if (variant != AudioVariant.lite)
          const GuideLine('播放没有声音：该首没有音频文件，导入对应的音频包即可。'),
        const GuideLine('简谱或五线谱显示「暂无」：该首没有谱面图片，导入扫描图包即可。'),
        const GuideLine('导入完成但内容没变：重启应用。'),
        const GuideLine('自检提示缺失或损坏：重新导入对应的数据包。'),
        if (variant == AudioVariant.full)
          const GuideLine('音频按钮点了没反应：该首只有一种音频，程序会给出提示。'),
      ],
    );
