import 'package:flutter/material.dart';

/// A small primary-colored section title followed by a Card holding [children].
///
/// This is Lumii's canonical "section + Card" layout, shared by the Settings
/// page and the Account page.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.dividerIndent = 56,
  });

  final String title;
  final List<Widget> children;

  /// Horizontal inset of the dividers between rows. Use 16 for sections whose
  /// rows have no leading icon, 56 when rows have a 40px leading icon.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: dividerIndent, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
