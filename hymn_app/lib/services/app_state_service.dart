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

  /// 全局共享实例（跨模块单键更新时共用同一串行写队列）
  static final AppStateService shared = AppStateService();

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
    bool showLeft = false,
    bool showRight = false,
    String appTheme = '',
    String fontSizeLevel = '',
    bool manualOnStart = true,
  }) {
    final data = <String, Object>{
      'leftTab': leftTab,
      'subcategory': subcategory,
      'playlistName': playlistName,
      'hymnNumber': hymnNumber,
      'audioVersion': audioVersion,
      'displayMode': displayMode,
      'playlistIndex': playlistIndex,
      'showLeft': showLeft,
      'showRight': showRight,
      'appTheme': appTheme,
      'fontSizeLevel': fontSizeLevel,
      'manualOnStart': manualOnStart,
    };
    // 排队执行，串行写入，且异常不影响后续写入
    _writeChain = _writeChain.then((_) => _doWrite(data)).catchError((_) {});
    return _writeChain;
  }

  /// 仅更新 manualOnStart 单键：读文件 → 改该键 → 原子写回。
  /// 挂接同一串行写队列，不影响其他字段（用户手册弹窗独立持久化用）。
  Future<void> updateManualOnStart(bool value) {
    _writeChain = _writeChain.then((_) async {
      final file = File(_statePath);
      Map<String, Object> data = {};
      if (await file.exists()) {
        try {
          final json = jsonDecode(await file.readAsString());
          if (json is Map<String, dynamic>) data = Map<String, Object>.from(json);
        } catch (_) {}
      }
      data['manualOnStart'] = value;
      const encoder = JsonEncoder.withIndent('  ');
      final tmp = File('$_statePath.tmp');
      await tmp.writeAsString(encoder.convert(data), flush: true);
      try {
        await tmp.rename(file.path);
      } catch (_) {
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      }
    }).catchError((_) {});
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
        // 无状态文件 = 全新环境：返回默认状态（首次运行默认第 1 首、收起侧栏）。
        // 不再从旧版本 %APPDATA% shared_preferences.json 迁移——
        // 迁移逻辑已被旧版本（v1.0.4 前）完成使命；若继续迁移，
        // 会污染「首次启动 / 删除 state.json 后启动」的默认行为
        // （测试实测：删除 state.json 后从 Roaming 迁出旧状态导致
        //  恢复异常，见 UI 测试 A01/A03/A04/J04）。
        return _defaultState;
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
        showLeft: (json['showLeft'] as bool?) ?? false,
        showRight: (json['showRight'] as bool?) ?? false,
        appTheme: (json['appTheme'] as String?) ?? '',
        fontSizeLevel: (json['fontSizeLevel'] as String?) ?? '',
        manualOnStart: (json['manualOnStart'] as bool?) ?? true,
      );
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

  /// 左栏（歌单列表）是否展开
  final bool showLeft;

  /// 右栏（诗歌源考）是否展开
  final bool showRight;

  /// 当前配色 id（对应 [theme/app_palette.dart] 的 AppPalette.id；空串 = 默认）
  final String appTheme;

  /// 当前字号等级 id（对应 [theme/app_fonts.dart] 的 FontSizeLevel.id；空串 = 默认）
  final String fontSizeLevel;

  /// 启动时是否自动弹出用户手册（默认 true；手册底部勾选框控制）
  final bool manualOnStart;

  const AppState({
    required this.leftTab,
    required this.subcategory,
    required this.playlistName,
    required this.hymnNumber,
    required this.audioVersion,
    required this.displayMode,
    required this.playlistIndex,
    this.showLeft = false,
    this.showRight = false,
    this.appTheme = '',
    this.fontSizeLevel = '',
    this.manualOnStart = true,
  });
}
