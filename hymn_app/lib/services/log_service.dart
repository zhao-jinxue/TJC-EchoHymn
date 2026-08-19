import 'dart:io';

/// 日志级别
enum LogLevel { info, warning, error }

/// 日志分类标签（文件内标识，便于检索）
abstract final class LogTag {
  /// 程序库文件加载（数据库/资源/转换表/插件等）
  static const String lib = 'LIB';

  /// UI 生成
  static const String ui = 'UI';

  /// 人机交互（点击/搜索/切换等）
  static const String action = 'ACTION';

  /// 个人歌单创建/修改/删除
  static const String playlist = 'PLAYLIST';

  /// 诗歌播放
  static const String play = 'PLAY';

  /// 异常
  static const String error = 'ERROR';

  /// 应用生命周期与状态
  static const String system = 'SYS';
}

/// 应用日志服务
///
/// - 日志目录：`echo_hymn.exe` 同级目录下的 `logs/`（与 state.json 同级，便携）
/// - 日志文件：按天轮转 `app_yyyy-MM-dd.log`，当天写入当天文件
/// - 保留策略：**最多保留 7 个日志文件**（按文件名日期排序，删除更旧的）
///   —— 是「数量」的 7 天，不是时间跨度 7 天
/// - 写入：Future 链串行执行，避免并发写损坏；写失败不影响应用运行
class LogService {
  static final LogService instance = LogService._();

  LogService._();

  /// 写队列：所有写入排队串行执行
  Future<void> _writeChain = Future.value();

  /// 日志目录是否已初始化
  bool _initialized = false;

  /// 日志目录绝对路径（初始化后可用）
  String? _logDirPath;

  /// 当前打开的日志文件名（按天轮转）
  String? _currentFileName;

  /// 初始化日志目录（幂等）。
  ///
  /// [ensureExeDir] 为 true 时保证日志目录位于 `echo_hymn.exe` 同级；
  /// 定位失败则退到当前工作目录（尽量避免无日志可写）。
  Future<void> init({bool ensureExeDir = true}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      String base;
      if (ensureExeDir) {
        try {
          final exe = Platform.resolvedExecutable;
          base = File(exe).parent.path;
        } catch (_) {
          base = Directory.current.path;
        }
      } else {
        base = Directory.current.path;
      }
      final dir = Directory('$base${Platform.pathSeparator}logs');
      await dir.create(recursive: true);
      _logDirPath = dir.path;
    } catch (e) {
      _logDirPath = null;
    }
  }

  /// 日志目录路径（未初始化/失败时为 null）
  String? get logDirPath => _logDirPath;

  // ================= 对外日志接口 =================

  /// 记录一条日志。
  ///
  /// [tag] 建议使用 [LogTag] 常量；[message] 为日志正文；
  /// [detail] 为附加详情（异常栈、数据快照等，可多行）。
  void log(LogLevel level, String tag, String message, {String? detail}) {
    final line = _format(level, tag, message, detail);
    // 串行写，异常不影响后续
    _writeChain = _writeChain.then((_) => _writeLine(line)).catchError((_) {});
  }

  void info(String tag, String message, {String? detail}) =>
      log(LogLevel.info, tag, message, detail: detail);

  void warning(String tag, String message, {String? detail}) =>
      log(LogLevel.warning, tag, message, detail: detail);

  void error(String tag, String message, {String? detail}) =>
      log(LogLevel.error, tag, message, detail: detail);

  /// 记录异常（自动带标签与栈信息）
  void exception(String message, Object e, [StackTrace? stack]) {
    final detail = StringBuffer()
      ..writeln('异常类型: ${e.runtimeType}')
      ..writeln('异常信息: $e');
    if (stack != null) {
      detail.writeln('--- 堆栈 ---');
      detail.write(stack.toString());
    }
    log(LogLevel.error, LogTag.error, message, detail: detail.toString());
  }

  // ================= 内部实现 =================

  /// 格式化一行日志
  String _format(LogLevel level, String tag, String message, String? detail) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final lv = switch (level) {
      LogLevel.info => 'INFO ',
      LogLevel.warning => 'WARN ',
      LogLevel.error => 'ERROR',
    };
    final buf = StringBuffer('[$ts] [$lv] [$tag] $message');
    if (detail != null && detail.trim().isNotEmpty) {
      // 详情按行缩进，保持可读性
      final indented = detail.split('\n').map((l) => '    | $l').join('\n');
      buf.write('\n$indented');
    }
    return buf.toString();
  }

  /// 写入一行（自动轮转文件 + 保留 7 份清理）
  ///
  /// 日志文件编码为 **UTF-8 with BOM**：PowerShell 5.1 / 记事本默认按系统
  /// ANSI（GBK）解码无 BOM 的 UTF-8 文件会导致中文乱码；带 BOM 后
  /// Windows 全部工具（Get-Content/记事本/VSCode）均可正确识别。
  Future<void> _writeLine(String line) async {
    final dir = _logDirPath;
    if (dir == null) return;

    final fileName = _fileNameFor(DateTime.now());
    // 日期变化 → 切新文件
    if (_currentFileName == null || _currentFileName != fileName) {
      _currentFileName = fileName;
      await _rotateAndCleanup(dir, fileName);
    }

    final file = File('$dir${Platform.pathSeparator}$fileName');
    try {
      if (!await file.exists()) {
        // 首次创建：先写 UTF-8 BOM（EF BB BF），再追加内容
        await file.writeAsString('\uFEFF', flush: true);
      }
      await file.writeAsString('$line${Platform.lineTerminator}',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // 写失败静默（不影响应用）
    }
  }

  /// 生成当天日志文件名：app_yyyy-MM-dd.log
  String _fileNameFor(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'app_${d.year}-${two(d.month)}-${two(d.day)}.log';
  }

  /// 轮转：清理超量日志文件（保留最新的 7 个）
  ///
  /// 规则：扫描 logs/ 下所有 `app_*.log`，按文件名（日期）倒序保留最近 7 份，
  /// 其余删除。这里是「数量 7 份」，与文件日期是否连续无关。
  Future<void> _rotateAndCleanup(String dir, String currentName) async {
    final dirObj = Directory(dir);
    try {
      final files = dirObj
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split(Platform.pathSeparator).last.startsWith('app_'))
          .toList();
      // 按文件名倒序（最新日期在前）
      final sorted = files.toList()..sort((a, b) => b.path.compareTo(a.path));
      // 当前文件永远保留；删除超出 7 个的旧文件
      const maxFiles = 7;
      if (sorted.length > maxFiles) {
        for (final f in sorted.skip(maxFiles)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // 清理失败不影响
    }
  }
}
