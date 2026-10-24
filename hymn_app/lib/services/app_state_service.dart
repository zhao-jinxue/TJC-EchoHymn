import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用状态持久化：记住上次选择（锚点 = 当前播放/选择的诗歌及其上下文）
///
/// v1.0.4：存储位置从 `%APPDATA%\com.example\echo_hymn\shared_preferences.json`
/// 改为 **echo_hymn.exe 同级目录下的 `state.json`**（便携，随程序一起拷贝）。
///
/// 移动端（2026-10-24）：`Platform.resolvedExecutable` 指向系统进程路径
/// （写不进去 → 状态永远保存不了），改用应用私有目录，见 [ensurePath]。
///
/// 容错：文件不存在/损坏时返回默认状态，绝不抛出导致启动失败。
class AppStateService {
  static const _fileName = 'state.json';

  /// 状态文件所在目录（由 [ensurePath] 初始化）
  static String? _dir;

  /// 初始化状态目录（幂等）。
  ///
  /// **移动端必须在 `load()` 之前 `await` 一次**；桌面端可选（未初始化时回退
  /// exe 同级目录）。
  static Future<void> ensurePath() async {
    if (_dir != null) return;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        _dir = (await getApplicationSupportDirectory()).path;
        return;
      } catch (_) {
        // 落到下面的桌面逻辑（极端情况：插件不可用）
      }
    }
    try {
      _dir = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      _dir = Directory.current.path;
    }
  }

  /// 全局共享实例（跨模块单键更新时共用同一串行写队列）
  static final AppStateService shared = AppStateService();

  /// 写队列：所有写入排队串行执行，避免并发写同一 tmp 文件导致文件损坏
  Future<void> _writeChain = Future.value();

  /// 状态文件路径（桌面 = exe 同级；移动端 = 应用私有目录）
  static String get _statePath => _dir == null
      ? _fileName
      : '$_dir${Platform.pathSeparator}$_fileName';

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
    bool lyricAutoMode = true,
    String closeAction = '',
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
      'lyricAutoMode': lyricAutoMode,
      'closeAction': closeAction,
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
        lyricAutoMode: (json['lyricAutoMode'] as bool?) ?? true,
        closeAction: (json['closeAction'] as String?) ?? '',
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

  /// 歌词翻页模式：true=自动（跟随播放进度），false=手动（按钮翻页）
  final bool lyricAutoMode;

  /// 关闭按钮行为：''=未选择（首次点击关闭时弹窗询问）、
  /// 'exit'=直接关闭、'tray'=最小化到系统托盘（v1.8.0）
  final String closeAction;

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
    this.lyricAutoMode = true,
    this.closeAction = '',
  });
}
