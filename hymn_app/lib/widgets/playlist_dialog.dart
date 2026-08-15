import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/chinese_convert_service.dart';
import '../services/sqlite_repository.dart';

/// 个人歌单创建弹窗
///
/// 结构：
/// - 顶部标题「个人歌单创建」
/// - 歌单名称输入框（限 30 字）
/// - 搜索框（编号/名称，回车或点击搜索 → 弹出诗歌选择）
/// - 已添加诗歌列表（编号 + 标题 + 减号）
/// - 底部：取消 / 创建（创建后写入数据库，返回 pop(true)）
class CreatePlaylistDialog extends StatefulWidget {
  final SqliteRepository repo;
  const CreatePlaylistDialog({super.key, required this.repo});

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  /// 歌单名称（弹窗关闭前暂存在内存，创建时才写库）
  String _playlistName = '';

  /// 暂存的歌单成员 [{hymnId, name}]
  final List<MapEntry<int, String>> _addedHymns = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部：标题 + 右上角 ✕
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '个人歌单创建',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 歌单名称
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _nameCtrl,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '歌单名称',
                  hintText: '请输入歌单名称（最多 30 字）',
                  counterText: '',
                  isDense: true,
                ),
                onChanged: (v) => _playlistName = v.trim(),
                onSubmitted: (_) => _searchCtrl.clear(),
              ),
            ),
            // 搜索框 + 搜索按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => widget.repo
                              .searchHymns(_searchCtrl.text.trim())
                              .isEmpty
                          ? _searchHymn(_searchCtrl.text.trim())
                          : _openHymnSearch(_searchCtrl.text.trim()),
                      decoration: const InputDecoration(
                        hintText: '输入编号或诗歌名称',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: () => _openHymnSearch(_searchCtrl.text.trim()),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text('搜索'),
                    ),
                  ),
                ],
              ),
            ),
            // 已添加列表
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '已添加诗歌（${_addedHymns.length}）',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: _addedHymns.isEmpty
                  ? const Center(
                      child: Text(
                        '暂未添加诗歌',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _addedHymns.length,
                      itemBuilder: (context, index) {
                        final entry = _addedHymns[index];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: SizedBox(
                            width: 40,
                            child: Text(
                              '${entry.key}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: AppColors.danger),
                            tooltip: '移除',
                            onPressed: () =>
                                setState(() => _addedHymns.removeAt(index)),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _doCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('创建'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 非精确搜索：搜索框直接回车但无结果时，直接列出搜索出的诗歌
  void _searchHymn(String keyword) {
    final results = widget.repo.searchHymns(keyword);
    if (results.isEmpty) return;
    _openHymnResults(results);
  }

  Future<void> _openHymnSearch(String keyword) async {
    if (keyword.isEmpty) return;
    final results = widget.repo.searchHymns(keyword);
    if (results.isEmpty) {
      _showToast('未找到相关诗歌');
      return;
    }
    _openHymnResults(results);
  }

  Future<void> _openHymnResults(List<Hymn> results) async {
    final selected = await showDialog<Hymn>(
      context: context,
      builder: (ctx) => HymnPickDialog(results: results),
    );
    if (selected == null || !mounted) return;
    // 不允许重复添加
    final exists = _addedHymns.any((e) => e.key == selected.id);
    if (exists) {
      _showToast('该诗歌已在歌单中');
      return;
    }
    setState(() {
      _addedHymns.add(MapEntry(selected.id,
          ChineseConvertService.instance.toSimplified(selected.title)));
    });
  }

  void _doCreate() {
    if (_playlistName.isEmpty) {
      _showToast('请输入歌单名称');
      return;
    }
    final id = widget.repo.createPlaylist(_playlistName);
    if (_addedHymns.isNotEmpty) {
      for (var i = 0; i < _addedHymns.length; i++) {
        final entry = _addedHymns[i];
        widget.repo.addHymnToPlaylist(id, entry.key, entry.value);
      }
    }
    Navigator.pop(context, true);
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 诗歌选择弹窗：展示搜索结果，点击「添加」返回该诗歌
class HymnPickDialog extends StatelessWidget {
  final List<Hymn> results;
  const HymnPickDialog({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '诗歌展示',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 搜索结果列表
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        '未找到诗歌',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final h = results[index];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: SizedBox(
                            width: 40,
                            child: Text(
                              h.hymnNumber,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            ChineseConvertService.instance
                                .toSimplified(h.title),
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: () => Navigator.pop(context, h),
                            child: const Text('添加'),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 底部
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
