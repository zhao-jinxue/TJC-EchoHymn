import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/playlist.dart';
import '../services/chinese_convert_service.dart';
import '../services/sqlite_repository.dart';

/// 个人歌单创建/修改弹窗（复用同一个弹窗）
///
/// 结构：
/// - 顶部标题（新建：「个人歌单创建」；修改：「修改歌单」）
/// - 歌单名称输入框（限 30 字）
/// - 搜索框（编号/名称，回车或点击搜索 → 弹出诗歌选择）
/// - 已添加诗歌列表（编号 + 标题 + 减号）
/// - 底部按钮：
///   - 新建模式：取消 / 创建
///   - 修改模式：删除歌单 / 取消 / 保存
///
/// 成员存储：`[{标题: 编号}]`（与 hymn_category.hymns 一致的 JSON 格式）
///
/// 返回值（String?）：'create' 新建成功 / 'save' 修改成功 / 'delete' 删除歌单 / null 取消
class CreatePlaylistDialog extends StatefulWidget {
  final SqliteRepository repo;
  final Playlist? existing; // 传入则为修改模式
  const CreatePlaylistDialog({super.key, required this.repo, this.existing});

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  /// 歌单名称（弹窗关闭前暂存在内存，提交时才写库）
  String _playlistName = '';

  /// 暂存的歌单成员 [{标题, 编号}]
  final List<MapEntry<String, int>> _addedHymns = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // 修改模式：预填名称与已添加成员
    final existing = widget.existing;
    if (existing != null) {
      _playlistName = existing.name;
      _nameCtrl.text = existing.name;
      _addedHymns.addAll(existing.hymns);
    }
  }

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
                  Expanded(
                    child: Text(
                      _isEdit ? '修改歌单' : '个人歌单创建',
                      style: const TextStyle(
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
                    onPressed: () => Navigator.pop(context, null),
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
                      onSubmitted: (_) =>
                          _openHymnSearch(_searchCtrl.text.trim()),
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
                              '${entry.value}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.key,
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
                  // 修改模式：追加「删除歌单」按钮
                  if (_isEdit) ...[
                    OutlinedButton(
                      onPressed: _onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text('删除歌单'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _doSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(_isEdit ? '保存' : '创建'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openHymnSearch(String keyword) async {
    if (keyword.isEmpty) return;
    final results = widget.repo.searchHymns(keyword);
    if (results.isEmpty) {
      _showToast('未找到相关诗歌');
      return;
    }
    final selected = await showDialog<Hymn>(
      context: context,
      builder: (ctx) => HymnPickDialog(results: results),
    );
    if (selected == null || !mounted) return;
    // 不允许重复添加（按编号判重）
    final number = int.tryParse(selected.hymnNumber) ?? selected.id;
    final exists = _addedHymns.any((e) => e.value == number);
    if (exists) {
      _showToast('该诗歌已在歌单中');
      return;
    }
    setState(() {
      _addedHymns.add(MapEntry(
        ChineseConvertService.instance.toSimplified(selected.title),
        number,
      ));
    });
  }

  Future<void> _onDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「${existing.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, 'delete');
  }

  void _doSave() {
    if (_playlistName.isEmpty) {
      _showToast('请输入歌单名称');
      return;
    }
    final repo = widget.repo;
    final existing = widget.existing;
    if (existing == null) {
      // 新建
      final id = repo.createPlaylist(_playlistName);
      repo.updatePlaylist(id, _playlistName, _addedHymns);
      Navigator.pop(context, 'create');
    } else {
      // 修改
      repo.updatePlaylist(existing.id, _playlistName, _addedHymns);
      Navigator.pop(context, 'save');
    }
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
