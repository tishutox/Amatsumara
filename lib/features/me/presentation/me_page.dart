import 'package:friendship/core/update/apk_update.dart';
import 'package:flutter/material.dart';

const _meColor = Color(0xFF5860C3);

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: _meColor.withValues(alpha: 0.15),
                    child: const Icon(Icons.person_outline, color: _meColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Me',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _meColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hier kommen dein Profil, Einstellungen und Favoriten hin.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ApkUpdate.openLatestApk(context),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Neueste Android APK herunterladen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
