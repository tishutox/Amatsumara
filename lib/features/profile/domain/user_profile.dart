import 'package:flutter/material.dart';

enum BioAlignment {
  left,
  center,
  right,
  justify;

  String get label => switch (this) {
    BioAlignment.left => 'Left',
    BioAlignment.center => 'Center',
    BioAlignment.right => 'Right',
    BioAlignment.justify => 'Justify',
  };

  TextAlign get textAlign => switch (this) {
    BioAlignment.left => TextAlign.left,
    BioAlignment.center => TextAlign.center,
    BioAlignment.right => TextAlign.right,
    BioAlignment.justify => TextAlign.justify,
  };

  static BioAlignment fromDatabase(String? value) {
    return BioAlignment.values.firstWhere(
      (alignment) => alignment.name == value,
      orElse: () => BioAlignment.left,
    );
  }
}

class ProfileLink {
  const ProfileLink({required this.label, required this.url});

  final String label;
  final String url;
}

class ProfileMention {
  const ProfileMention({
    required this.username,
    required this.displayName,
    required this.tag,
    this.avatarUrl,
  });

  final String username;
  final String displayName;
  final String tag;
  final String? avatarUrl;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.bioAlignment,
    required this.links,
    required this.mentions,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final BioAlignment bioAlignment;
  final String? avatarUrl;
  final String? bannerUrl;
  final List<ProfileLink> links;
  final List<ProfileMention> mentions;
}

class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.bio,
    required this.bioAlignment,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.links,
    required this.mentions,
  });

  final String displayName;
  final String bio;
  final BioAlignment bioAlignment;
  final String? avatarUrl;
  final String? bannerUrl;
  final List<ProfileLink> links;
  final List<ProfileMention> mentions;
}
