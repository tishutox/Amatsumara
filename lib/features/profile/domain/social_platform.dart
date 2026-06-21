import 'package:flutter/widgets.dart';
import 'package:remixicon/remixicon.dart';

enum SocialPlatform {
  instagram('Instagram', Remix.instagram_line),
  x('X', Remix.twitter_x_line),
  twitch('Twitch', Remix.twitch_line),
  youtube('YouTube', Remix.youtube_line),
  discord('Discord', Remix.discord_line),
  behance('Behance', Remix.behance_line),
  dribbble('Dribbble', Remix.dribbble_line),
  github('GitHub', Remix.github_line),
  bluesky('Bluesky', Remix.bluesky_line),
  facebook('Facebook', Remix.facebook_circle_line),
  reddit('Reddit', Remix.reddit_line),
  xbox('Xbox', Remix.xbox_line),
  playstation('PlayStation', Remix.playstation_line),
  nintendo('Nintendo', Remix.switch_line),
  steam('Steam', Remix.steam_line),
  vkontakte('VKontakte', Remix.vk_line),
  pinterest('Pinterest', Remix.pinterest_line),
  legacy('Link', Remix.link);

  const SocialPlatform(this.label, this.icon);

  final String label;
  final IconData icon;

  static List<SocialPlatform> get selectable => values
      .where((platform) => platform != SocialPlatform.legacy)
      .toList(growable: false);

  static SocialPlatform fromDatabase(String? value) {
    return values.firstWhere(
      (platform) => platform.name == value,
      orElse: () => SocialPlatform.legacy,
    );
  }

  String profileUrl(String username) {
    final clean = username.trim().replaceFirst(RegExp(r'^@'), '');
    final path = Uri.encodeComponent(clean);
    return switch (this) {
      SocialPlatform.instagram => 'https://www.instagram.com/$path/',
      SocialPlatform.x => 'https://x.com/$path',
      SocialPlatform.twitch => 'https://www.twitch.tv/$path',
      SocialPlatform.youtube => 'https://www.youtube.com/@$path',
      SocialPlatform.discord => 'https://discord.com/users/$path',
      SocialPlatform.behance => 'https://www.behance.net/$path',
      SocialPlatform.dribbble => 'https://dribbble.com/$path',
      SocialPlatform.github => 'https://github.com/$path',
      SocialPlatform.bluesky => 'https://bsky.app/profile/$path',
      SocialPlatform.facebook => 'https://www.facebook.com/$path',
      SocialPlatform.reddit => 'https://www.reddit.com/user/$path/',
      SocialPlatform.xbox => 'https://account.xbox.com/profile?gamertag=$path',
      SocialPlatform.playstation => 'https://psnprofiles.com/$path',
      SocialPlatform.nintendo => 'https://accounts.nintendo.com/',
      SocialPlatform.steam => 'https://steamcommunity.com/id/$path',
      SocialPlatform.vkontakte => 'https://vk.com/$path',
      SocialPlatform.pinterest => 'https://www.pinterest.com/$path/',
      SocialPlatform.legacy => clean,
    };
  }
}
