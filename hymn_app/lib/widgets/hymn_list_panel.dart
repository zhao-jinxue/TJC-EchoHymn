import 'package:flutter/material.dart';

import '../models/hymn.dart';

/// 诗歌列表面板（搜索框 + 列表）
class HymnListPanel extends StatelessWidget {
  final List<Hymn> hymns;
  final String searchKeyword;
  final ValueChanged<String> onSearchChanged;
  final Hymn? currentHymn;
  final void Function(Hymn hymn, int index) onSelect;

  const HymnListPanel({
    super.key,
    required this.hymns,
    required this.searchKeyword,
    required this.onSearchChanged,
    required this.currentHymn,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索编号 / 标题 / 作者 / 分类…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            ),
          ),
        ),
        Expanded(
          child: hymns.isEmpty
              ? const Center(child: Text('未找到匹配的诗歌'))
              : ListView.builder(
                  itemCount: hymns.length,
                  itemBuilder: (context, index) {
                    final hymn = hymns[index];
                    final active = currentHymn?.id == hymn.id;
                    return ListTile(
                      dense: true,
                      selected: active,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Text(
                          hymn.number.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 11,
                            color: active
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      title: Text(
                        hymn.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        hymn.category,
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => onSelect(hymn, index),
                    );
                  },
                ),
        ),
        Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '共 ${hymns.length} 首',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}