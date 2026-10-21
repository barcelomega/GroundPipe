# GroundPipe

GroundPipe is an unofficial Android music player for the [Newgrounds Audio Portal](https://www.newgrounds.com/audio). It browses Newgrounds audio and streams tracks directly from Newgrounds and its CDN.

## Features

- **Discover:** browse Featured, Latest, and Popular audio; filter by genre and search tracks.
- **Recommendations:** get suggestions based on your listening library.
- **Timeline:** browse recent music from artists you follow in the app.
- **Player:** stream audio, control playback from the mini-player or full-screen player, and continue listening in the background.
- **Library:** save tracks to Likes, create local playlists, and cache tracks and artwork for offline access.
- **Artist pages:** explore tracks by Newgrounds artists.
- **Track details:** view Newgrounds metadata and open recommended tracks.
- **All data local:** doesn't requires Newgrounds account for recommendations, playlist and all other features to work.

GroundPipe is an independent client, not an official Newgrounds app. Newgrounds pages are fetched and parsed by the app; audio playback uses the URLs provided by Newgrounds.

## Tech stack

- Flutter and Dart
- Android Media3 for audio playback, media controls, and background playback
- `http` and `html` for Newgrounds requests and HTML parsing
- `provider` for app state management
- `sqflite` for Likes, playlists, and local track metadata
- `webview_flutter` for Newgrounds web flows

## Build and run

Install Flutter and the Android SDK, then run:

```bash
flutter pub get
flutter run
flutter build apk --release
```

Run tests with:

```bash
flutter test
```

## Notes

GroundPipe is not affiliated with or endorsed by Newgrounds. Music and other content remain the property of their respective creators and rights holders. Please follow Newgrounds' terms and each creator's licensing requirements.
