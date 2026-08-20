import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/log_service.dart';

/// 主题色常量（按 UI 确认单规范）
class AppColors {
  static const Color primary = Color(0xFF2B6AE0);
  static const Color primaryHover = Color(0xFF1E57C8);
  static const Color accent = Color(0xFF00A870);
  static const Color pageBg = Color(0xFFFAFBFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color sidebarBg = Color(0xFFF5F6FA);
  static const Color textPrimary = Color(0xFF1F2329);
  static const Color textSecondary = Color(0xFF646A73);
  static const Color textTertiary = Color(0xFF8F959E);
  static const Color divider = Color(0xFFE5E6EB);
  static const Color border = Color(0xFFD0D3D9);
  static const Color success = Color(0xFF00A870);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color danger = Color(0xFFF54A45);
  static const Color selectedBg = Color(0xFFE8F0FE);

  /// 歌词显示区背景（暖白，与侧栏冷灰 #F5F6FA 形成轻微色差，便于感知区域大小）
  static const Color lyricsBg = Color(0xFFFDF8EE);
}

/// EchoHymn 应用根组件
class EchoHymnApp extends StatelessWidget {
  const EchoHymnApp({super.key});

  @override
  Widget build(BuildContext context) {
    LogService.instance.info(LogTag.ui, '生成应用根组件（EchoHymnApp / Material 主题）');
    final base = ThemeData.light(useMaterial3: true);
    final theme = base.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.pageBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cardBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      // 全局滚动条：宽度 13px（默认 8 → +5），滑块 #C1C1C1
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(10),
        thumbColor: WidgetStatePropertyAll(Color(0xFFC1C1C1)),
      ),
    );

    LogService.instance.info(
      LogTag.ui,
      'MaterialApp 构建完成',
      detail: '标题: EchoHymn · 聆听赞美诗\n主页: HomeScreen',
    );
    return MaterialApp(
      title: 'EchoHymn · 聆听赞美诗',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const HomeScreen(),
    );
  }
}
