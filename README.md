# Lumii Quest

Cross-platform foundation for an Amino-inspired community hub.

## Goals

- One codebase for Android, iOS, Web, and Desktop (Windows, macOS, Linux)
- Responsive layouts for phone, tablet, and large screens
- Modular structure for future features like feed, chat, communities, and profiles

## Projektstruktur

```text
lib/
	app/
	core/
		responsive/
		theme/
	features/
		home/
		communities/
		profile/
	widgets/
```

## Requirements

- Flutter SDK (stable)
- Android Studio for Android build tools
- Xcode (macOS only) for iOS build tools

## Run

```bash
flutter pub get
flutter run
```

## Run By Platform

```bash
flutter run -d windows
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

## Suggested Next Steps

- Authentication (Email, OAuth)
- Backend (for example Supabase/Firebase or your own API)
- Data models for community, post, comment, and chat
- State management (Riverpod or Bloc)
