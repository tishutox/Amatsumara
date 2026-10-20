import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CommunitiesPage extends StatelessWidget {
  const CommunitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final communities = <String>[
      'Anime & Manga',
      'Gaming Hub',
      'Art & Design',
      'K-Pop & Music',
      'Cosplay',
    ];

    return ListView.separated(
      padding: ContentLayout.pagePadding,
      itemCount: communities.length,
      separatorBuilder: (_, _) => ContentLayout.sectionGap,
      itemBuilder: (context, index) {
        return ContentLayout.widthBox(
          child: SizedBox(
            height: 86,
            child: Card(
              child: Center(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withValues(alpha: 0.15),
                    child: Icon(
                      LucideIcons.usersRoundCollaboration,
                      color: primary,
                    ),
                  ),
                  title: Text(communities[index]),
                  subtitle: Text(
                    '0 new posts',
                    style: TextStyle(color: primary),
                  ),
                  trailing: Icon(LucideIcons.chevronRight, color: primary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
