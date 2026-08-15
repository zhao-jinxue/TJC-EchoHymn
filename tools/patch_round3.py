# -*- coding: utf-8 -*-
"""第 3 轮 UI 修改补丁"""
import io


def patch(path, old, new, count=1):
    with io.open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    if old not in c:
        print(f'[SKIP] {path}')
        return False
    c = c.replace(old, new, count)
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(c)
    print(f'[OK] {path}')
    return True


# ============ 1. audio_service.dart：修复播放 + 暴露错误 ============
AS = r'e:\EchoHymn\hymn_app\lib\services\audio_service.dart'
patch(AS, '''  Hymn? _currentHymn;
  String _currentAudioVersion = '鋼琴版';
  bool _disposed = false;''',
'''  Hymn? _currentHymn;
  String _currentAudioVersion = '鋼琴版';
  bool _disposed = false;
  String? lastError; // 最近一次播放错误（调试用）''')

patch(AS, '''    _emitStatus(PlayerStatus.loading);
    try {
      if (abs.startsWith('http://') || abs.startsWith('https://')) {
        await _player.setUrl(abs);
      } else {
        await _player.setFilePath(abs);
      }
      await _player.play();
      _emitStatus(PlayerStatus.playing);
    } catch (e) {
      _emitStatus(PlayerStatus.error);
      rethrow;
    }''',
'''    _emitStatus(PlayerStatus.loading);
    try {
      if (abs.startsWith('http://') || abs.startsWith('https://')) {
        await _player.setAudioSource(AudioSource.uri(Uri.parse(abs)));
      } else {
        await _player.setAudioSource(AudioSource.uri(Uri.file(abs)));
      }
      await _player.play();
      lastError = null;
      _emitStatus(PlayerStatus.playing);
    } catch (e) {
      lastError = e.toString();
      _emitStatus(PlayerStatus.error);
    }''')

# ============ 2. hymn_display.dart：恢复人声版按钮 + 错误详情 ============
HD = r'e:\EchoHymn\hymn_app\lib\widgets\hymn_display.dart'
patch(HD, '''          _versionBtn(
            label: '钢琴版',
            icon: Icons.piano,
            active:
                hymn != null && widget.audio.currentAudioVersion.contains('鋼琴'),
            onTap: hymn == null ? null : () => _switchVersion(hymn, '鋼琴版'),
          ),
          const Spacer(),''',
'''          _versionBtn(
            label: '钢琴版',
            icon: Icons.piano,
            active:
                hymn != null && widget.audio.currentAudioVersion.contains('鋼琴'),
            onTap: hymn == null ? null : () => _switchVersion(hymn, '鋼琴版'),
          ),
          const SizedBox(width: 8),
          _buildVoiceButton(hymn),
          const Spacer(),''')

patch(HD, '''  Widget _modeBtn(String label, DisplayMode mode, IconData icon) {''',
'''  /// 人声版切换按钮（切到第一个人声版本；多版本列表在播放条）
  Widget _buildVoiceButton(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    if (hymn == null || voices.isEmpty) {
      return _versionBtn(label: '人声版', icon: Icons.mic, active: false);
    }
    final currentVoice = widget.audio.currentAudioVersion;
    final isVoiceActive = currentVoice.contains('人聲') ||
        currentVoice.contains('人声') ||
        !currentVoice.contains('鋼琴');
    return _versionBtn(
      label: '人声版',
      icon: Icons.mic,
      active: isVoiceActive,
      onTap: () => _switchVersion(hymn, voices.first),
    );
  }

  Widget _modeBtn(String label, DisplayMode mode, IconData icon) {''')

patch(HD, '''  void _showAudioError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('音频加载失败'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }''',
'''  void _showAudioError() {
    if (!mounted) return;
    final err = widget.audio.lastError;
    final msg = (err == null || err.isEmpty)
        ? '音频加载失败'
        : '音频加载失败：$err';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }''')

# ============ 3. home_screen.dart：切换即保存 + 分页 35 ============
HS = r'e:\EchoHymn\hymn_app\lib\screens\home_screen.dart'
patch(HS, '  static const int _pageSize = 50;', '  static const int _pageSize = 35;')
patch(HS, '    final start = _listPage * 50;', '    final start = _listPage * _pageSize;')
patch(HS, '    final end = (start + 50).clamp(0, all.length);',
           '    final end = (start + _pageSize).clamp(0, all.length);')

# 左栏 tab 切换保存
patch(HS, '''          onTap: () {
            setState(() {
              _leftTab = tab;
              _showDefaultPlaylistContent = false;
            });
          },''',
'''          onTap: () {
            setState(() {
              _leftTab = tab;
              _showDefaultPlaylistContent = false;
            });
            _saveState();
          },''')

# 二级目录选择保存
patch(HS, '''        onTap: () {
          // 点击二级目录 → 展示包含的诗歌
          setState(() {
            _selectedSubcategory = sub.subcategory;
            _defaultPlaylistHymns = _buildCategoryHymns(sub);
            _showDefaultPlaylistContent = true;
          });
        },''',
'''        onTap: () {
          setState(() {
            _selectedSubcategory = sub.subcategory;
            _defaultPlaylistHymns = _buildCategoryHymns(sub);
            _showDefaultPlaylistContent = true;
          });
          _saveState();
        },''')

# 个人歌单选择保存
patch(HS, '            onTap: () => setState(() => _selectedPlaylistName = pl.name),',
           '            onTap: () {\n'
           '              setState(() => _selectedPlaylistName = pl.name);\n'
           '              _saveState();\n'
           '            },')

# 播放时保存当前诗歌
patch(HS, '''  void _playHymnFromList(Hymn hymn, int index, List<Hymn> contextList) {
    _audio!.setPlaylist(contextList, startIndex: index);
    _audio!.playHymn(hymn, index: index, version: _currentAudioVersion);
    setState(() {});
  }''',
'''  void _playHymnFromList(Hymn hymn, int index, List<Hymn> contextList) {
    _audio!.setPlaylist(contextList, startIndex: index);
    _audio!.playHymn(hymn, index: index, version: _currentAudioVersion);
    setState(() {});
    _saveState();
  }''')

patch(HS, '''    audio.playHymn(hymn,
        index: idx >= 0 ? idx : 0, version: _currentAudioVersion);
    setState(() {});
  }''',
'''    audio.playHymn(hymn,
        index: idx >= 0 ? idx : 0, version: _currentAudioVersion);
    setState(() {});
    _saveState();
  }''')

# ============ 4. app.dart：滚动条 10px ============
TH = r'e:\EchoHymn\hymn_app\lib\app.dart'
patch(TH, 'thickness: WidgetStatePropertyAll(13),', 'thickness: WidgetStatePropertyAll(10),')

# ============ 5. win32_window.cpp：最小宽度保证歌词 450 ============
CP = r'e:\EchoHymn\hymn_app\windows\runner\win32_window.cpp'
patch(CP, '      mmi->ptMinTrackSize.x = 1000;', '      mmi->ptMinTrackSize.x = 1202;')

print('done')