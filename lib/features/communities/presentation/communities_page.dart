import 'package:flutter/material.dart';

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
            leading: const CircleAvatar(child: Icon(Icons.groups_2_outlined)),
            title: Text(communities[index]),
            subtitle: const Text('0 neue Beitraege'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
