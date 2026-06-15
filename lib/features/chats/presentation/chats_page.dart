import 'package:flutter/material.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _ChatTile(name: 'Lena', lastMessage: 'Kannst du den neuen Post checken?'),
        SizedBox(height: 10),
        _ChatTile(name: 'Kai', lastMessage: 'Ich baue gerade die Community-Regeln.'),
        SizedBox(height: 10),
        _ChatTile(name: 'Mina', lastMessage: 'Heute Abend Voice Chat?'),
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
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(name),
        subtitle: Text(lastMessage),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
