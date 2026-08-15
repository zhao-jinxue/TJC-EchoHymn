# -*- coding: utf-8 -*-
"""第 2 轮 UI 修改补丁（Windows 环境）"""
import io

def patch(path, old, new, count=1):
    with io.open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    if old not in c:
        print(f'[SKIP] {path}: pattern not found')
        return False
    c = c.replace(old, new, count)
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(c)
    print(f'[OK] {path} patched')
    return True

# ============ 1. hymn_display.dart ============
HD = r'e:\EchoHymn\hymn_app\lib\widgets\hymn_display.dart'

# 1a. 移除内容区人声下拉（_buildVoiceDropdown 调用）
patch(HD, '''          const SizedBox(width: 8),
          _buildVoiceDropdown(hymn),
          const Spacer(),''', '''          const Spacer(),''')

# 1b. 移除 _buildVoiceDropdown 与 _voiceLabel 方法体（保留 _versionBtn 等）
start = HD_index = None
with io.open(HD, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 删除 _buildVoiceDropdown 与 _voiceLabel 两个方法（从 "  Widget _buildVoiceDropdown" 到 "  String _voiceLabel" 结束）
out = []
skip = False
for i, line in enumerate(lines):
    if line.strip().startswith('Widget _buildVoiceDropdown(Hymn? hymn) {'):
        skip = True
        continue
    if skip:
        # 遇到下一个方法定义或类结束为止（_voiceLabel 紧随其后）
        if line.strip().startswith('String _voiceLabel('):
            skip = False
            continue
        if line.startswith('  //') or line.startswith('  Widget') or line.startswith('  void') or line.startswith('  Future'):
            skip = False
        if skip:
            continue
    out.append(line)

with io.open(HD, 'w', encoding='utf-8', newline='') as f:
    f.writelines(out)
print(f'[OK] {HD} removed _buildVoiceDropdown/_voiceLabel')

# 1c. 播放条人声列表按钮间距（下一首后加间距）
patch(HD, '''        IconButton(
          icon: const Icon(Icons.skip_next, color: AppColors.textPrimary),
          tooltip: '下一首',
          onPressed: () => widget.audio.playNext(),
        ),
        // 人声版本列表（>1 时显示，悬停提示 10 秒）
        if (voices.length > 1) _buildVoiceListButton(hymn!, voices),''',
'''        IconButton(
          icon: const Icon(Icons.skip_next, color: AppColors.textPrimary),
          tooltip: '下一首',
          onPressed: () => widget.audio.playNext(),
        ),
        // 人声版本列表（>1 时显示，悬停提示 10 秒，与下一首拉开间距）
        if (voices.length > 1) ...[
          const SizedBox(width: 24),
          _buildVoiceListButton(hymn!, voices),
        ],''')

# 1d. 歌词字号以铺满显示区为目标（基于宽高综合，先测再排版）
patch(HD, '''    return LayoutBuilder(
      builder: (context, constraints) {
        // 响应式字号：随窗口缩放
        final w = constraints.maxWidth;
        final titleSize = (w / 36).clamp(20.0, 34.0);
        final bodySize = (w / 52).clamp(14.0, 24.0);
        final labelSize = (w / 90).clamp(12.0, 16.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                ChineseConvertService.instance.toSimplified(hymn.title),
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '第 ${hymn.hymnNumber} 首',
                style: TextStyle(
                    fontSize: labelSize, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < verses.length; i++) ...[
                if (verses[i].trim().isNotEmpty) ...[
                  Text(
                    '第${i + 1}节',
                    style: TextStyle(
                      fontSize: labelSize,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ChineseConvertService.instance.toSimplified(verses[i]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: bodySize,
                      height: 1.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ],
          ),
        );
      },
    );''',
'''    return LayoutBuilder(
      builder: (context, constraints) {
        // 以「铺满显示区」为目标计算字号：先用基准字号测算内容高度，再按比例缩放铺满
        const pad = 48.0; // 上下留白 24+24
        double baseBody = 18.0;
        // 粗估每段高度：标题 + 节标签 × N + 歌词 × N
        final verseTexts = verses.where((v) => v.trim().isNotEmpty).toList();
        int lineCount = 0;
        for (final v in verseTexts) {
          final lines = v.split('\\n').length;
          lineCount += lines + 1; // + 节标签
        }
        // 每行按 1.8 倍字号高度估算
        final availH = (constraints.maxHeight - pad).clamp(100.0, 4000.0);
        final availW = constraints.maxWidth - pad;
        // 行高与字号关系：行距 1.8 → 每行约 2.0 倍字号
        final maxByH = lineCount > 0 ? availH / (lineCount * 2.0) : 40.0;
        final maxByW = availW / 14.0; // 每行约 14 个汉字
        final bodySize = [baseBody, maxByH, maxByW].reduce((a, b) => a < b ? a : b).clamp(14.0, 30.0);
        final titleSize = (bodySize * 1.4).clamp(20.0, 34.0);
        final labelSize = (bodySize * 0.7).clamp(12.0, 16.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                ChineseConvertService.instance.toSimplified(hymn.title),
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '第 ${hymn.hymnNumber} 首',
                style: TextStyle(
                    fontSize: labelSize, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < verses.length; i++) ...[
                if (verses[i].trim().isNotEmpty) ...[
                  Text(
                    '第${i + 1}节',
                    style: TextStyle(
                      fontSize: labelSize,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ChineseConvertService.instance.toSimplified(verses[i]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: bodySize,
                      height: 1.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ],
          ),
        );
      },
    );''')

# 1e. 滚动条宽度增加 5px（全局滚动条）→ 通过 app.dart theme 设置
THEME = r'e:\EchoHymn\hymn_app\lib\app.dart'
patch(THEME, '''    return MaterialApp(
      title: 'EchoHymn · 聆听赞美诗',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const HomeScreen(),
    );''',
'''    return MaterialApp(
      title: 'EchoHymn · 聆听赞美诗',
      debugShowCheckedModeBanner: false,
      theme: theme,
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(13), // 默认 8 → +5
        thumbColor: WidgetStatePropertyAll(Color(0xFFC1C1C1)),
      ),
      home: const HomeScreen(),
    );''')

# ============ 2. home_screen.dart ============
HS = r'e:\EchoHymn\hymn_app\lib\screens\home_screen.dart'

# 2a. 顶栏箭头方向反转（第 1 条）
patch(HS, '''            child: _toggleButton(
              icon: _showLeft ? Icons.chevron_left : Icons.chevron_right,''',
'''            child: _toggleButton(
              icon: _showLeft ? Icons.chevron_right : Icons.chevron_left,''')
patch(HS, '''            child: _toggleButton(
              icon: _showRight ? Icons.chevron_right : Icons.chevron_left,''',
'''            child: _toggleButton(
              icon: _showRight ? Icons.chevron_left : Icons.chevron_right,''')

# 2b. 左栏宽度 400 → 350（第 6 条）
patch(HS, '''    return SizedBox(
      width: 400,''', '''    return SizedBox(
      width: 350,''')

# 2c. 左栏空白区兜底：无选中内容时可缩放（软最小，由窗口级 hard min 保证）
# 左栏 350 → 最小 350（由窗口最小尺寸保证）

# ============ 3. win32_window.cpp 最小尺寸 ============
CppFile = r'e:\EchoHymn\hymn_app\windows\runner\win32_window.cpp'
patch(CppFile, '''    case WM_DESTROY:''', '''    case WM_GETMINMAXINFO: {
      // 设置窗口最小尺寸 1000x700（逻辑像素，DPI 已按 96 比例）
      auto mmi = reinterpret_cast<MINMAXINFO*>(lparam);
      mmi->ptMinTrackSize.x = 1000;
      mmi->ptMinTrackSize.y = 700;
      return 0;
    }

    case WM_DESTROY:''')

print('done')