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

  test('ignores unrelated links', () {
    expect(profileLocationFromUri(Uri.parse('https://example.com')), isNull);
  });
}
