import 'package:flutter/material.dart';

const _chatsColor = Color(0xFFEF372C);

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _ChatTile(name: 'Lena', lastMessage: 'Can you check the new post?'),
        SizedBox(height: 10),
        _ChatTile(name: 'Kai', lastMessage: 'I am working on the community guidelines right now.'),
        SizedBox(height: 10),
        _ChatTile(name: 'Mina', lastMessage: 'Voice chat tonight?'),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.name, required this.lastMessage});

  final String name;
  final String lastMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _chatsColor.withValues(alpha: 0.12),
          child: const Icon(Icons.person_outline, color: _chatsColor),
        ),
        title: Text(name),
        subtitle: Text(lastMessage),
        trailing: const Icon(Icons.chevron_right, color: _chatsColor),
      ),
    );
  }
}
