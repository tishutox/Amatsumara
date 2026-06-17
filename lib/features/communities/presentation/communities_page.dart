import 'package:flutter/material.dart';

const _communitiesColor = Color(0xFF5860C3);

class CommunitiesPage extends StatelessWidget {
  const CommunitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final communities = <String>[
      'Anime & Manga',
      'Gaming Hub',
      'Art & Design',
      'K-Pop & Music',
      'Cosplay',
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: communities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _communitiesColor.withValues(alpha: 0.15),
              child: const Icon(Icons.groups_2_outlined, color: _communitiesColor),
            ),
            title: Text(communities[index]),
            subtitle: const Text('0 new posts', style: TextStyle(color: _communitiesColor)),
            trailing: const Icon(Icons.chevron_right, color: _communitiesColor),
          ),
        );
      },
    );
  }
}
