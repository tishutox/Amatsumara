# Friendship

Cross-platform Grundgeruest fuer einen Amino-inspirierten Community-Hub.

## Ziele

- Eine Codebase fuer Android, iOS, Web und Desktop (Windows, macOS, Linux)
- Responsive Layouts fuer Handy, Tablet und grosse Bildschirme
- Modulare Struktur fuer spaetere Features wie Feed, Chat, Communitys und Profile

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

## Voraussetzungen

- Flutter SDK (stable)
- Android Studio fuer Android Build Tools
- Xcode (nur auf macOS) fuer iOS Build Tools

## Starten

```bash
flutter pub get
flutter run
```

## Plattform-spezifisch starten

```bash
flutter run -d windows
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

## Naechste sinnvolle Schritte

- Authentifizierung (Email, OAuth)
- Backend (z. B. Supabase/Firebase oder eigenes API)
- Datenmodelle fuer Community, Post, Kommentar, Chat
- State-Management (Riverpod oder Bloc)
