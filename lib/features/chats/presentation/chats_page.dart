import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:flutter/material.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: ContentLayout.pagePadding,
      children: const [
        _ChatContentWidth(
          child: _ChatTile(
            name: 'Lena',
            lastMessage: 'Can you check the new post?',
          ),
        ),
        ContentLayout.sectionGap,
        _ChatContentWidth(
          child: _ChatTile(
            name: 'Kai',
            lastMessage: 'I am working on the community guidelines right now.',
          ),
        ),
        ContentLayout.sectionGap,
        _ChatContentWidth(
          child: _ChatTile(name: 'Mina', lastMessage: 'Voice chat tonight?'),
        ),
      ],
    );
  }
}

class _ChatContentWidth extends StatelessWidget {
  const _ChatContentWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ContentLayout.widthBox(child: SizedBox(height: 86, child: child));
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.name, required this.lastMessage});

  final String name;
  final String lastMessage;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.12),
          child: Icon(Icons.person_outline, color: primary),
        ),
        title: Text(name),
        subtitle: Text(lastMessage),
        trailing: Icon(Icons.chevron_right, color: primary),
      ),
    );
  }
}
