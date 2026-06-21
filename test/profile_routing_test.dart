import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/core/routing/app_router.dart';

void main() {
  test('maps the public web profile URL to an app route', () {
    final location = profileLocationFromUri(
      Uri.parse('https://tishutox.github.io/Lumii/app/u/Alice'),
    );

    expect(location, '/u/Alice');
  });

  test('maps the custom app scheme to an app route', () {
    final location = profileLocationFromUri(Uri.parse('lumiiquest://u/Alice'));

    expect(location, '/u/Alice');
  });

  test('maps the legacy custom scheme without the u segment', () {
    expect(
      profileLocationFromUri(Uri.parse('lumiiquest:///Alice')),
      '/u/Alice',
    );
  });

  test('maps a legacy public profile URL to an app route', () {
    expect(
      profileLocationFromUri(
        Uri.parse('https://tishutox.github.io/Lumii/app/Alice'),
      ),
      '/u/Alice',
    );
  });

  test('maps a relative username link to an app route', () {
    expect(profileLocationFromUri(Uri.parse('/Alice')), '/u/Alice');
  });

  test('ignores unrelated links', () {
    expect(profileLocationFromUri(Uri.parse('https://example.com')), isNull);
    expect(
      profileLocationFromUri(Uri.parse('https://example.com/u/Alice')),
      isNull,
    );
  });
}
