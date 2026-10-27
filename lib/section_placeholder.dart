import 'package:flutter/material.dart';

/// 尚未落地的分区（听书 / 漫画 / 小说）的诚实占位页：
/// 只说明开发状态与规划，不放任何假数据、假列表。
class SectionPlaceholder extends StatelessWidget {
  const SectionPlaceholder({
    super.key,
    required this.title,
    required this.icon,
    required this.plan,
  });

  final String title;
  final IconData icon;
  final String plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.primary),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Chip(
              label: const Text('开发中'),
              avatar: Icon(
                Icons.construction_rounded,
                size: 16,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              plan,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
