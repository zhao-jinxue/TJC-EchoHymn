import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';

/// 五态统一视图（`ANDROID_PLAN §3.0` 设计基础）
///
/// 规格要求：**Loading / Empty / Error / Fallback**（Offline 对本地应用不适用——
/// 无网络依赖，素材缺失归入 Fallback）。统一组件避免各处文案/间距/重试行为不一致。
///
/// - [LoadingView]：转圈 + 文案（调用方负责「>300ms 才显示」防闪烁）
/// - [EmptyView]：图标 + 文案（真空态：无歌词 / 无搜索结果 …）
/// - [ErrorView]：图标 + 文案 + **重试按钮**（此前只有文字，用户无路可走）
/// - [FallbackView]：静默灰字（无谱面等非错误降级，§3.0 明确"不弹错"）
class LoadingView extends StatefulWidget {
  const LoadingView({
    super.key,
    this.message = '正在载入…',
    this.delay = const Duration(milliseconds: 300),
  });

  final String message;

  /// 延迟显示（§3.0：**">300ms 才显示"** 防闪烁）——本地查库常几十毫秒，
  /// 立即显示会让转圈图标"闪一下"。测试可传 `Duration.zero`。
  final Duration delay;

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _visible = true;
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 未到 300ms：不占位也不画转圈（避免闪烁）
    if (!_visible) return const SizedBox.shrink();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.message,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.textTertiary),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 错误态：图标 + 文案 +〔重试〕（`ANDROID_PLAN §3.0` 五态 Error）
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String message;

  /// 补充说明（小字灰；可放路径/异常摘要）
  final String? detail;

  /// null = 无重试入口（纯提示）
  final VoidCallback? onRetry;

  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 34, color: AppColors.danger),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(retryLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 静默降级态（非错误）：如「暂无谱面」——只显示灰字，不弹错、不给重试
class FallbackView extends StatelessWidget {
  const FallbackView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
      ),
    );
  }
}
