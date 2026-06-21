import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/profile/domain/social_platform.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';

void main() {
  test('offers every requested social platform', () {
    expect(
      SocialPlatform.selectable.map((platform) => platform.label),
      [
        'Instagram',
        'X',
        'Twitch',
        'YouTube',
        'Discord',
        'Behance',
        'Dribbble',
        'GitHub',
        'Bluesky',
        'Facebook',
        'Reddit',
        'Xbox',
        'PlayStation',
        'Nintendo',
        'Steam',
        'VKontakte',
        'Pinterest',
      ],
    );
  });

  test('builds platform profile URLs from usernames', () {
    expect(
      SocialPlatform.instagram.profileUrl('@lumii'),
      'https://www.instagram.com/lumii/',
    );
    expect(
      SocialPlatform.github.profileUrl('lumii quest'),
      'https://github.com/lumii%20quest',
    );
    expect(
      SocialPlatform.bluesky.profileUrl('lumii.bsky.social'),
      'https://bsky.app/profile/lumii.bsky.social',
    );
  });

  test('round-trips saved profile colors', () {
    const color = Color(0xFFDB5DC9);
    expect(profileColorToHex(color), '#DB5DC9');
    expect(profileColorFromHex('#DB5DC9', Colors.black), color);
    expect(profileColorFromHex('invalid', Colors.black), Colors.black);
  });
}
