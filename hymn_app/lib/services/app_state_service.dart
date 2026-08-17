import 'dart:convert';
import 'dart:io';

/// 应用状态持久化：记住上次选择（锚点 = 当前播放/选择的诗歌及其上下文）
///
/// v1.0.4：存储位置从 `%APPDATA%\com.example\echo_hymn\shared_preferences.json`
/// 改为 **echo_hymn.exe 同级目录下的 `state.json`**（便携，随程序一起拷贝）。
///
/// 容错：文件不存在/损坏时返回默认状态，绝不抛出导致启动失败。
class AppStateService {
  static const _fileName = 'state.json';

  /// 写队列：所有写入排队串行执行，避免并发写同一 tmp 文件导致文件损坏
  Future<void> _writeChain = Future.value();

  /// exe 同级目录的 state.json 路径
  static String get _statePath {
    try {
      final exe = Platform.resolvedExecutable;
      final dir = File(exe).parent.path;
      return '$dir\\$_fileName';
    } catch (_) {
      // 极端情况下取当前工作目录
      return _fileName;
    }
  }

  Future<void> saveAll({
    required String leftTab,
    required String subcategory,
    required String playlistName,
    required String hymnNumber,
    required String audioVersion,
    required String displayMode,
    required int playlistIndex,
  }) {
    final data = <String, Object>{
      'leftTab': leftTab,
      'subcategory': subcategory,
      'playlistName': playlistName,
      'hymnNumber': hymnNumber,
      'audioVersion': audioVersion,
      'displayMode': displayMode,
      'playlistIndex': playlistIndex,
    };
    // 排队执行，串行写入，且异常不影响后续写入
    _writeChain = _writeChain.then((_) => _doWrite(data)).catchError((_) {});
    return _writeChain;
  }

  Future<void> _doWrite(Map<String, Object> data) async {
    final file = File(_statePath);
    // 原子写：先写临时文件再替换，避免写一半损坏
    // 用 2 空格缩进格式化输出，便于人工阅读/排查
    final tmp = File('$_statePath.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(encoder.convert(data), flush: true);
    // 直接 rename 覆盖；如目标存在且平台不允许覆盖，则先删再改名
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
  }

  Future<AppState> load() async {
    try {
      final file = File(_statePath);
      if (!await file.exists()) {
        // 尝试从旧位置迁移一次（用户旧版本状态）
        return _migrateFromLegacy();
      }
      final text = await file.readAsString();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return _defaultState;
      return AppState(
        leftTab: (json['leftTab'] as String?) ?? '',
        subcategory: (json['subcategory'] as String?) ?? '',
        playlistName: (json['playlistName'] as String?) ?? '',
        hymnNumber: (json['hymnNumber'] as String?) ?? '',
        audioVersion: (json['audioVersion'] as String?) ?? '',
        displayMode: (json['displayMode'] as String?) ?? '',
        playlistIndex: (json['playlistIndex'] as num?)?.toInt() ?? -1,
      );
    } catch (_) {
      return _defaultState;
    }
  }

  /// 从旧位置（Roaming\com.example\echo_hymn\shared_preferences.json）迁移一次
  AppState _migrateFromLegacy() {
    try {
      final roaming = Platform.environment['APPDATA'] ?? '';
      if (roaming.isEmpty) return _defaultState;
      final legacy =
          File('$roaming\\com.example\\echo_hymn\\shared_preferences.json');
      if (!legacy.existsSync()) return _defaultState;
      final text = legacy.readAsStringSync();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return _defaultState;
      // 旧键带 flutter. 前缀
      String s(String k) => (json['flutter.$k'] as String?) ?? '';
      final state = AppState(
        leftTab: s('left_tab'),
        subcategory: s('subcategory'),
        playlistName: s('playlist_name'),
        hymnNumber: s('hymn_number'),
        audioVersion: s('audio_version'),
        displayMode: s('display_mode'),
        playlistIndex: (json['flutter.playlist_index'] as num?)?.toInt() ?? -1,
      );
      // 迁移完成后写入新位置
      saveAll(
        leftTab: state.leftTab,
        subcategory: state.subcategory,
        playlistName: state.playlistName,
        hymnNumber: state.hymnNumber,
        audioVersion: state.audioVersion,
        displayMode: state.displayMode,
        playlistIndex: state.playlistIndex,
      );
      return state;
    } catch (_) {
      return _defaultState;
    }
  }

  static const _defaultState = AppState(
    leftTab: '',
    subcategory: '',
    playlistName: '',
    hymnNumber: '',
    audioVersion: '',
    displayMode: '',
    playlistIndex: -1,
  );
}

class AppState {
  final String leftTab;
  final String subcategory;
  final String playlistName;
  final String hymnNumber;
  final String audioVersion;
  final String displayMode;

  /// 当前诗歌在播放列表中的位置索引（-1 表示未记录）
  final int playlistIndex;

  const AppState({
    required this.leftTab,
    required this.subcategory,
    required this.playlistName,
    required this.hymnNumber,
    required this.audioVersion,
    required this.displayMode,
    required this.playlistIndex,
  });
}
