String? profileLocationFromUri(Uri uri) {
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();

  if (uri.scheme == 'lumiiquest') {
    if (uri.host == 'u' && segments.isNotEmpty) {
      return _profileLocation(segments.first);
    }
    if (segments.length >= 2 && segments.first == 'u') {
      return _profileLocation(segments[1]);
    }
    if (segments.length == 1) {
      return _profileLocation(segments.first);
    }
    if (uri.host.isNotEmpty && uri.host != 'u') {
      return _profileLocation(uri.host);
    }
    return null;
  }

  if (!uri.hasScheme && uri.host.isEmpty) {
    if (segments.length >= 2 && segments.first == 'u') {
      return _profileLocation(segments[1]);
    }
    if (segments.length == 1) {
      return _profileLocation(segments.first);
    }
  }

  if (uri.host.toLowerCase() != 'tishutox.github.io') {
    return null;
  }

  final userSegment = segments.lastIndexOf('u');
  if (userSegment >= 0 && userSegment + 1 < segments.length) {
    return _profileLocation(segments[userSegment + 1]);
  }

  final appSegment = segments.lastIndexOf('app');
  if (appSegment >= 0 && appSegment + 1 < segments.length) {
    return _profileLocation(segments[appSegment + 1]);
  }
  return null;
}

String? _profileLocation(String username) {
  final normalized = Uri.decodeComponent(username).trim().replaceFirst('@', '');
  if (normalized.isEmpty || normalized.contains('/')) {
    return null;
  }
  return '/u/${Uri.encodeComponent(normalized)}';
}
