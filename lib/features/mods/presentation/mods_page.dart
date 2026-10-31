import 'package:flutter/material.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';

class ModsPage extends StatelessWidget {
  const ModsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.cpu, size: 56, color: primary),
          const SizedBox(height: 16),
          Text(
            'Mods',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Coming soon',
            style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
